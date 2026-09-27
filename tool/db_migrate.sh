#!/usr/bin/env bash
# Applies pending supabase/patch_NNN_*.sql files to the live database —
# and, on an empty project, supabase/schema.sql first (see below).
#
# Applied patches are tracked in public.applied_patches. Each patch runs in
# a single transaction and is recorded afterwards, so the script is
# idempotent and safe to run from both CI (per PR) and the release
# workflow (safety net).
#
# BASELINE is 0 here — unlike PilzBuddy, where patches 001–005 had been
# applied by hand before this automation existed and are only recorded.
# TrailBuddy starts with schema.sql as its complete first state and has
# no manual history; the first patch_001 will be applied by this script.
# (Adapted from PilzBuddy's tool/db_migrate.sh; the logic is unchanged.)
#
# Requires SUPABASE_DB_URL (Session-Pooler URI incl. password, GitHub
# secret). Without it the script only fails if THIS change adds a patch —
# see the BASE_REF block below.
set -euo pipefail

BASELINE=${BASELINE:-0}
DB_URL="${SUPABASE_DB_URL:-}"
BASE_REF="${BASE_REF:-origin/main}"

patch_number() {
  basename "$1" | sed -n 's/^patch_0*\([0-9][0-9]*\)_.*/\1/p'
}

files=$(ls supabase/patch_*.sql 2>/dev/null | sort || true)
pending_without_db=""
for f in $files; do
  n=$(patch_number "$f")
  if [ -n "$n" ] && [ "$n" -gt "$BASELINE" ]; then
    pending_without_db="$pending_without_db $(basename "$f")"
  fi
done

if [ -z "$DB_URL" ]; then
  # Ohne Datenbank lässt sich `applied_patches` nicht lesen. Die Frage ist
  # dann NICHT „gibt es Patches jenseits der Baseline" — die gibt es seit
  # patch_006 immer, das wäre ein Wächter, der nie wieder grün wird.
  #
  # Die Frage ist: Fügt DIESER Stand einen Patch hinzu, den der
  # Ziel-Branch noch nicht hat? Nur dann steht etwas aus. Genau dieselbe
  # Betrachtung wie in tool/patch_guard.sh.
  #
  # Der Fall ist real und nicht theoretisch: GitHub reicht bei
  # Dependabot-Läufen die DEPENDABOT-Secrets durch, nicht die von Actions
  # (zwei getrennte Sätze in den Repo-Einstellungen). SUPABASE_DB_URL ist
  # dort nicht gesetzt, also war dieser Pflicht-Check auf JEDEM
  # Dependabot-PR rot — mit einer Meldung, die sechzehn längst
  # eingespielte Patches als offen auswies und zum Anlegen eines Secrets
  # riet, das es längst gibt (PilzBuddy #368, #369).
  #
  # Das Secret zusätzlich als Dependabot-Secret zu hinterlegen wäre der
  # bequeme, aber falsche Weg: Damit bekäme ein Lauf, der fremde
  # Paket-Updates einspielt und dabei deren Build-Hooks ausführt, Zugriff
  # auf die Produktionsdatenbank.
  if git rev-parse --verify --quiet "$BASE_REF" >/dev/null 2>&1; then
    added=$(git diff --name-only --diff-filter=A "$BASE_REF"...HEAD \
              -- 'supabase/patch_*.sql' 2>/dev/null || true)
    if [ -z "$added" ]; then
      echo "Dieser Stand fügt keinen DB-Patch hinzu (Basis: $BASE_REF) — SUPABASE_DB_URL wird nicht benötigt."
      exit 0
    fi
    echo "::error::Dieser Stand fügt DB-Patches hinzu ($(echo $added | tr '\n' ' ')), aber SUPABASE_DB_URL ist in diesem Lauf leer. Ohne eingespielten Patch darf der Stand nicht gemergt/released werden. Bei einem Dependabot-PR ist das erwartbar — dort greifen die Dependabot-Secrets, nicht die von Actions; ein solcher PR sollte aber gar keinen Patch mitbringen. Sonst: Supabase-Dashboard → Connect → Session-Pooler-URI (inkl. DB-Passwort) → GitHub → Settings → Secrets → Actions → SUPABASE_DB_URL."
    exit 1
  fi
  # Ohne Basis-Branch (flacher Klon, Lauf auf einem Tag) lässt sich die
  # Frage nicht beantworten. Dann bleibt es bei der vorsichtigen Antwort:
  # lieber rot als ein nicht eingespielter Patch im Release.
  if [ -n "$pending_without_db" ]; then
    echo "::error::Neue DB-Patches vorhanden (${pending_without_db# }), und weder SUPABASE_DB_URL noch der Basis-Branch $BASE_REF stehen zur Verfügung — ob etwas aussteht, ist damit nicht entscheidbar. Für PR-Läufe: actions/checkout mit fetch-depth: 0 und BASE_REF setzen."
    exit 1
  fi
  echo "Keine neuen DB-Patches — SUPABASE_DB_URL wird nicht benötigt."
  exit 0
fi

run_sql() { psql "$DB_URL" -v ON_ERROR_STOP=1 -qtA "$@"; }

if ! run_sql -c "select 1" >/dev/null; then
  echo "::error::Keine Verbindung zur Datenbank — stimmt die Session-Pooler-URI im Secret SUPABASE_DB_URL (inkl. Passwort)?"
  exit 1
fi

# Frisches Projekt: schema.sql ist der erste Stand, und er kommt über
# DIESEN Weg hinein, nicht von Hand im Dashboard — sonst gäbe es für die
# Produktion einen Schritt, den CI nie gefahren hat. Der Schema Dry Run
# fährt genau diesen Zweig (Frischinstallation nach `supabase db reset`).
#
# Entschieden wird an ZWEI Tabellen, und nur die beiden Eindeutigen
# führen weiter: keine von beiden ⇒ leer, einspielen; beide ⇒ Bestand.
# Alles dazwischen ist ein halb eingerichtetes Projekt, und darüber
# schema.sql zu legen hieße raten, was schon steht.
state=$(run_sql -c "select format('%s%s',
  (to_regclass('public.trails') is not null)::int,
  (to_regclass('public.applied_patches') is not null)::int);")
case "$state" in
  00)
    echo "→ Leeres Projekt: spiele supabase/schema.sql ein"
    psql "$DB_URL" -v ON_ERROR_STOP=1 -q --single-transaction -f supabase/schema.sql
    echo "✓ Eingespielt: schema.sql (die Saat-Liste trägt alle bisherigen Patches)"
    ;;
  11) ;;
  *)
    echo "::error::Halb eingerichtetes Projekt (trails/applied_patches: $state) — schema.sql wird NICHT darübergelegt. Von Hand nachsehen, was dort steht."
    exit 1
    ;;
esac

# RLS + Revoke gehören zum Bootstrap (idempotent), nicht nur zu Patch 010:
# die Tabelle entsteht hier VOR dem ersten Patch-Lauf und wäre auf einer
# Frischinstallation sonst wieder offen (Supabase-Advisor:
# rls_disabled_in_public — über die API voll les- und schreibbar).
run_sql -c "create table if not exists public.applied_patches (
  filename text primary key,
  applied_at timestamptz not null default now()
);
alter table public.applied_patches enable row level security;
revoke all on table public.applied_patches from anon, authenticated;" >/dev/null

for f in $files; do
  name=$(basename "$f")
  n=$(patch_number "$f")
  if [ -z "$n" ]; then
    echo "::warning::Überspringe $name — Dateiname passt nicht zum Muster patch_NNN_*.sql"
    continue
  fi
  if [ "$n" -le "$BASELINE" ]; then
    # Baseline: manuell eingespielt, nur protokollieren (hier leer, s. o.).
    run_sql -c "insert into public.applied_patches (filename) values ('$name') on conflict do nothing;" >/dev/null
    continue
  fi
  applied=$(run_sql -c "select 1 from public.applied_patches where filename = '$name';")
  if [ "$applied" = "1" ]; then
    echo "✓ Schon eingespielt: $name"
    continue
  fi
  echo "→ Spiele ein: $name"
  psql "$DB_URL" -v ON_ERROR_STOP=1 --single-transaction -f "$f"
  run_sql -c "insert into public.applied_patches (filename) values ('$name');" >/dev/null
  echo "✓ Eingespielt: $name"
done

echo "Alle DB-Patches sind eingespielt."
