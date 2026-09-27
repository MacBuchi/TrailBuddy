-- Rechte, die ein Wächter über die API NICHT sieht, weil er mit dem
-- Publishable Key fragt: die des Service-Schlüssels (Feedback-Bot,
-- patch_001) und die Gegenprobe, dass anon an Feedback nicht herankommt.
-- Läuft im Schema Dry Run nach beiden Wegen.
do $$
declare
  missing text := '';
begin
  if not has_table_privilege('service_role', 'public.feedback', 'select') then
    missing := missing || ' feedback:select'; end if;
  if not has_table_privilege('service_role', 'public.feedback', 'update') then
    missing := missing || ' feedback:update'; end if;
  if not has_table_privilege('service_role', 'public.error_reports', 'select') then
    missing := missing || ' error_reports:select'; end if;
  if not has_table_privilege('service_role', 'public.error_reports', 'delete') then
    missing := missing || ' error_reports:delete'; end if;
  if missing <> '' then
    raise exception 'service_role fehlen Rechte für den Feedback-Bot:%', missing;
  end if;
  if has_table_privilege('anon', 'public.feedback', 'select') then
    raise exception 'anon darf feedback lesen — das Feedback anderer wäre offen';
  end if;
  raise notice 'grants_check: ok';
end $$;
