-- Patch 009: der Charakter eines Trails (Issue #72) — Mehrfachwahl je
-- Beitrag statt der Einzelwahl „Art" (`kind`).
--
-- Sieben Merkmale, Entscheidung des Betreibers vom 2026-09-29: die fünf
-- aus dem Design (flowig, Jump-Line, verblockt, steil, uphill) plus
-- Naturtrail und Verbindung aus der alten Art, damit beim Übernehmen
-- nichts verloren geht. Angezeigt werden in der App die höchstens zwei
-- häufigsten über alle sichtbaren Beiträge — gezählt auf dem Gerät, wie
-- der Grad (Konzept 12: keine Rechnung über alle Nutzer).
--
-- Erweitern → ausliefern → entfernen: `kind` BLEIBT stehen. Clients bis
-- 0.33.0 lesen und schreiben sie weiter; ab 0.34.0 liest und schreibt die
-- App nur `traits`. Entfernt wird `kind` in einem späteren Patch, wenn
-- `minimum_supported_version` über 0.33.0 liegt.
--
-- Die Rechte gelten je Tabelle (select/insert/update für authenticated),
-- die neue Spalte ist damit ohne eigenen Grant erreichbar; die RLS-
-- Policies bleiben unverändert — Sichtbarkeit wie der Grad.
set search_path = public, extensions;

alter table public.trail_details
  add column traits text[] not null default '{}'
    constraint trail_details_traits_check check (
      traits <@ array['flowy', 'jumps', 'rocky', 'steep', 'uphill', 'natural', 'connection']::text[]
      and cardinality(traits) <= 7);

-- Die alte Art als Merkmal übernehmen — dieselbe Zuordnung wie
-- `TrailTrait.fromLegacyKind` in der App.
update public.trail_details
   set traits = array[case kind
                        when 'flow' then 'flowy'
                        when 'jump' then 'jumps'
                        when 'tech' then 'rocky'
                        else kind
                      end]
 where kind is not null and traits = '{}';

comment on column public.trail_details.kind is
  'Veraltet seit Patch 009 (Issue #72): nur noch für Clients bis 0.33.0; ersetzt durch traits.';
