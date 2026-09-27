-- Patch 001: Rechte für den Feedback-Bot (tool/feedback_bot.py).
--
-- Der Bot arbeitet mit dem Service-Schlüssel: unverarbeitetes Feedback
-- lesen und abstempeln (processed_at), Fehlerberichte nach 90 Tagen
-- löschen, wie die Datenschutzerklärung es verspricht. service_role umgeht
-- RLS, aber nicht fehlende Grants — und das Live-Projekt ist ohne
-- automatische Tabellenfreigabe angelegt. Ausdrücklich statt auf eine
-- Vorgabe verlassen; ist das Recht schon da, ändert der Grant nichts.
grant select, update on public.feedback to service_role;
grant select, delete on public.error_reports to service_role;
