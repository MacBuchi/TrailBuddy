-- Patch 012 (#103): ein Link zur Quelle im eigenen Beitrag — die Seite
-- eines Vereins mit Beschreibung und Regeln, vorgeschlagen aus dem <link>
-- der GPX-Datei (docs/konzept-rework.md, Abschnitt 4). Er gehört dem
-- Beitrag, nicht dem Trail: Angezeigt wird der eigene, sonst der des
-- ältesten sichtbaren Beitrags, wie beim Namen.
--
-- Nur https, höchstens 500 Zeichen, ohne Query und Fragment:
-- Freigabelinks von Tourenportalen tragen dort Tokens und Kennungen. Die
-- App kürzt schon beim Vorschlagen; der Check hält es für jeden Client.
-- Ältere Clients schreiben per upsert nur ihre Spalten und lassen den
-- Link stehen. Die Tabellenrechte gelten für die neue Spalte mit.
set search_path = public, extensions;

alter table public.trail_details
  add column if not exists link text
  constraint trail_details_link_check check (link is null or (link ~ '^https://[^[:space:]/?#]+(/[^[:space:]?#]*)?$' and char_length(link) <= 500));
