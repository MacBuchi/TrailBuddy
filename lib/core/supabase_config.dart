/// Zugangsdaten des Supabase-Projekts.
///
/// **Noch kein Live-Projekt.** Die Vorgaben zeigen auf den lokalen Stack
/// aus `supabase/config.toml` (Ports 5452x, damit er neben dem
/// PilzBuddy-Stack laufen kann); der anon-Key des lokalen Stacks ist
/// fest und öffentlich dokumentiert, er steht nur als Platzhalter hier —
/// `supabase status -o json` liefert den gültigen.
///
/// Ein Live-Projekt kommt über `--dart-define=SUPABASE_URL=…` und
/// `--dart-define=SUPABASE_KEY=…` in den Build, oder später durch
/// Ersetzen der Vorgaben. Der Publishable-Key ist bewusst öffentlich —
/// die Sicherheit liegt vollständig in den Row-Level-Security-Policies
/// (`supabase/schema.sql`). Niemals den service_role-Key eintragen.
class SupabaseConfig {
  static const url = String.fromEnvironment('SUPABASE_URL',
      defaultValue: 'http://127.0.0.1:54521');
  static const publishableKey = String.fromEnvironment('SUPABASE_KEY',
      defaultValue: 'local-anon-key-placeholder-see-supabase-status');
}
