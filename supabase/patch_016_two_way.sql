-- Patch 016 (#174): „In beide Richtungen fahrbar" je Beitrag.
--
-- Der Planer fährt einen Trail nie gegen seine Richtung — weder als
-- Abfahrt noch als Aufstieg über die Wege, die auf ihm liegen
-- (Feldbericht 0.73.0: „man sollte nie rückwärts über einen Trail
-- fahren, außer der Trail ist so attributiert"). Die Ausnahme ist eine
-- Angabe des Beitrags, Vorgabe AUS: Ein flacher Singletrail darf auch
-- andersherum. Angezeigt und benutzt wird auf dem Gerät: die eigene
-- Angabe, sonst die Mehrheit der sichtbaren Beiträge (Konzept 12, keine
-- Rechnung über alle).
--
-- Eine Spalte, kein neues Merkmal in `traits`: Ein Client bis 0.73.0
-- schreibt beim Speichern seine `traits` vollständig und hätte ein
-- unbekanntes Merkmal still gelöscht; eine Spalte, die er nicht kennt,
-- schickt er nicht mit, und das Upsert lässt sie stehen.
set search_path = public, extensions;

alter table public.trail_details
  add column if not exists two_way boolean not null default false;

comment on column public.trail_details.two_way is
  'Patch 016 (#174): in beide Richtungen fahrbar — der Planer fährt den Trail sonst nie gegen seine Richtung.';
