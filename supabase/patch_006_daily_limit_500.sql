-- Patch 006: Tageslimit 50 → 500 Aufzeichnungen (Issue #23).
--
-- 50 sollten „auch für einen Bestandsimport an einem Abend" reichen
-- (Konzept 4.6) — der gemessene Bestand hat aber 454 Trails, das wären
-- zehn Tage. Gegen das Sondieren schützt die Zahl nichts (der Abgleich
-- verrät ohnehin nichts); sie schützt die Datenbank vor Fluten. Gemessen
-- (docs/trail-abgleich-messung.md, Abschnitt Tageslimit): 450 Import-
-- Aufzeichnungen, jede „gleich" (teuerster Weg), kosten lokal 144 s,
-- p95 0,5 s je Aufruf. Entscheidung des Betreibers vom 2026-09-28: 500.
--
-- Nur die eine Zahl; alles andere wie in schema.sql.
set search_path = public, extensions;

create or replace function app_internal.match_params()
returns app_internal.match_params
language sql immutable set search_path = '' as $$
  select row(15.0, 0.8, 2.0, 150.0, 5.0, 400, 0.3, 0.7, 0.3, 500)::app_internal.match_params;
$$;
