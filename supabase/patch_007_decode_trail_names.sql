-- Patch 007: URL-kodierte Trailnamen im Bestand aufräumen.
--
-- Vor 0.9.1 (#27) übernahm der Import Namen wie „DREI%20EICHEN%20-%20…"
-- unverändert aus der Datei (Locus beim Export von Trailforks-Spuren).
-- Was dabei unter 80 Zeichen blieb, steht so in trail_details; seit
-- 0.9.1 dekodiert der Client beim Import. Dieser Patch holt das für den
-- Bestand nach, mit DERSELBEN Regel wie `decodeTrackName` in
-- lib/features/trails/gpx.dart:
--   - nur Namen mit einem Escape `%XX`;
--   - steht irgendwo ein `%` ohne zwei Hex-Ziffern dahinter, bleibt der
--     ganze Name (wie Uri.decodeComponent, das dann abbricht) — „100 %
--     Flow" bleibt „100 % Flow";
--   - ergeben die Bytes kein gültiges UTF-8, bleibt der Name;
--   - das Ergebnis wird an den Rändern von Leerzeichen befreit; wäre es
--     leer, bleibt der alte Name (der Check verlangt 1–80 Zeichen, und
--     dekodiert ist nie länger als kodiert).
--
-- Einmalig, keine Struktur: Die Funktion lebt nur in dieser Sitzung
-- (pg_temp), schema.sql bekommt nur den Eintrag in der Saat-Liste.
-- `updated_at` des Beitrags springt mit (Trigger) — der Name hat sich ja
-- geändert.
set search_path = public, extensions;

create function pg_temp.decode_trail_name(t text)
returns text language plpgsql immutable as $$
declare
  buf bytea := ''::bytea;
  i int := 1;
  ch text;
  hex text;
  decoded text;
begin
  if t !~ '%[0-9A-Fa-f]{2}' then
    return t;
  end if;
  while i <= length(t) loop
    ch := substr(t, i, 1);
    if ch = '%' then
      hex := substr(t, i + 1, 2);
      if hex !~ '^[0-9A-Fa-f]{2}$' then
        return t;
      end if;
      buf := buf || decode(hex, 'hex');
      i := i + 3;
    else
      buf := buf || convert_to(ch, 'UTF8');
      i := i + 1;
    end if;
  end loop;
  decoded := btrim(convert_from(buf, 'UTF8'));
  return coalesce(nullif(decoded, ''), t);
exception when character_not_in_repertoire or untranslatable_character then
  return t;
end $$;

do $$
declare
  n int;
begin
  update public.trail_details
     set name = pg_temp.decode_trail_name(name)
   where name ~ '%[0-9A-Fa-f]{2}'
     and pg_temp.decode_trail_name(name) is distinct from name;
  get diagnostics n = row_count;
  raise notice 'Patch 007: % Trailnamen dekodiert', n;
end $$;

drop function pg_temp.decode_trail_name(text);
