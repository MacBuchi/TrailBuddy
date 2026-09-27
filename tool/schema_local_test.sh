#!/usr/bin/env bash
# Frischinstallation + Matcher-Prüfung auf einem WEGWERF-Postgres, ohne
# Supabase-Stack und ohne Docker:
#
#   1. eigenen Cluster anlegen (initdb) und auf einem freien Port starten,
#   2. tool/auth_shim.sql   — Ersatz für das auth-Schema (nur hier!),
#   3. supabase/schema.sql  — in EINEM Durchlauf, ON_ERROR_STOP,
#   4. tool/matcher_check.sql — die Fälle aus dem Konzept als Assertions,
#   5. Cluster stoppen und wegräumen; PASS oder FAIL am Ende.
#
# Braucht Postgres-Binaries mit PostGIS (Ubuntu: postgresql-16 +
# postgresql-16-postgis-3; Pfad über PGBIN, sonst wird gesucht). initdb
# verweigert den Dienst als root — dann wird der Cluster als Systemnutzer
# `postgres` angelegt (runuser), und das Verzeichnis muss für ihn
# erreichbar sein; TB_TEST_DIR setzt es (Vorgabe: ein Ordner unter dem
# Home des Nutzers, der den Cluster betreibt).
#
# Was der Lauf NICHT prüft: PostgREST (Antwortcodes über die API, Embeds)
# und GoTrue. Das leistet der Schema Dry Run mit dem echten lokalen Stack
# (tool/schema_check.sh, tool/auth_reset_check.sh). Hier geht es um die
# SQL-Seite: läuft die Datei, stimmen Matcher, Policies und Grants.
set -euo pipefail

cd "$(dirname "$0")/.."

PGBIN="${PGBIN:-}"
if [ -z "$PGBIN" ]; then
  for d in /usr/lib/postgresql/*/bin; do
    [ -x "$d/initdb" ] && PGBIN="$d"
  done
fi
if [ -z "$PGBIN" ] || [ ! -x "$PGBIN/initdb" ]; then
  echo "::error::Keine Postgres-Binaries gefunden — PGBIN setzen (Ordner mit initdb, pg_ctl, psql)."
  exit 1
fi
PORT="${TB_TEST_PORT:-54599}"

# Als wer läuft der Cluster? initdb lehnt root ab.
RUN=()
if [ "$(id -u)" = "0" ]; then
  if ! id postgres >/dev/null 2>&1; then
    echo "::error::Läuft als root, aber es gibt keinen Systemnutzer postgres — initdb braucht einen Nicht-Root."
    exit 1
  fi
  RUN=(runuser -u postgres --)
  home=$(getent passwd postgres | cut -d: -f6)
else
  home="${HOME:-/tmp}"
fi
DIR="${TB_TEST_DIR:-$home/trailbuddy-schema-test}"

cleanup() {
  "${RUN[@]}" "$PGBIN/pg_ctl" -D "$DIR/data" stop -m immediate >/dev/null 2>&1 || true
  "${RUN[@]}" rm -rf "$DIR" >/dev/null 2>&1 || true
}
trap cleanup EXIT

cleanup
"${RUN[@]}" mkdir -p "$DIR"
"${RUN[@]}" "$PGBIN/initdb" -D "$DIR/data" -A trust -U postgres >"$DIR.initdb.log" 2>&1 \
  || { cat "$DIR.initdb.log"; echo "::error::initdb fehlgeschlagen"; exit 1; }
"${RUN[@]}" "$PGBIN/pg_ctl" -D "$DIR/data" -w \
  -o "-p $PORT -k $DIR -c listen_addresses=127.0.0.1 -c fsync=off" \
  -l "$DIR/postgres.log" start >/dev/null

PSQL=("$PGBIN/psql" -h 127.0.0.1 -p "$PORT" -U postgres -v ON_ERROR_STOP=1 -q)

"${PSQL[@]}" -d postgres -c "create database trailbuddy_test"
echo "→ auth-Shim"
"${PSQL[@]}" -d trailbuddy_test -f tool/auth_shim.sql
echo "→ schema.sql (Frischinstallation, ein Durchlauf)"
"${PSQL[@]}" -d trailbuddy_test -f supabase/schema.sql
echo "→ matcher_check.sql + grants_check.sql"
if "${PSQL[@]}" -d trailbuddy_test -f tool/matcher_check.sql \
   && "${PSQL[@]}" -d trailbuddy_test -f tool/grants_check.sql; then
  echo "PASS: schema.sql läuft auf einer leeren Datenbank durch, Matcher und Policies verhalten sich wie im Konzept."
else
  echo "FAIL: siehe Meldung oben (Log: $DIR/postgres.log wird beim Aufräumen gelöscht — mit TB_TEST_KEEP=1 bleibt es)."
  if [ -n "${TB_TEST_KEEP:-}" ]; then trap - EXIT; fi
  exit 1
fi
