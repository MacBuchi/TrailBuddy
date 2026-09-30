#!/usr/bin/env bash
# Ruft app_internal.push_flush() auf dem Wegwerf-Stack des Schema Dry
# Run WIRKLICH auf und prüft Auslöser, Empfänger und die Nutzlast, die an
# `send-push` ginge (Patch 008, #34; Muster PilzBuddy #564).
#
# **Warum es das braucht:** PL/pgSQL prüft den Rumpf einer Funktion beim
# Anlegen kaum — ein falscher Spaltenname fällt erst beim AUFRUF auf.
# push_flush ruft in CI sonst niemand auf, live aber jede Minute der
# Cron-Job; ein Fehler darin legte ALLE Benachrichtigungen lautlos still
# (der Job scheitert in cron.job_run_details, die App merkt nichts).
#
# **Es geht nichts hinaus.** Alles läuft in EINER Transaktion, die am Ende
# zurückgerollt wird; pg_net verschickt nur, was committet ist. Die
# Geheimnisse sind Platzhalter, die Adresse zeigt ins Leere.
#
# Braucht SUPABASE_DB_URL (lokaler Stack) und jq.
set -euo pipefail

DB="${SUPABASE_DB_URL:?SUPABASE_DB_URL fehlt}"
A=aaaaaaaa-0000-0000-0000-00000000000a   # Anna: meldet und schreibt
B=bbbbbbbb-0000-0000-0000-00000000000b   # Bert: Buddy von Anna, mit Gerät
C=cccccccc-0000-0000-0000-00000000000c   # Carl: Buddy von Anna, OHNE Gerät
D=dddddddd-0000-0000-0000-00000000000d   # Dave: nur eine offene Anfrage
T1=11111111-0000-0000-0000-000000000001
T2=11111111-0000-0000-0000-000000000002

out=$(psql "$DB" -v ON_ERROR_STOP=1 -q -At <<SQL
begin;
-- Sauberer Korb: matcher_check.sql läuft davor in derselben Datenbank
-- und hinterlässt eigene Statuswechsel und Hinweise (also Zeilen).
delete from app_internal.push_outbox;
select vault.create_secret('http://127.0.0.1:9/functions/v1', 'push_functions_url');
select vault.create_secret('dry-run', 'push_job_secret');
select vault.create_secret('dry-run', 'push_service_key');
insert into auth.users (id, email, aud, role, instance_id) values
  ('$A', 'a@push.check', 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'),
  ('$B', 'b@push.check', 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'),
  ('$C', 'c@push.check', 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000'),
  ('$D', 'd@push.check', 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000');
-- Eigene Namen: matcher_check.sql lässt seine Nutzer (anna, bernd …)
-- in derselben Datenbank stehen, und username ist eindeutig.
insert into public.profiles (id, username) values
  ('$A', 'push_anna'), ('$B', 'push_bert'), ('$C', 'push_carl'), ('$D', 'push_dave')
  on conflict (id) do update set username = excluded.username;
insert into public.friendships (requester_id, addressee_id, status)
  values ('$A', '$B', 'accepted'), ('$C', '$A', 'accepted'), ('$D', '$A', 'pending');
insert into public.push_devices (token, user_id, platform)
  values ('tok-bert', '$B', 'android'), ('tok-anna', '$A', 'web'), ('tok-dave', '$D', 'android');
-- Zwei Trails von Anna, geteilt (Beitrag mit „buddies"); Bert, Carl
-- und Dave haben selbst nichts gefahren — sie sehen die Trails nur
-- über die Freundschaft mit Anna.
insert into public.trails (id) values ('$T1'), ('$T2');
insert into public.trail_recordings (trail_id, user_id, geom, source, quality) values
  ('$T1', '$A', 'SRID=4326;LINESTRING(9 48, 9.01 48)', 'app', 0.5),
  ('$T2', '$A', 'SRID=4326;LINESTRING(9 48.1, 9.01 48.1)', 'app', 0.5);
insert into public.trail_details (trail_id, user_id, name, visibility, status) values
  ('$T1', '$A', 'Hang', 'buddies', 'open'),
  ('$T2', '$A', 'Kamm', 'buddies', 'open');
select 'OUTBOX_AFTER_SEED=' || count(*) from app_internal.push_outbox;

-- 1. Anna meldet T1 gesperrt: Bert und Carl bekommen eine Zeile, Anna
--    selbst und Dave nicht.
update public.trail_details set status = 'closed', status_at = now()
  where trail_id = '$T1' and user_id = '$A';
select 'OUTBOX_AFTER_STATUS=' || string_agg(recipient_id::text || ':' || kind || ':' || coalesce(status, '-'), ',' order by recipient_id)
  from app_internal.push_outbox;
-- Dieselbe Meldung noch einmal (nur status_at springt): keine neue Zeile,
-- und die Fälligkeit wird geschoben, nicht neu angelegt.
update public.trail_details set status_at = now()
  where trail_id = '$T1' and user_id = '$A';
select 'OUTBOX_AFTER_REPEAT=' || count(*) from app_internal.push_outbox;
-- Entprellt: Vor der Frist geht nichts hinaus.
select 'SENT_EARLY=' || app_internal.push_flush();
select 'OUTBOX_EARLY=' || count(*) from app_internal.push_outbox;
-- Frist um.
update app_internal.push_outbox set due_at = now() - interval '1 minute';
select 'SENT1=' || app_internal.push_flush();
select 'BODY1=' || convert_from(body, 'utf8') from net.http_request_queue order by id desc limit 1;
select 'OUTBOX_AFTER_FLUSH1=' || count(*) from app_internal.push_outbox;

-- 2. Zwei Hinweise an zwei Trails: EINE Meldung, Ziel die Liste.
insert into public.trail_notes (trail_id, user_id, body) values
  ('$T1', '$A', 'Baum liegt quer'), ('$T2', '$A', 'Kehre ausgewaschen');
update app_internal.push_outbox set due_at = now() - interval '1 minute';
select 'SENT2=' || app_internal.push_flush();
select 'BODY2=' || convert_from(body, 'utf8') from net.http_request_queue order by id desc limit 1;

-- 3. Status UND Hinweis am selben Trail, fällig zugleich.
update public.trail_details set status = 'open', status_at = now()
  where trail_id = '$T1' and user_id = '$A';
insert into public.trail_notes (trail_id, user_id, body) values ('$T1', '$A', 'wieder frei');
update app_internal.push_outbox set due_at = now() - interval '1 minute';
select 'SENT3=' || app_internal.push_flush();
select 'BODY3=' || convert_from(body, 'utf8') from net.http_request_queue order by id desc limit 1;

-- 3b. Meldungen über report_trail (Patch 013): Bert hat T1 nie gefahren.
--     Von zu Hause gemeldet ist unbestätigt und bleibt still; vor Ort
--     gemeldet ist bestätigt und geht an Anna.
delete from app_internal.push_outbox;
select set_config('request.jwt.claims', '{"sub":"$B","role":"authenticated"}', true);
set local role authenticated;
select public.report_trail('$T1', 'closed', null, false, null, null);
reset role;
select 'OUTBOX_UNCONFIRMED=' || count(*) from app_internal.push_outbox;
set local role authenticated;
select public.report_trail('$T1', 'closed', 2, true, null, null);
reset role;
select 'OUTBOX_ONSITE=' || coalesce(string_agg(recipient_id::text || ':' || kind || ':' || coalesce(status, '-'), ',' order by recipient_id), '')
  from app_internal.push_outbox;
delete from app_internal.push_outbox;

-- 4. Privat: Kein Buddy sieht den Beitrag, also erfährt keiner etwas.
update public.trail_details set visibility = 'private'
  where trail_id = '$T2' and user_id = '$A';
update public.trail_details set status = 'destroyed', status_at = now()
  where trail_id = '$T2' and user_id = '$A';
insert into public.trail_notes (trail_id, user_id, body) values ('$T2', '$A', 'privat');
select 'OUTBOX_PRIVATE=' || count(*) from app_internal.push_outbox;

-- 5. Ohne Geheimnisse räumt der Versand nur ab.
update public.trail_details set visibility = 'buddies', status = 'changed', status_at = now()
  where trail_id = '$T2' and user_id = '$A';
delete from vault.secrets where name = 'push_job_secret';
update app_internal.push_outbox set due_at = now() - interval '1 minute';
select 'SENT_NOSECRET=' || app_internal.push_flush();
select 'OUTBOX_NOSECRET=' || count(*) from app_internal.push_outbox;
rollback;
SQL
)
# ACHTUNG: Der Heredoc oben ist absichtlich NICHT gequotet (\$A, \$B
# werden eingesetzt) — Backticks in SQL-Kommentaren führte die Shell
# deshalb als Befehle aus. Keine Backticks dort.

value() { printf '%s\n' "$out" | sed -n "s/^$1=//p" | head -1; }

fail=0
expect() {
  if [ "$2" != "$3" ]; then
    echo "::error::push_flush: $1 — erwartet '$3', bekommen '$2'"
    fail=1
  else
    echo "✓ $1"
  fi
}

expect "Anlegen eines Beitrags mit Status offen löst nichts aus" "$(value OUTBOX_AFTER_SEED)" "0"
expect "Statuswechsel: Bert und Carl bekommen eine Zeile, Anna und Dave nicht" \
  "$(value OUTBOX_AFTER_STATUS)" "$B:trail_status:closed,$C:trail_status:closed"
expect "erneutes Melden desselben Status legt keine Zeile an" "$(value OUTBOX_AFTER_REPEAT)" "2"
expect "vor der Frist geht nichts hinaus" "$(value SENT_EARLY)" "0"
expect "und der Korb bleibt voll" "$(value OUTBOX_EARLY)" "2"
expect "eine Meldung (Carl hat kein Gerät)" "$(value SENT1)" "1"
body1=$(value BODY1)
msg1=$(printf '%s' "$body1" | jq -c '.messages[0]')
expect "an Berts Gerät" "$(jq -r .token <<<"$msg1")" "tok-bert"
expect "Titel: Statuswort, kein Name" "$(jq -r .title <<<"$msg1")" "Ein Buddy meldet einen Trail als gesperrt"
expect "Text: der Tipp" "$(jq -r .body <<<"$msg1")" "Tippen zeigt den Trail"
expect "Ziel: der Trail" "$(jq -r .route <<<"$msg1")" "/trail/$T1"
expect "genau eine Nachricht in der Nutzlast" "$(jq -r '.messages | length' <<<"$body1")" "1"
expect "Korb nach dem Versand leer" "$(value OUTBOX_AFTER_FLUSH1)" "0"
case "$body1" in *Hang*|*push_anna*|*48*) echo "::error::push_flush: Trailname, Nutzername oder Koordinate in der Nutzlast: $body1"; fail=1;;
  *) echo "✓ kein Trailname, kein Nutzername, keine Koordinate in der Nutzlast";; esac

expect "zwei Hinweise an zwei Trails: eine Meldung" "$(value SENT2)" "1"
msg2=$(value BODY2 | jq -c '.messages[0]')
expect "Titel: die Anzahl" "$(jq -r .title <<<"$msg2")" "2 neue Hinweise von deinen Buddys"
expect "Text: die Trails" "$(jq -r .body <<<"$msg2")" "An 2 Trails"
expect "Ziel: die Liste" "$(jq -r .route <<<"$msg2")" "/trails"
case "$msg2" in *Baum*|*Kehre*) echo "::error::push_flush: Hinweistext in der Nutzlast: $msg2"; fail=1;;
  *) echo "✓ kein Hinweistext in der Nutzlast";; esac

expect "Status und Hinweis zugleich: eine Meldung" "$(value SENT3)" "1"
msg3=$(value BODY3 | jq -c '.messages[0]')
expect "Titel: beides" "$(jq -r .title <<<"$msg3")" "Deine Buddys haben etwas gemeldet"
expect "Text: die Zahlen" "$(jq -r .body <<<"$msg3")" "1 Meldung und 1 Hinweis"
expect "Ziel: der eine Trail" "$(jq -r .route <<<"$msg3")" "/trail/$T1"

expect "unbestätigte Meldung (von zu Hause): keine Push" "$(value OUTBOX_UNCONFIRMED)" "0"
expect "vor Ort bestätigt: Anna bekommt eine Zeile, der Zustand keine" "$(value OUTBOX_ONSITE)" "$A:trail_status:closed"
expect "privater Beitrag: niemand erfährt etwas" "$(value OUTBOX_PRIVATE)" "0"
expect "ohne Geheimnisse wird nichts verschickt" "$(value SENT_NOSECRET)" "0"
expect "aber abgeräumt" "$(value OUTBOX_NOSECRET)" "0"

exit $fail
