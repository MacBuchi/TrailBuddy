-- Patch 015 (#120): Fahrdatum für eine Datei ohne Zeiten.
--
-- Eine Datei ohne Fahrzeiten geht als `planned` hoch: Qualität 0,1, sie
-- belegt keine Fahrt (has_ridden) und setzt keine Meldung auf „offen"
-- (Patch 011). Seit 0.58.0 kann der Fahrer beim Import „Gefahren am …"
-- eintragen (Betreiber, 2026-09-30: „Falls das Attribut fehlt, sollte der
-- Buddy das Datum eintragen"). Dann bleibt die Aufzeichnung `planned`
-- — die Linie ist gezeichnet, nicht gemessen, und wird nie zur Linie
-- des Trails —, trägt aber das Datum in `recorded_at`, und genau das
-- heißt „gefahren": has_ridden zählt sie, Meldungen dazu sind bestätigt,
-- und Schritt 8 setzt die eigene Meldung zum Fahrdatum auf „offen".
--
-- Keine neue Quelle (`dated` o. ä.): Ältere Clients kennen den Wert
-- nicht, das erzwänge eine Pflicht-Aktualisierung. Keine neue Spalte:
-- `recorded_at` IST das Fahrdatum, und `planned` hatte bisher nie eins.
set search_path = public, extensions;

-- 1. Altlast absichern: Die App schickt bei `planned` seit jeher kein
--    Datum. Trägt eine Zeile trotzdem eins (unplausible Zeiten aus der
--    Datei), fällt es weg — sonst zählte sie ab hier still als gefahren.
update public.trail_recordings set recorded_at = null
 where source = 'planned' and recorded_at is not null;

-- 2. Gefahren heißt: nicht `planned`, oder `planned` mit Fahrdatum.
-- Hat [uid] den Trail selbst GEFAHREN? Eine eigene Aufzeichnung, die
-- nicht `planned` ist — eine Datei ohne Fahrzeiten belegt keine Fahrt
-- (Patch 011, 013) —, oder eine geplante MIT eingetragenem Fahrdatum
-- (Patch 015, #120: der Fahrer sagt ausdrücklich, dass er dort war). Die
-- Grundlage von „bestätigt" (trail_reports).
create or replace function app_internal.has_ridden(uid uuid, trail uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from trail_recordings r
     where r.trail_id = trail and r.user_id = uid
       and (r.source <> 'planned' or r.recorded_at is not null));
$$;
revoke all on function app_internal.has_ridden(uuid, uuid) from public, anon, authenticated;

-- 3. contribute_recording: dieselbe Funktion wie in schema.sql, geändert
--    ist nur die Bedingung in Schritt 8. Gleiche Signatur, die Rechte
--    bleiben beim Ersetzen stehen.
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
  ride_at timestamptz;
  last_report record;
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

  -- 7. Der Beitrag, falls er fehlt.
  insert into trail_details (trail_id, user_id)
  values (target, uid)
  on conflict (trail_id, user_id) do nothing;

  -- 8. Die eigene Meldung auf „offen" (Patch 013; bis dahin der Status
  -- am Beitrag): Wer den Trail fährt, hat ihn befahrbar vorgefunden —
  -- und zwar AN DEM TAG, an dem er gefahren ist. Eine GPX-Datei von 2024
  -- verdrängt keine Meldung von gestern (Betreiber, 2026-09-30). Nur
  -- wenn der Aufrufer schon etwas gemeldet hat und das nicht schon ein
  -- bestätigtes „offen" ist; nicht bei `planned` (Patch 011) — außer
  -- mit eingetragenem Fahrdatum (Patch 015, #120).
  if contribute_recording.source <> 'planned' or contribute_recording.recorded_at is not null then
    ride_at := least(coalesce(contribute_recording.recorded_at, now()), now());
    select r.status, r.confirmed, r.reported_at into last_report
      from trail_reports r
     where r.trail_id = target and r.user_id = uid and r.kind = 'status'
     order by r.reported_at desc, r.created_at desc
     limit 1;
    if found and ride_at > last_report.reported_at
       and not (last_report.status = 'open' and last_report.confirmed) then
      perform app_internal.put_report(uid, target, 'status', 'open', null, true, ride_at, null);
    end if;
  end if;

  return target;
end $$;
