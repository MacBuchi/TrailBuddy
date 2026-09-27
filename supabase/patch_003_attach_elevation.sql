-- Patch 003: Höhen nachtragen (Issue #16).
--
-- Nur eine neue Funktion; keine Spalte, keine Sicht, keine Daten.
set search_path = public, extensions;

-- Höhen nachtragen (Patch 003, Issue #16): Eine eigene Aufzeichnung
-- ohne Höhen bekommt sie aus der Originaldatei, statt dass ein zweiter
-- Import eine zweite Aufzeichnung anlegt. Kein Abgleich, kein neuer
-- Trail, keine Kante, nicht im Tageslimit.
--
-- Der Client schickt die GESPEICHERTE Linie zurück — deren Punkte sind
-- Originalpunkte der Datei, er findet sie dort samt Höhe — und hier muss
-- sie Punkt für Punkt dieselbe sein (≤ 5 cm; `st_asgeojson` rundet auf
-- neun Stellen). Nicht „eine Linie in der Nähe": sonst ließen sich
-- beliebige Höhen an fremde Stellen hängen. Neu vereinfachen ginge
-- nicht, weil 0.3.0 die Vereinfachung dreidimensional gemacht hat.
--
-- Gibt true zurück, wenn geschrieben wurde, false, wenn die Aufzeichnung
-- schon Höhen hat (Wiederholung nach einem Abriss: kein Fehler, aber
-- auch kein Überschreiben).
create or replace function public.attach_elevation(
  recording_id uuid,
  coords double precision[],
  eles double precision[])
returns boolean
language plpgsql security definer set search_path = public, extensions as $$
declare
  uid uuid := auth.uid();
  stored geometry;
  stored_ele real[];
  npts integer;
begin
  if uid is null then
    raise exception 'Nicht angemeldet' using errcode = '28000';
  end if;
  select r.geom::geometry, r.ele into stored, stored_ele
    from trail_recordings r
   where r.id = attach_elevation.recording_id and r.user_id = uid
     for update;
  if not found then
    -- Fremd oder gelöscht: dieselbe Antwort, damit die Funktion nicht
    -- verrät, ob es eine fremde Aufzeichnung mit dieser Kennung gibt.
    raise exception 'Keine eigene Aufzeichnung' using errcode = 'P0002';
  end if;
  if stored_ele is not null then
    return false;
  end if;
  npts := coalesce(array_length(coords, 1), 0);
  if npts % 2 <> 0 or npts / 2 <> st_npoints(stored) then
    raise exception 'Linie passt nicht: % Punkte für % gespeicherte', npts / 2, st_npoints(stored)
      using errcode = '22023';
  end if;
  if coalesce(array_length(eles, 1), 0) <> npts / 2
     or array_position(eles, null) is not null
     or exists (select 1 from unnest(eles) e where e not between -500 and 9000) then
    raise exception 'Höhen: eine je Punkt, zwischen −500 und 9000 m' using errcode = '22023';
  end if;
  if exists (
    select 1 from generate_series(1, npts / 2) i
     where not st_dwithin(st_pointn(stored, i)::geography,
                          st_setsrid(st_makepoint(coords[2 * i - 1], coords[2 * i]), 4326)::geography,
                          0.05)) then
    raise exception 'Die Linie ist nicht die gespeicherte' using errcode = '22023';
  end if;
  update trail_recordings r
     set ele = array(select e::real from unnest(eles) with ordinality u(e, o) order by o)
   where r.id = attach_elevation.recording_id;
  return true;
end $$;

revoke all on function public.attach_elevation(uuid, double precision[], double precision[])
  from public, anon;
grant execute on function public.attach_elevation(uuid, double precision[], double precision[])
  to authenticated;
