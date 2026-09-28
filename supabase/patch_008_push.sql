-- Patch 008: Push-Benachrichtigungen (#34) — Statusmeldung und Hinweis
-- eines Buddys an einem Trail, den ich sehe.
--
-- Muster PilzBuddy Patch 017–020 (#277): ein Geräteregister
-- (`push_devices`), ein entprellter Korb (`push_outbox`) in
-- `app_internal`, zwei Auslöser und ein minütlicher Versand
-- (`push_flush`) über pg_net an die Edge Function `send-push`.
--
-- **Wer etwas erfährt, ist NICHT neu entschieden.** Empfänger sind
-- genau die direkten Buddys des Autors, die den Trail sehen und seinen
-- Beitrag sehen dürfen — dieselben Bedingungen wie `td_friend_select`
-- und `notes_select` (`contributor_shares`, `can_see_trail`). Keine
-- Transitivität, keine Aggregation über Netzgrenzen (Konzept 12): Je
-- Buddy-Beziehung eine Zeile im Korb, der Server rechnet nichts über
-- alle.
--
-- **Die Meldung trägt KEINEN Inhalt.** Kein Trailname, kein
-- Benutzername, keine Koordinate, kein Hinweistext — eine Push läuft
-- über Googles Server. Nur die Art des Ereignisses, das Statuswort
-- („gesperrt") und Anzahlen; das Ziel reist als opake Trail-Kennung in
-- `route`. Die Einzelheiten holt die App beim Antippen. Mehr Inhalt
-- wäre eine Betreiber-Entscheidung samt Zeile in der
-- Datenschutzerklärung (PilzBuddy Patch 031 als Muster).
--
-- **Ein Korb, kein direkter Aufruf beim Insert.** Drei Statuswechsel in
-- einer Minute dürfen nicht drei Meldungen sein: Der Auslöser legt nur
-- eine Zeile ab und schiebt ihre Fälligkeit vor sich her (fünf Minuten
-- Ruhe, gedeckelt auf eine halbe Stunde), erst dann geht eine einzige
-- Meldung raus.
--
-- Ohne Vault-Geheimnisse tut der Versand nichts, wirft aber auch nichts
-- — und räumt fällige Zeilen trotzdem weg (PilzBuddy Patch 019): Der
-- Patch spielt beim Merge ein, die Geheimnisse kommen von Hand; eine
-- Benachrichtigung ist verderbliche Ware.
--
-- KEIN Bump von minimum_supported_version: Ältere Clients kennen die
-- Tabelle nicht und bekommen schlicht keine Benachrichtigungen.
--
-- Wird automatisch eingespielt (tool/db_migrate.sh über den Pflicht-Check
-- „Schema Check").

set search_path = public, extensions;

-- pg_net und pg_cron gibt es auf Supabase; der nackte Postgres des
-- Matcher-Tests hat beides nicht. Dieselbe Weiche wie beim Aufräumjob in
-- schema.sql — der Rumpf von push_flush löst `net.` erst beim Aufruf auf.
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_net') then
    create extension if not exists pg_net;
  end if;
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
  end if;
end $$;

-- ------------------------------------------------------ Das Geräteregister
--
-- Eine Zeile je Gerät, Primärschlüssel ist der TOKEN: FCM-Token sind
-- global eindeutig, und ein Token gehört zu genau EINEM Konto — meldet
-- sich am selben Gerät jemand anders an, muss die alte Zeile weichen
-- (`on conflict (token) do update` der App), sonst bekäme der
-- Vorbesitzer weiter Meldungen über fremde Trails.
--
-- Was hier bewusst NICHT steht: ein Schalter „aktiv". Eine Zeile IST die
-- Zustimmung dieses Geräts, ihr Fehlen der Widerruf.
create table public.push_devices (
  token text primary key,
  user_id uuid not null default auth.uid()
    references public.profiles(id) on delete cascade,
  platform text not null check (platform in ('android', 'web')),
  created_at timestamptz not null default now(),
  -- Jede Registrierung schiebt den Wert vor; eine Zeile, die seit
  -- Monaten nicht angefasst wurde, ist mit hoher Wahrscheinlichkeit tot.
  last_seen_at timestamptz not null default now()
);
create index push_devices_user_idx on public.push_devices (user_id);

alter table public.push_devices enable row level security;
-- Nur die eigenen Geräte, in beide Richtungen: Ohne das `with check`
-- könnte jemand ein Token auf ein fremdes Konto schreiben und dessen
-- Meldungen mitbekommen.
create policy push_devices_own_all on public.push_devices for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- Keine automatische Freigabe (config.toml, auto_expose_new_tables =
-- false): Grants ausdrücklich. anon bekommt nichts — der Schema Check
-- prüft die Tabelle deshalb über check_get_protected.
revoke all on public.push_devices from public, anon, authenticated;
grant select, insert, update, delete on public.push_devices to authenticated;
-- `send-push` räumt tote Token mit dem Service-Schlüssel ab (FCM meldet
-- „unregistered"). service_role umgeht RLS, aber keine fehlenden
-- Grants; tool/grants_check.sql prüft es.
grant select, delete on public.push_devices to service_role;

-- --------------------------------------------------------------- Der Korb
--
-- Schlüssel (Empfänger, Art, Trail): Ein zweiter Statuswechsel am
-- selben Trail trifft dieselbe Zeile und schiebt nur die Fälligkeit.
-- In `app_internal`, nicht in `public`: In `public` hielte PostgREST die
-- Tabelle wegen ihrer Fremdschlüssel für eine Verbindungstabelle
-- (PilzBuddy Patch 018, PGRST201); und der Client hat hier nichts zu
-- suchen.
create table app_internal.push_outbox (
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null check (kind in ('trail_status', 'trail_note')),
  trail_id uuid not null references public.trails(id) on delete cascade,
  -- Das gemeldete Statuswort (nur bei trail_status), damit die Meldung
  -- „gesperrt" sagen kann, ohne beim Versand in trail_details zu lesen.
  status text check (status is null or status in ('open', 'closed', 'destroyed', 'changed')),
  -- Wann frühestens rausgehen darf; jeder weitere Anlass schiebt es …
  due_at timestamptz not null,
  -- … aber nicht endlos: created_at ist die Reißleine (30 Minuten).
  created_at timestamptz not null default now(),
  primary key (recipient_id, kind, trail_id)
);
create index push_outbox_due_idx on app_internal.push_outbox (due_at);

alter table app_internal.push_outbox enable row level security;
revoke all on app_internal.push_outbox from public, anon, authenticated;
-- Sperr-Policy statt „RLS ohne Policy" (PilzBuddy Patch 037): der
-- Security Advisor meldet das sonst dauerhaft.
create policy push_outbox_no_client on app_internal.push_outbox
  for all to anon, authenticated using (false) with check (false);

-- --------------------------------------------------------- Die Fälligkeit
--
-- Fünf Minuten Ruhe, gedeckelt auf eine halbe Stunde ab dem ersten
-- Anlass. An EINER Stelle, damit die Auslöser nicht auseinanderlaufen.
create or replace function app_internal.push_due_at(first_seen timestamptz)
returns timestamptz
language sql stable set search_path = '' as $$
  select least(now() + interval '5 minutes', first_seen + interval '30 minutes');
$$;
revoke all on function app_internal.push_due_at(timestamptz) from public, anon, authenticated;

-- ---------------------------------------------------------- Die Empfänger
--
-- Die direkten Buddys des Autors, die seinen Beitrag zu diesem Trail
-- sehen dürfen: Spiegel von td_friend_select / notes_select — Buddy UND
-- der Autor teilt den Trail (`contributor_shares`: nicht „privat") UND
-- der Buddy sieht den Trail überhaupt (`can_see_trail`). Der Autor
-- selbst ist nie dabei.
create or replace function app_internal.push_recipients(author uuid, trail uuid)
returns table (recipient_id uuid)
language sql stable security definer set search_path = public as $$
  select f.friend_id
    from (
      select case when requester_id = author then addressee_id else requester_id end as friend_id
        from friendships
       where status = 'accepted'
         and (requester_id = author or addressee_id = author)
    ) f
   where app_internal.contributor_shares(author, trail)
     and app_internal.can_see_trail(f.friend_id, trail);
$$;
revoke all on function app_internal.push_recipients(uuid, uuid) from public, anon, authenticated;

-- ----------------------------------------------------------- Die Auslöser

-- Ein Beitrag ändert seinen Status (Konzept 10, Punkt 6: alle vier
-- Werte, auch zurück auf „offen" — eine neue Aufzeichnung setzt den
-- eigenen Status auf offen, und das ist die gute Nachricht). Ein
-- erneutes Melden desselben Status (nur status_at springt) löst NICHTS
-- aus; ein neuer Beitrag mit „offen" auch nicht.
create or replace function app_internal.push_on_status()
returns trigger
language plpgsql security definer set search_path = public, app_internal as $$
begin
  if tg_op = 'UPDATE' and old.status = new.status then return new; end if;
  if tg_op = 'INSERT' and new.status = 'open' then return new; end if;
  insert into app_internal.push_outbox (recipient_id, kind, trail_id, status, due_at)
    select r.recipient_id, 'trail_status', new.trail_id, new.status,
           app_internal.push_due_at(now())
      from app_internal.push_recipients(new.user_id, new.trail_id) r
  on conflict (recipient_id, kind, trail_id) do update
    set status = excluded.status,
        due_at = app_internal.push_due_at(push_outbox.created_at);
  return new;
end $$;
revoke all on function app_internal.push_on_status() from public, anon, authenticated;

-- Ein neuer Hinweis (#7). Der Text bleibt in der Datenbank.
create or replace function app_internal.push_on_note()
returns trigger
language plpgsql security definer set search_path = public, app_internal as $$
begin
  insert into app_internal.push_outbox (recipient_id, kind, trail_id, due_at)
    select r.recipient_id, 'trail_note', new.trail_id,
           app_internal.push_due_at(now())
      from app_internal.push_recipients(new.user_id, new.trail_id) r
  on conflict (recipient_id, kind, trail_id) do update
    set due_at = app_internal.push_due_at(push_outbox.created_at);
  return new;
end $$;
revoke all on function app_internal.push_on_note() from public, anon, authenticated;

create trigger push_on_status_trg after insert or update of status on public.trail_details
  for each row execute function app_internal.push_on_status();
create trigger push_on_note_trg after insert on public.trail_notes
  for each row execute function app_internal.push_on_note();

-- ------------------------------------------------------------ Der Versand
--
-- Die drei Geheimnisse stehen im VAULT und nicht hier — ein Patch liegt
-- öffentlich im Repo. Einmalig von Hand im SQL-Editor des Dashboards:
--
--   select vault.create_secret('https://<ref>.supabase.co/functions/v1',
--                              'push_functions_url');
--   select vault.create_secret('<PUSH_JOB_SECRET>', 'push_job_secret');
--   select vault.create_secret('<SERVICE_ROLE_KEY>', 'push_service_key');
--
-- Je Empfänger EINE Meldung, auch wenn mehrere Trails fällig sind.
-- Genau ein Trail ⇒ das Ziel ist der Trail (`/trail/<id>`), sonst die
-- Liste (`/trails`); die App prüft den Pfad gegen eine Erlaubnisliste.
-- tool/push_flush_check.sh ruft diese Funktion im Schema Dry Run
-- WIRKLICH auf (zurückgerollt): PL/pgSQL prüft den Rumpf erst beim
-- Aufruf, und ein Fehler hier legte live jede Minute still alles lahm.
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
               then g.statuses || ' Statusmeldungen von deinen Buddys'
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
               g.statuses || (case when g.statuses = 1 then ' Statusmeldung'
                                   else ' Statusmeldungen' end) || ' und ' ||
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

-- Jede Minute. Teuer ist das nicht: Ohne fällige Zeilen passiert nichts.
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    execute $cron$select cron.schedule('push-flush', '* * * * *',
              'select app_internal.push_flush()')$cron$;
  else
    raise notice 'pg_cron nicht verfügbar — push_flush() ist nicht eingeplant (lokaler Testlauf).';
  end if;
end $$;

-- PostgREST-Schema-Cache sofort neu laden, damit der direkt
-- anschließende Schema Check die neue Tabelle sieht.
notify pgrst, 'reload schema';
