-- Patch 002: Höhen je Aufzeichnung (Issue #14).
--
-- Bis hierher gingen an contribute_recording nur lon/lat; die Höhen aus
-- der GPX-Datei las die App und warf sie weg. Jetzt trägt jede
-- Aufzeichnung eine Höhe je Punkt (oder keine), und der Client rechnet
-- daraus Anstieg, Abstieg, Gefälle und das Profil (trail_elevation.dart).
--
-- Nicht brechend: `eles` hat eine Vorgabe, Clients vor 0.3.0 rufen
-- dieselbe Funktion ohne den Namen auf (PostgREST löst über die Namen
-- auf). Die alte Signatur muss trotzdem weg — `create or replace` mit
-- anderer Parameterliste legte eine ZWEITE Funktion daneben, und mit
-- vier Namen im Aufruf wären dann beide passend (PGRST203).
--
-- Die Sicht bekommt `ele` hinten angehängt; `create or replace view`
-- darf Spalten nur am Ende ergänzen, der Grant bleibt stehen.
set search_path = public, extensions;

alter table public.trail_recordings add column ele real[];
alter table public.trail_recordings add constraint trail_recordings_ele_check check (
  ele is null or (
    array_length(ele, 1) = st_npoints(geom::geometry)
    and array_position(ele, null) is null
    and -500 <= all(ele) and 9000 >= all(ele)));

drop function public.contribute_recording(double precision[], text, timestamptz, uuid);

create or replace function public.contribute_recording(
  coords double precision[],
  source text,
  recorded_at timestamptz default null,
  client_id uuid default null,
  -- Eine Höhe je Punkt aus `coords`, oder null (Patch 002). Mit Vorgabe,
  -- damit Clients vor 0.3.0 dieselbe Funktion ohne den Namen treffen.
  eles double precision[] default null)
returns uuid
language plpgsql security definer set search_path = public, extensions as $$
declare
  p app_internal.match_params := app_internal.match_params();
  uid uuid := auth.uid();
  npts integer;
  line geometry;
  geog geography;
  len double precision;
  srid integer;
  cand geometry;
  existing uuid;
  best_trail uuid;
  best_cov double precision := -1;
  best_reversed boolean := false;
  rec record;
  res app_internal.match_result;
  ov_trails uuid[] := '{}';
  ov_ab real[] := '{}';
  ov_ba real[] := '{}';
  target uuid;
  q real;
  ele_clean real[];
begin
  if uid is null then
    raise exception 'Nicht angemeldet' using errcode = '28000';
  end if;
  if source is null or source not in ('app', 'import', 'planned') then
    raise exception 'Unbekannte Quelle: %', coalesce(source, 'null')
      using errcode = '22023', hint = 'app, import oder planned';
  end if;
  npts := coalesce(array_length(coords, 1), 0);
  if npts < 4 or npts % 2 <> 0 then
    raise exception 'Mindestens zwei Punkte als [lon, lat, lon, lat, …] erwartet'
      using errcode = '22023';
  end if;
  if exists (select 1 from generate_series(1, npts / 2) i
              where coords[2 * i - 1] not between -180 and 180
                 or coords[2 * i] not between -90 and 90) then
    raise exception 'Koordinate außerhalb von WGS84 (lon ±180, lat ±90)'
      using errcode = '22023';
  end if;
  -- Höhen: eine je Punkt oder gar keine. Die App schickt null, sobald
  -- einem Punkt die Höhe fehlt; hier wird nur noch geprüft, nicht geraten.
  if eles is not null then
    if coalesce(array_length(eles, 1), 0) <> npts / 2 then
      raise exception 'Höhen: % Werte für % Punkte', coalesce(array_length(eles, 1), 0), npts / 2
        using errcode = '22023';
    end if;
    if array_position(eles, null) is not null
       or exists (select 1 from unnest(eles) e where e not between -500 and 9000) then
      raise exception 'Höhe fehlt oder liegt außerhalb von −500 bis 9000 m'
        using errcode = '22023';
    end if;
  end if;

  -- 2. Idempotenz (Ausgangskorb): derselbe Auftrag noch einmal ⇒ dieselbe
  -- Antwort, keine zweite Aufzeichnung.
  if contribute_recording.client_id is not null then
    select r.trail_id into existing
      from trail_recordings r
     where r.user_id = uid and r.client_id = contribute_recording.client_id;
    if found then
      return existing;
    end if;
  end if;

  -- Rate (4.6): reicht jedem echten Nutzer, auch für einen Bestandsimport
  -- an einem Abend, und macht das Sondieren als Fläche unattraktiv.
  if (select count(*) from trail_recordings r
       where r.user_id = uid and r.created_at > now() - interval '1 day') >= p.daily_limit then
    raise exception 'Tageslimit von % Aufzeichnungen erreicht', p.daily_limit
      using errcode = '54000';
  end if;

  -- Doppelte Punkte fallen weg (Locus schreibt sie an Pausen) — samt
  -- ihrer Höhe. Bis Patch 002 stand hier st_removerepeatedpoints; das
  -- kürzt nur die Linie, und die Höhen liefen danach um einen Punkt
  -- versetzt neben ihr her.
  select st_setsrid(st_makeline(array_agg(st_makepoint(d.x, d.y) order by d.i)), 4326),
         case when eles is null then null else array_agg(d.z::real order by d.i) end
    into line, ele_clean
    from (
      select r.i, r.x, r.y, r.z,
             lag(r.x) over (order by r.i) as px, lag(r.y) over (order by r.i) as py
        from (select g.i, coords[2 * g.i - 1] as x, coords[2 * g.i] as y, eles[g.i] as z
                from generate_series(1, npts / 2) as g(i)) r
    ) d
   where d.px is null or d.x <> d.px or d.y <> d.py;
  if st_npoints(line) < 2 then
    raise exception 'Mindestens zwei verschiedene Punkte erwartet' using errcode = '22023';
  end if;
  geog := line::geography;
  len := st_length(geog);
  if len < p.min_trail_m then
    raise exception 'Aufzeichnung zu kurz: % m, ein Trail hat mindestens % m',
      round(len), p.min_trail_m::integer using errcode = '22023';
  end if;

  -- 3./4. Abgleich gegen die Vertreterinnen aller Trails in Reichweite.
  srid := app_internal.utm_srid(line);
  cand := st_transform(line, srid);
  for rec in
    with near as (
      select distinct r.trail_id
        from trail_recordings r
       where st_dwithin(r.geom, geog, p.corridor_m)
    )
    select n.trail_id, b.geom, b.reversed
      from near n
      cross join lateral (
        select r.geom, r.reversed
          from trail_recordings r
         where r.trail_id = n.trail_id
         order by r.quality desc, r.created_at asc
         limit 1) b
  loop
    res := app_internal.match_lines(cand, st_transform(rec.geom::geometry, srid));
    if res.class in ('same', 'same-reversed') then
      if least(res.cov_ab, res.cov_ba) > best_cov then
        best_trail := rec.trail_id;
        best_cov := least(res.cov_ab, res.cov_ba);
        best_reversed := (res.class = 'same-reversed') <> rec.reversed;
      end if;
    elsif greatest(res.cov_ab, res.cov_ba) >= p.overlap_min then
      ov_trails := ov_trails || rec.trail_id;
      ov_ab := ov_ab || res.cov_ab;
      ov_ba := ov_ba || res.cov_ba;
    end if;
  end loop;

  -- 5. Anhängen oder neu — nur „gleich" verschmilzt.
  if best_trail is not null then
    target := best_trail;
  else
    insert into trails default values returning id into target;
    insert into app_internal.trail_overlaps (a, b, coverage_ab, coverage_ba)
      select target, t, ab, ba
        from unnest(ov_trails, ov_ab, ov_ba) as u(t, ab, ba);
  end if;

  -- 6. Die Aufzeichnung.
  q := case source when 'app' then 0.6 when 'import' then 0.4 else 0.1 end;
  begin
    insert into trail_recordings
      (trail_id, user_id, geom, recorded_at, source, reversed, quality, client_id, ele)
    values
      (target, uid, geog, recorded_at, source, best_reversed, q, contribute_recording.client_id, ele_clean);
  exception when unique_violation then
    -- Wettlauf zweier Wiedervorlagen desselben Auftrags: Die erste hat
    -- gewonnen, ihre Antwort gilt. Ein eben angelegter leerer Trail geht
    -- wieder weg.
    if best_trail is null then
      delete from trails where id = target;
    end if;
    select r.trail_id into existing
      from trail_recordings r
     where r.user_id = uid and r.client_id = contribute_recording.client_id;
    return existing;
  end;

  -- 7. Der Beitrag.
  insert into trail_details (trail_id, user_id)
  values (target, uid)
  on conflict (trail_id, user_id) do update
    set status = 'open', status_at = now()
    where trail_details.status <> 'open';

  return target;
end $$;

revoke all on function public.contribute_recording(double precision[], text, timestamptz, uuid, double precision[])
  from public, anon;
grant execute on function public.contribute_recording(double precision[], text, timestamptz, uuid, double precision[])
  to authenticated;

create or replace view public.recordings_visible
with (security_invoker = true) as
  select id, trail_id, user_id, source, recorded_at, reversed, quality, created_at,
         st_asgeojson(geom::geometry) as geojson,
         st_length(geom) as length_m,
         ele
    from public.trail_recordings;
