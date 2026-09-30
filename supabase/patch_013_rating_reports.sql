-- Patch 013 (#101): Bewertung, Meldungen und Zustände
-- (docs/konzept-rework.md, Abschnitt 9 — Entscheidungen des Betreibers
-- vom 2026-09-30).
--
-- 1. trail_details.rating: 1–5 Sterne je Beitrag. Ältere Clients
--    schreiben per upsert nur ihre Spalten und lassen sie stehen
--    (matcher_check.sql Block 23 prüft genau diesen Upsert).
-- 2. trail_reports: die Meldung (bisher „Status" am Beitrag) und der
--    Zustand 1–5 als Verlauf. Schreiben darf, wer den Trail SIEHT, nur
--    über report_trail(); bestätigt ist eine Angabe, wenn der Meldende
--    den Trail gefahren hat (nicht nur geplant) oder vor Ort war — das
--    „vor Ort" prüft die App, gespeichert wird nur das Ergebnis.
--    90 Tage Verlauf, die jüngste je Person, Art und Bestätigung bleibt.
-- 3. Alte Clients (bis 0.48.0) lesen und schreiben weiter
--    trail_details.status: Trigger gleichen in beide Richtungen ab, die
--    bisherigen Status werden als Meldungen übernommen.
-- 4. Push nur noch für BESTÄTIGTE Meldungen (push_on_report ersetzt
--    push_on_status); im Text heißt es „Meldung" statt „Statusmeldung".
-- 5. contribute_recording setzt die eigene Meldung zum FAHRDATUM auf
--    „offen", nicht zur Importzeit — eine Datei von 2024 verdrängt
--    keine Meldung von gestern.
-- 6. withdraw_contribution löscht die eigenen Meldungen mit.
--
-- Die Funktionen sind dieselben wie in schema.sql. Nichts bricht für
-- alte Clients, minimum_supported_version bleibt.
set search_path = public, extensions;

-- 1. Bewertung ----------------------------------------------------------
alter table public.trail_details
  add column if not exists rating smallint
  constraint trail_details_rating_check check (rating between 1 and 5);
comment on column public.trail_details.status is
  'Veraltet seit Patch 013: die Meldung steht in trail_reports; bleibt für Clients bis 0.48.0 und wird abgeglichen.';

-- 2. Meldungen und Zustände ----------------------------------------------
create table public.trail_reports (
  id uuid primary key default gen_random_uuid(),
  trail_id uuid not null,
  user_id uuid not null,
  kind text not null check (kind in ('status', 'condition')),
  status text check (status in ('open', 'closed', 'destroyed', 'changed')),
  condition smallint check (condition between 1 and 5),
  confirmed boolean not null,
  -- Wann die Angabe gemacht wurde — vom Gerät, damit eine Meldung aus
  -- dem Ausgangskorb ihre echte Zeit behält; der Server kappt auf now().
  reported_at timestamptz not null,
  created_at timestamptz not null default now(),
  -- Ausgangskorb: derselbe Auftrag zweimal legt keine zweite Zeile an.
  client_id uuid,
  constraint trail_reports_value_check check (
    (kind = 'status') = (status is not null)
    and (kind = 'condition') = (condition is not null)),
  constraint trail_reports_user_id_fkey foreign key (user_id)
    references public.profiles(id) on delete cascade,
  constraint trail_reports_trail_id_fkey foreign key (trail_id)
    references public.trails(id) on delete cascade
);
create index trail_reports_trail_idx on public.trail_reports (trail_id);
create index trail_reports_latest_idx
  on public.trail_reports (trail_id, user_id, kind, confirmed, reported_at desc);
create index trail_reports_user_idx on public.trail_reports (user_id);
create unique index trail_reports_client_id_key
  on public.trail_reports (user_id, client_id, kind)
  where client_id is not null;

alter table public.trail_reports enable row level security;
create policy reports_select on public.trail_reports for select
  using (user_id = auth.uid()
     or (app_internal.are_friends(user_id, auth.uid())
         and app_internal.contributor_shares(user_id, trail_id)
         and app_internal.can_see_trail(auth.uid(), trail_id)));
create policy reports_delete_own on public.trail_reports for delete
  using (user_id = auth.uid());
-- Erst alles weg (Legacy-Vorgabe auto_expose), dann gezielt zurück.
revoke all on public.trail_reports from anon, authenticated;
grant select, delete on public.trail_reports to authenticated;

-- Funktionen -------------------------------------------------------------
create or replace function app_internal.has_ridden(uid uuid, trail uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from trail_recordings r
     where r.trail_id = trail and r.user_id = uid and r.source <> 'planned');
$$;
revoke all on function app_internal.has_ridden(uuid, uuid) from public, anon, authenticated;

create or replace function app_internal.put_report(
  p_user uuid, p_trail uuid, p_kind text, p_status text, p_condition integer,
  p_confirmed boolean, p_at timestamptz, p_client_id uuid)
returns boolean
language plpgsql security definer set search_path = public as $$
begin
  insert into trail_reports (trail_id, user_id, kind, status, condition, confirmed, reported_at, client_id)
  values (p_trail, p_user, p_kind, p_status, p_condition, p_confirmed,
          least(coalesce(p_at, now()), now()), p_client_id)
  on conflict (user_id, client_id, kind) where client_id is not null do nothing;
  return found;
end $$;
revoke all on function app_internal.put_report(uuid, uuid, text, text, integer, boolean, timestamptz, uuid)
  from public, anon, authenticated;

create or replace function app_internal.sweep_old_reports()
returns integer
language plpgsql security definer set search_path = public as $$
declare
  n integer;
begin
  delete from trail_reports old
   where old.reported_at < now() - interval '90 days'
     and exists (select 1 from trail_reports newer
                  where newer.trail_id = old.trail_id
                    and newer.user_id = old.user_id
                    and newer.kind = old.kind
                    and newer.confirmed = old.confirmed
                    and (newer.reported_at, newer.created_at, newer.id)
                      > (old.reported_at, old.created_at, old.id));
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function app_internal.sweep_old_reports() from public, anon, authenticated;

create or replace function app_internal.reports_from_details()
returns trigger
language plpgsql security definer set search_path = public, app_internal as $$
begin
  if pg_trigger_depth() > 1 then return new; end if;
  if new.status = 'open' and new.status_at is null then return new; end if;
  if tg_op = 'UPDATE'
     and new.status is not distinct from old.status
     and new.status_at is not distinct from old.status_at then
    return new;
  end if;
  perform app_internal.put_report(new.user_id, new.trail_id, 'status', new.status, null,
                                  app_internal.has_ridden(new.user_id, new.trail_id),
                                  coalesce(new.status_at, now()), null);
  return new;
end $$;
revoke all on function app_internal.reports_from_details() from public, anon, authenticated;

create or replace function app_internal.reports_to_details()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.kind = 'status' and new.confirmed then
    update trail_details d
       set status = new.status, status_at = new.reported_at
     where d.trail_id = new.trail_id and d.user_id = new.user_id
       and new.reported_at > coalesce(d.status_at, '-infinity'::timestamptz);
  end if;
  return new;
end $$;
revoke all on function app_internal.reports_to_details() from public, anon, authenticated;

create or replace function app_internal.push_on_report()
returns trigger
language plpgsql security definer set search_path = public, app_internal as $$
declare
  prev text;
begin
  if new.kind <> 'status' or not new.confirmed then return new; end if;
  if exists (select 1 from trail_reports r
              where r.trail_id = new.trail_id and r.user_id = new.user_id
                and r.kind = 'status' and r.confirmed and r.id <> new.id
                and r.reported_at > new.reported_at) then
    return new;
  end if;
  select r.status into prev
    from trail_reports r
   where r.trail_id = new.trail_id and r.user_id = new.user_id
     and r.kind = 'status' and r.confirmed and r.id <> new.id
   order by r.reported_at desc, r.created_at desc
   limit 1;
  if not found and new.status = 'open' then return new; end if;
  if found and prev = new.status then return new; end if;
  insert into app_internal.push_outbox (recipient_id, kind, trail_id, status, due_at)
    select r.recipient_id, 'trail_status', new.trail_id, new.status,
           app_internal.push_due_at(now())
      from app_internal.push_recipients(new.user_id, new.trail_id) r
  on conflict (recipient_id, kind, trail_id) do update
    set status = excluded.status,
        due_at = app_internal.push_due_at(push_outbox.created_at);
  return new;
end $$;
revoke all on function app_internal.push_on_report() from public, anon, authenticated;

create or replace function app_internal.push_flush()
returns integer
language plpgsql security definer
set search_path = public, app_internal, vault, net as $$
declare
  base_url text;
  job_secret text;
  service_key text;
  payload jsonb;
  sent integer;
begin
  select decrypted_secret into base_url
    from vault.decrypted_secrets where name = 'push_functions_url';
  select decrypted_secret into job_secret
    from vault.decrypted_secrets where name = 'push_job_secret';
  select decrypted_secret into service_key
    from vault.decrypted_secrets where name = 'push_service_key';

  -- Nicht eingerichtet: Fällige Zeilen trotzdem wegräumen und still
  -- zurück — sonst wüchse der Korb bis zur Einrichtung, und der erste
  -- Lauf feuerte einen Schwall über Meldungen von vorgestern ab.
  if base_url is null or job_secret is null or service_key is null then
    delete from app_internal.push_outbox where due_at <= now();
    return 0;
  end if;

  with due as (
    delete from app_internal.push_outbox
     where due_at <= now()
    returning recipient_id, kind, trail_id, status
  ),
  grouped as (
    select recipient_id,
           count(*) filter (where kind = 'trail_status') as statuses,
           count(*) filter (where kind = 'trail_note') as notes,
           count(distinct trail_id) as trails,
           min(trail_id::text) as trail_id,
           -- Das Statuswort, wenn es genau EINE Statusmeldung ist.
           max(status) filter (where kind = 'trail_status') as status
      from due group by recipient_id
  )
  select jsonb_agg(jsonb_build_object(
           'token', d.token,
           'title', case
             when g.statuses > 0 and g.notes > 0
               then 'Deine Buddys haben etwas gemeldet'
             when g.statuses > 1
               then g.statuses || ' Meldungen von deinen Buddys'
             when g.statuses = 1
               then 'Ein Buddy meldet einen Trail als ' || case g.status
                 when 'closed' then 'gesperrt'
                 when 'destroyed' then 'zerstört'
                 when 'changed' then 'verändert'
                 else 'wieder offen' end
             when g.notes > 1
               then g.notes || ' neue Hinweise von deinen Buddys'
             else 'Neuer Hinweis von einem Buddy'
           end,
           'body', case
             when g.statuses > 0 and g.notes > 0 then
               g.statuses || (case when g.statuses = 1 then ' Meldung'
                                   else ' Meldungen' end) || ' und ' ||
               g.notes || (case when g.notes = 1 then ' Hinweis'
                                else ' Hinweise' end) ||
               (case when g.trails > 1 then ' an ' || g.trails || ' Trails'
                     else '' end)
             when g.trails > 1 then 'An ' || g.trails || ' Trails'
             else 'Tippen zeigt den Trail'
           end,
           'route', case
             when g.trails = 1 then '/trail/' || g.trail_id
             else '/trails'
           end))
    into payload
    from grouped g
    join public.push_devices d on d.user_id = g.recipient_id;

  if payload is null then return 0; end if;
  select jsonb_array_length(payload) into sent;

  -- Asynchron (pg_net): Die Antwort landet in net._http_response, der
  -- Cron-Lauf wartet nicht. Ein fehlgeschlagener Versand ist verloren —
  -- eine Wiedervorlage brächte im Zweifel dieselbe Meldung zweimal.
  perform net.http_post(
    url := base_url || '/send-push',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || service_key,
      'x-push-secret', job_secret),
    body := jsonb_build_object('messages', payload));
  return sent;
end $$;
revoke all on function app_internal.push_flush() from public, anon, authenticated;

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
  -- bestätigtes „offen" ist; nicht bei `planned` (Patch 011).
  if contribute_recording.source <> 'planned' then
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

create or replace function public.withdraw_contribution(trail_id uuid)
returns integer
language plpgsql security invoker set search_path = public as $$
declare
  uid uuid := auth.uid();
  n integer;
begin
  if uid is null then
    raise exception 'Nicht angemeldet' using errcode = '28000';
  end if;
  delete from trail_recordings r
   where r.trail_id = withdraw_contribution.trail_id and r.user_id = uid;
  get diagnostics n = row_count;
  delete from trail_notes t
   where t.trail_id = withdraw_contribution.trail_id and t.user_id = uid;
  delete from trail_reports m
   where m.trail_id = withdraw_contribution.trail_id and m.user_id = uid;
  delete from trail_details d
   where d.trail_id = withdraw_contribution.trail_id and d.user_id = uid;
  return n;
end $$;

create or replace function public.report_trail(
  trail_id uuid,
  status text default null,
  condition integer default null,
  on_site boolean default false,
  reported_at timestamptz default null,
  client_id uuid default null)
returns void
language plpgsql security definer set search_path = public, app_internal as $$
declare
  uid uuid := auth.uid();
  conf boolean;
begin
  if uid is null then
    raise exception 'Nicht angemeldet' using errcode = '28000';
  end if;
  if report_trail.status is null and report_trail.condition is null then
    raise exception 'Weder Meldung noch Zustand' using errcode = '22023';
  end if;
  if report_trail.trail_id is null
     or not app_internal.can_see_trail(uid, report_trail.trail_id) then
    raise exception 'Trail nicht sichtbar' using errcode = '42501';
  end if;
  -- Schutz gegen Fluten, kein gemessener Wert: 200 Zeilen in 24 h liegen
  -- weit über jedem echten Gebrauch (derselbe Code wie das Tageslimit der
  -- Aufzeichnungen, die App kennt ihn schon).
  if (select count(*) from trail_reports m
       where m.user_id = uid and m.created_at > now() - interval '1 day') >= 200 then
    raise exception 'Tageslimit von 200 Meldungen erreicht' using errcode = '54000';
  end if;
  conf := coalesce(report_trail.on_site, false)
          or app_internal.has_ridden(uid, report_trail.trail_id);
  if report_trail.status is not null then
    perform app_internal.put_report(uid, report_trail.trail_id, 'status', report_trail.status,
                                    null, conf, report_trail.reported_at, report_trail.client_id);
  end if;
  if report_trail.condition is not null then
    perform app_internal.put_report(uid, report_trail.trail_id, 'condition', null,
                                    report_trail.condition, conf, report_trail.reported_at,
                                    report_trail.client_id);
  end if;
end $$;

revoke all on function public.report_trail(uuid, text, integer, boolean, timestamptz, uuid) from public, anon;
grant execute on function public.report_trail(uuid, text, integer, boolean, timestamptz, uuid) to authenticated;

-- 3. Bisherige Status als Meldungen übernehmen — VOR den Triggern, damit
-- das Übernehmen weder Push auslöst noch an den Beiträgen etwas ändert.
-- Bestätigt, wer den Trail gefahren hat (nicht nur geplant); die Zeit
-- ist die der Meldung, ohne Datum die des Beitrags.
insert into public.trail_reports (trail_id, user_id, kind, status, confirmed, reported_at, created_at)
select d.trail_id, d.user_id, 'status', d.status,
       app_internal.has_ridden(d.user_id, d.trail_id),
       least(coalesce(d.status_at, d.created_at), now()),
       now()
  from public.trail_details d
 where d.status_at is not null or d.status <> 'open';

-- 4. Push hängt jetzt an den Meldungen.
drop trigger if exists push_on_status_trg on public.trail_details;
drop function if exists app_internal.push_on_status();

create trigger trail_details_reports
  after insert or update of status, status_at on public.trail_details
  for each row execute function app_internal.reports_from_details();
create trigger trail_reports_details
  after insert on public.trail_reports
  for each row execute function app_internal.reports_to_details();
create trigger push_on_report_trg after insert on public.trail_reports
  for each row execute function app_internal.push_on_report();

-- Aufräumen nach 90 Tagen, wo es pg_cron gibt (Muster Patch 005).
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    execute $cron$select cron.schedule('reports-sweep', '41 3 * * *',
              'select app_internal.sweep_old_reports()')$cron$;
  else
    raise notice 'pg_cron nicht verfügbar — sweep_old_reports() ist nicht eingeplant (lokaler Testlauf).';
  end if;
end $$;
