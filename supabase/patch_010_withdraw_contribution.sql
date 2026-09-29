-- Patch 010: den eigenen Beitrag zu einem Trail zurückziehen (Löschen in
-- der App). Kein neues Recht, nur eine gemeinsame Transaktion.
set search_path = public, extensions;

-- Den eigenen Beitrag zu einem Trail zurückziehen (Konzept 4, „Löschen
-- und DSGVO"): eigene Aufzeichnungen, eigene Hinweise und der eigene
-- Beitrag, in EINER Transaktion. Einzeln aus der App wäre es nicht
-- dasselbe: Fällt zuerst der Beitrag, steht „privat" nicht mehr da
-- (`contributor_shares` sagt ohne Zeile „teilt"), und die eigenen
-- Aufzeichnungen und Hinweise wären bis zum nächsten Schritt für Buddys
-- sichtbar; bricht es mittendrin ab, bliebe ein halber Beitrag stehen.
-- Der Trail selbst bleibt, solange ein anderer ihn belegt; ohne jeden
-- Beleg holt ihn `sweep_orphan_trails` (nächtlich).
--
-- Security INVOKER: Die RLS erlaubt jede der drei Löschungen ohnehin
-- (recordings_delete_own, td_owner_all, notes_delete) — die Funktion
-- braucht keine Rechte darüber hinaus, nur die gemeinsame Transaktion.
-- Gibt die Zahl der gelöschten Aufzeichnungen zurück.
create or replace function public.withdraw_contribution(trail_id uuid)
returns integer
language plpgsql security invoker set search_path = public as $$
declare
  uid uuid := auth.uid();
  n integer;
begin
  if uid is null then
    raise exception 'Nicht angemeldet' using errcode = '28000';
  end if;
  delete from trail_recordings r
   where r.trail_id = withdraw_contribution.trail_id and r.user_id = uid;
  get diagnostics n = row_count;
  delete from trail_notes t
   where t.trail_id = withdraw_contribution.trail_id and t.user_id = uid;
  delete from trail_details d
   where d.trail_id = withdraw_contribution.trail_id and d.user_id = uid;
  return n;
end $$;

revoke all on function public.withdraw_contribution(uuid) from public, anon;
grant execute on function public.withdraw_contribution(uuid) to authenticated;
