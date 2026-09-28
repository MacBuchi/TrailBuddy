-- Patch 005: Hinweise für alle am Trail, drei Monate Aufbewahrung (#7).
--
-- Nachentscheidung des Betreibers (2026-09-28), nachdem Patch 004 schon
-- eingespielt war:
--   - Schreiben darf jeder, der den Trail SIEHT — nicht nur, wer ihn
--     selbst belegt hat. Damit hängt ein Hinweis nicht mehr am Beitrag
--     (den hat nicht jeder), sondern am Trail.
--   - Sehen: der Autor selbst; sonst seine direkten Buddys, sofern sie den
--     Trail sehen und der Autor dort nicht auf „privat" steht. Keine
--     Transitivität.
--   - Entfernen darf ihn der Autor und jeder, der ihn sieht — wer am
--     Trail steht und den Baum weggeräumt findet, soll „erledigt" sagen
--     können.
--   - Nach 90 Tagen wird aufgeräumt; der jüngste Hinweis eines Autors zu
--     einem Trail bleibt, bis ihn jemand entfernt. Je AUTOR, nicht je
--     Trail: Welcher Hinweis über alle Netze der jüngste ist, wäre eine
--     Rechnung über Netzgrenzen (Konzept 12). Für jeden Leser bleibt so
--     trotzdem sein jüngster sichtbarer Hinweis stehen.
set search_path = public, extensions;

alter table public.trail_notes drop constraint trail_notes_details_fkey;
alter table public.trail_notes add constraint trail_notes_trail_id_fkey
  foreign key (trail_id) references public.trails(id) on delete cascade;

-- Sieht [uid] den Trail? Dieselbe Regel wie recordings_select, als
-- Definer, damit Policies sie ohne Umweg über die RLS fragen können.
create or replace function app_internal.can_see_trail(uid uuid, trail uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from trail_recordings r
     where r.trail_id = trail
       and (r.user_id = uid
         or (app_internal.are_friends(r.user_id, uid)
             and app_internal.contributor_shares(r.user_id, trail))));
$$;

drop policy notes_select on public.trail_notes;
drop policy notes_insert_own on public.trail_notes;
drop policy notes_delete_own on public.trail_notes;

create policy notes_select on public.trail_notes for select
  using (user_id = auth.uid()
     or (app_internal.are_friends(user_id, auth.uid())
         and app_internal.contributor_shares(user_id, trail_id)
         and app_internal.can_see_trail(auth.uid(), trail_id)));
create policy notes_insert on public.trail_notes for insert
  with check (user_id = auth.uid()
     and app_internal.can_see_trail(auth.uid(), trail_id));
create policy notes_delete on public.trail_notes for delete
  using (user_id = auth.uid()
     or (app_internal.are_friends(user_id, auth.uid())
         and app_internal.contributor_shares(user_id, trail_id)
         and app_internal.can_see_trail(auth.uid(), trail_id)));

create or replace function app_internal.sweep_old_notes()
returns integer
language plpgsql security definer set search_path = public as $$
declare
  n integer;
begin
  delete from trail_notes old
   where old.created_at < now() - interval '90 days'
     and exists (select 1 from trail_notes newer
                  where newer.trail_id = old.trail_id
                    and newer.user_id = old.user_id
                    and newer.created_at > old.created_at);
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function app_internal.sweep_old_notes() from public, anon, authenticated;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    execute $cron$select cron.schedule('notes-sweep', '37 3 * * *',
              'select app_internal.sweep_old_notes()')$cron$;
  else
    raise notice 'pg_cron nicht verfügbar — sweep_old_notes() ist nicht eingeplant (lokaler Testlauf).';
  end if;
end $$;
