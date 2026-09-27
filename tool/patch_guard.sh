#!/usr/bin/env bash
# Wacht über die Buchführung der DB-Patches. Zwei Prüfungen:
#
#   1. Unveränderlichkeit: Ein Patch, den es im Basis-Branch schon gibt, darf
#      nicht mehr geändert, umbenannt oder gelöscht werden. Er kann auf dem
#      Server längst eingespielt sein — `applied_patches` sorgt dafür, dass er
#      dort NIE wieder läuft. Eine nachträgliche Änderung landet also
#      ausschließlich in Frischinstallationen, und die Live-Datenbank driftet
#      still davon weg. Der Weg ist immer ein NEUER Patch.
#
#   2. Vollständigkeit der Saat: Die Liste in schema.sql, die Patches als
#      „schon enthalten" einträgt, muss exakt den Dateien auf der Platte
#      entsprechen. Fehlt einer, läuft er bei der Frischinstallation erneut
#      über ein Schema, das sein Ergebnis bereits hat; steht einer zu viel
#      drin, wird er dort nie ausgeführt, obwohl schema.sql ihn nicht abbildet.
#
# Basis-Branch über BASE_REF (Default: origin/main). Lokal ohne Argumente
# aufrufbar, in CI mit BASE_REF=origin/${{ github.base_ref }}.
#
# Übernommen aus PilzBuddy, Logik unverändert. Solange es keinen Patch
# gibt, ist „leer gegen leer" der Normalzustand — schema.sql trägt dafür
# eine Saat-Sektion mit Kommentar, aber ohne Einträge.
set -euo pipefail

BASE_REF="${BASE_REF:-origin/main}"
SCHEMA="supabase/schema.sql"
fail=0

# --- 1. Unveränderlichkeit -------------------------------------------------
if git rev-parse --verify --quiet "$BASE_REF" >/dev/null; then
  changed=$(git diff --name-status "$BASE_REF"...HEAD -- 'supabase/patch_*.sql' || true)
  while IFS=$'\t' read -r status path rest; do
    [ -z "${status:-}" ] && continue
    case "$status" in
      A) ;;  # neuer Patch — genau so soll es sein
      M)
        echo "::error file=$path::$path ist im Basis-Branch schon vorhanden und wurde geändert. Ein eingespielter Patch läuft live nie wieder — die Änderung käme nur in Frischinstallationen an. Neuen patch_NNN anlegen."
        fail=1
        ;;
      D)
        echo "::error::$path wurde gelöscht. Bereits eingespielte Patches bleiben liegen, sonst fehlt der Nachweis, was in der Live-Datenbank steht."
        fail=1
        ;;
      R*)
        echo "::error::$path wurde umbenannt (nach ${rest:-?}). Der Dateiname ist der Schlüssel in public.applied_patches — nach dem Umbenennen liefe der Patch live erneut."
        fail=1
        ;;
      *)
        echo "::error::$path: unerwarteter Git-Status $status"
        fail=1
        ;;
    esac
  done <<< "$changed"
else
  echo "::warning::$BASE_REF nicht vorhanden — Unveränderlichkeit nicht geprüft (fetch-depth 0 gesetzt?)."
fi

# --- 2. Saat in schema.sql -------------------------------------------------
on_disk=$(ls supabase/patch_*.sql 2>/dev/null | xargs -r -n1 basename | sort || true)
seeded=$(grep -o "patch_[0-9][0-9][0-9]_[a-z0-9_]*\.sql" "$SCHEMA" | sort -u || true)

if [ "$on_disk" != "$seeded" ]; then
  echo "::error::Die Patch-Liste in $SCHEMA passt nicht zu den Dateien in supabase/."
  echo "Nur auf der Platte:"
  comm -23 <(echo "$on_disk") <(echo "$seeded") | sed 's/^/  + /'
  echo "Nur in $SCHEMA:"
  comm -13 <(echo "$on_disk") <(echo "$seeded") | sed 's/^/  - /'
  echo "Ein neuer Patch gehört im selben PR in die insert-Liste am Ende von $SCHEMA — und seine Struktur in den Rest der Datei."
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo "Patch-Buchführung in Ordnung: $(printf '%s\n' "$on_disk" | grep -c . || true) Patches, Saat deckungsgleich."
