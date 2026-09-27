-- Patch 004: Hinweise zu einem Trail für Buddys (Issue #7).
--
-- „Baum liegt quer nach der zweiten Kehre": freier Text, der das Warum
-- trägt, das der Status (offen/gesperrt/zerstört/verändert) nicht sagen
-- kann. Kein Feedback an den Betreiber, nichts Öffentliches.
--
-- Entscheidungen des Betreibers (2026-09-28):
--   - Schreiben darf nur, wer den Trail selbst belegt hat (Konzept 3:
--     ohne Beleg kein Beitrag). Sehen dürfen ihn genau die, die den
--     Beitrag des Schreibenden sehen: er selbst und direkte Buddys, wenn
--     der Beitrag nicht „privat" ist. Keine Transitivität.
--   - Nichts verfällt von selbst; das Alter steht dabei, löschen kann der
--     Schreibende. Kein Bearbeiten — ein korrigierter Hinweis ist ein
--     neuer, sonst stimmte das angezeigte Alter nicht mehr.
--   - Eine eigene Liste, mehrere je Person; kein Teil des Status.
--
-- Der Hinweis hängt am BEITRAG (trail_details), nicht nur am Trail: Wer
-- seinen Beitrag löscht, löscht seine Hinweise mit, und die Sichtbarkeit
-- ist dieselbe Frage wie beim Beitrag. Dezentral (Konzept 12) passt das:
-- Zeilen je Autor, der Server rechnet nichts über Netzgrenzen.
set search_path = public, extensions;

create table public.trail_notes (
  id uuid primary key default gen_random_uuid(),
  trail_id uuid not null,
  user_id uuid not null,
  body text not null check (char_length(btrim(body)) between 1 and 500),
  created_at timestamptz not null default now(),
  constraint trail_notes_user_id_fkey foreign key (user_id)
    references public.profiles(id) on delete cascade,
  constraint trail_notes_details_fkey foreign key (trail_id, user_id)
    references public.trail_details(trail_id, user_id) on delete cascade
);
create index trail_notes_trail_idx on public.trail_notes (trail_id);
create index trail_notes_user_idx on public.trail_notes (trail_id, user_id);

alter table public.trail_notes enable row level security;

-- Lesen: dieselbe Regel wie trail_recordings (Abschnitt 3).
create policy notes_select on public.trail_notes for select
  using (user_id = auth.uid()
     or (app_internal.are_friends(user_id, auth.uid())
         and app_internal.contributor_shares(user_id, trail_id)));
-- Schreiben: nur als man selbst und nur mit eigener Aufzeichnung des
-- Trails. Die Unterabfrage läuft mit den Rechten des Aufrufers; die
-- eigenen Aufzeichnungen sieht er immer.
create policy notes_insert_own on public.trail_notes for insert
  with check (user_id = auth.uid()
     and exists (select 1 from public.trail_recordings r
                  where r.trail_id = trail_notes.trail_id
                    and r.user_id = auth.uid()));
create policy notes_delete_own on public.trail_notes for delete
  using (user_id = auth.uid());

-- Kein update: siehe oben.
grant select, insert, delete on public.trail_notes to authenticated;
