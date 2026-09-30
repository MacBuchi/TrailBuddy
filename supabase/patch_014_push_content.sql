-- Patch 014 (#116): Push-Meldungen mit Inhalt — Trailname, Name bzw.
-- Alias des Buddys, das Statuswort und der Hinweistext (Betreiber,
-- 2026-09-30: „das ist anonym genug"). Jeweils so, wie der EMPFÄNGER sie
-- in der App sieht: sein eigener Trailname oder der des ältesten für ihn
-- sichtbaren Beitrags, sein Alias für den Buddy. Nie eine Koordinate,
-- nie der Zustand. Datenschutzerklärung und Profil-Text ändern sich im
-- selben PR.
--
-- 1. push_outbox merkt sich, wer (sender_ids), wie viele Anlässe eine
--    Zeile zusammenfasst (events) und den jüngsten Hinweis (note_id, ein
--    gelöschter Hinweis nimmt seine Zeile mit). Bestehende Zeilen
--    bekommen die Vorgaben und gehen als „ein Buddy" hinaus.
-- 2. Drei Helfer: trail_name_for, push_name_for, push_join_names.
-- 3. push_on_report, push_on_note und push_flush wie in schema.sql.
--
-- Keine App-Abfrage ändert sich; minimum_supported_version bleibt.
set search_path = public, extensions;

alter table app_internal.push_outbox
  add column if not exists sender_ids uuid[] not null default '{}',
  add column if not exists events integer not null default 1,
  add column if not exists note_id uuid references public.trail_notes(id) on delete cascade;

-- ------------------------------------------------ Namen in der Meldung
--
-- Seit Patch 014 (#116, Betreiber 2026-09-30: „anonym genug") trägt eine
-- Meldung den Trailnamen, den Namen des Buddys und den Hinweistext —
-- jeweils so, wie der EMPFÄNGER sie in der App sieht. Nie eine
-- Koordinate, nie der Zustand.

-- Der Name des Trails für [recipient]: Spiegel von `Trail.displayName`
-- — der eigene Name, sonst der des ältesten für ihn sichtbaren Beitrags
-- (eigene Zeile oder eine geteilte eines Buddys, td_friend_select), sonst
-- „Trail ohne Namen".
create or replace function app_internal.trail_name_for(recipient uuid, trail uuid)
returns text
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select d.name from trail_details d
      where d.trail_id = trail and d.user_id = recipient
        and nullif(btrim(d.name), '') is not null),
    (select d.name from trail_details d
      where d.trail_id = trail and d.user_id <> recipient
        and d.visibility = 'buddies'
        and app_internal.are_friends(d.user_id, recipient)
        and nullif(btrim(d.name), '') is not null
      order by (select min(r.created_at) from trail_recordings r
                 where r.trail_id = trail and r.user_id = d.user_id) nulls last
      limit 1),
    'Trail ohne Namen');
$$;
revoke all on function app_internal.trail_name_for(uuid, uuid) from public, anon, authenticated;

-- Der Name des Buddys [sender] für [recipient]: der Alias, den der
-- EMPFÄNGER vergeben hat (friend_aliases, Besitzer = Empfänger), sonst
-- der Benutzername. Den Alias der Gegenseite sieht nie jemand.
create or replace function app_internal.push_name_for(recipient uuid, sender uuid)
returns text
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select nullif(btrim(a.alias), '') from friend_aliases a
      where a.owner_id = recipient and a.friend_id = sender),
    (select p.username from profiles p where p.id = sender));
$$;
revoke all on function app_internal.push_name_for(uuid, uuid) from public, anon, authenticated;

-- „Anna", „Anna und Ben", „Anna, Ben und Carl", „Anna, Ben und 2 weitere".
create or replace function app_internal.push_join_names(names text[])
returns text
language sql immutable set search_path = '' as $$
  select case
    when coalesce(array_length(names, 1), 0) = 0 then null
    when array_length(names, 1) = 1 then names[1]
    when array_length(names, 1) <= 3 then
      array_to_string(names[1:array_length(names, 1) - 1], ', ')
        || ' und ' || names[array_length(names, 1)]
    else names[1] || ', ' || names[2] || ' und '
      || (array_length(names, 1) - 2) || ' weitere'
  end;
$$;
revoke all on function app_internal.push_join_names(text[]) from public, anon, authenticated;

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
  insert into app_internal.push_outbox (recipient_id, kind, trail_id, status, sender_ids, due_at)
    select r.recipient_id, 'trail_status', new.trail_id, new.status, array[new.user_id],
           app_internal.push_due_at(now())
      from app_internal.push_recipients(new.user_id, new.trail_id) r
  on conflict (recipient_id, kind, trail_id) do update
    set status = excluded.status,
        sender_ids = case when new.user_id = any(push_outbox.sender_ids) then push_outbox.sender_ids
                          else push_outbox.sender_ids || new.user_id end,
        events = push_outbox.events + 1,
        due_at = app_internal.push_due_at(push_outbox.created_at);
  return new;
end $$;
revoke all on function app_internal.push_on_report() from public, anon, authenticated;

create or replace function app_internal.push_on_note()
returns trigger
language plpgsql security definer set search_path = public, app_internal as $$
begin
  insert into app_internal.push_outbox (recipient_id, kind, trail_id, sender_ids, note_id, due_at)
    select r.recipient_id, 'trail_note', new.trail_id, array[new.user_id], new.id,
           app_internal.push_due_at(now())
      from app_internal.push_recipients(new.user_id, new.trail_id) r
  on conflict (recipient_id, kind, trail_id) do update
    set note_id = excluded.note_id,
        sender_ids = case when new.user_id = any(push_outbox.sender_ids) then push_outbox.sender_ids
                          else push_outbox.sender_ids || new.user_id end,
        events = push_outbox.events + 1,
        due_at = app_internal.push_due_at(push_outbox.created_at);
  return new;
end $$;
revoke all on function app_internal.push_on_note() from public, anon, authenticated;

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
    returning recipient_id, kind, trail_id, status, sender_ids, events, note_id
  ),
  grouped as (
    select recipient_id,
           coalesce(sum(events) filter (where kind = 'trail_status'), 0) as statuses,
           coalesce(sum(events) filter (where kind = 'trail_note'), 0) as notes,
           count(distinct trail_id) as trails,
           min(trail_id::text) as trail_id,
           -- Das Statuswort, wenn es genau EINE Statusmeldung ist.
           max(status) filter (where kind = 'trail_status') as status,
           max(note_id::text) filter (where kind = 'trail_note') as note_id
      from due group by recipient_id
  ),
  named as (
    select g.*,
           g.statuses + g.notes = 1 as single,
           app_internal.trail_name_for(g.recipient_id, g.trail_id::uuid) as trail_name,
           -- Die Buddys dieses Empfängers, in der Reihenfolge ihres
           -- ersten Anlasses; ein gelöschtes Konto fällt heraus.
           app_internal.push_join_names(array(
             select q.nm from (
               select app_internal.push_name_for(g.recipient_id, u.sender) as nm,
                      min(u.ord) as ord
                 from due x
                 cross join lateral unnest(x.sender_ids) with ordinality as u(sender, ord)
                where x.recipient_id = g.recipient_id
                group by u.sender) q
              where q.nm is not null
              order by q.ord, q.nm)) as names,
           (select n.body from public.trail_notes n where n.id = g.note_id::uuid) as note_body,
           concat_ws(' und ',
             case when g.statuses = 1 then '1 Meldung'
                  when g.statuses > 1 then g.statuses || ' Meldungen' end,
             case when g.notes = 1 then '1 Hinweis'
                  when g.notes > 1 then g.notes || ' Hinweise' end) as counts
      from grouped g
  )
  select jsonb_agg(jsonb_build_object(
           'token', d.token,
           'title', case
             when m.single and m.statuses = 1 and m.status = 'open'
               then coalesce(m.names, 'Ein Buddy') || ': „' || m.trail_name || '“ ist wieder frei'
             when m.single and m.statuses = 1
               then coalesce(m.names, 'Ein Buddy') || ' meldet „' || m.trail_name || '“ als '
                    || case m.status
                         when 'closed' then 'gesperrt'
                         when 'destroyed' then 'zerstört'
                         else 'verändert' end
             when m.single
               then coalesce(m.names, 'Ein Buddy') || ' zu „' || m.trail_name || '“'
             when m.trails = 1
               then '„' || m.trail_name || '“: ' || m.counts
             when m.statuses > 0 and m.notes > 0
               then 'Deine Buddys haben etwas gemeldet'
             when m.statuses > 1
               then m.statuses || ' Meldungen von deinen Buddys'
             else m.notes || ' neue Hinweise von deinen Buddys'
           end,
           'body', case
             when m.single and m.notes = 1 and m.note_body is not null
               then case when char_length(m.note_body) > 140
                         then left(m.note_body, 139) || '…'
                         else m.note_body end
             when m.single then 'Tippen zeigt den Trail'
             when m.trails = 1 then 'von ' || coalesce(m.names, 'deinen Buddys')
             when m.statuses > 0 and m.notes > 0
               then m.counts || ' an ' || m.trails || ' Trails · von '
                    || coalesce(m.names, 'deinen Buddys')
             else 'An ' || m.trails || ' Trails · von ' || coalesce(m.names, 'deinen Buddys')
           end,
           'route', case
             when m.trails = 1 then '/trail/' || m.trail_id
             else '/trails'
           end))
    into payload
    from named m
    join public.push_devices d on d.user_id = m.recipient_id;

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
