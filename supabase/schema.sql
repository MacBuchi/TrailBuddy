-- TrailBuddy — Supabase-Schema (Frischinstallation).
-- Komplett im Supabase-Dashboard unter „SQL Editor" einfügen und ausführen,
-- oder per psql (tool/schema_local_test.sh fährt genau das gegen einen
-- nackten Postgres mit tool/auth_shim.sql davor).
--
-- Die Datei muss für sich vollständig sein: Der Schema Dry Run spielt sie
-- auf eine leere Datenbank und danach NICHTS mehr (PilzBuddy-Muster).
-- Ein späterer patch_NNN gehört im selben PR in die Struktur hier UND in
-- die Saat-Liste am Ende; tool/patch_guard.sh erzwingt beides.
--
-- Was hier abgebildet ist, steht in docs/konzept-trails.md: Abschnitt 3
-- (Datenmodell), 4 (Abgleich), 10 (Entscheidungen des Betreibers). Die
-- Schwellen des Abgleichs sind gemessen (docs/trail-abgleich-messung.md)
-- und stehen an EINER Stelle: app_internal.match_params().

-- ============================================================
-- PostGIS
-- ============================================================
-- Supabase-Konvention: Erweiterungen liegen im Schema `extensions`. Auf
-- einem nackten Postgres gibt es das Schema nicht — deshalb zuerst
-- anlegen, dann funktioniert dieselbe Zeile auf beiden. Ist PostGIS im
-- Projekt schon eingeschaltet, tut `if not exists` nichts.
create schema if not exists extensions;
create extension if not exists postgis with schema extensions;
-- Damit Sicht und Funktionsköpfe (Typ `geometry`) PostGIS ohne Präfix
-- finden. Supabase hat `extensions` ohnehin im Suchpfad, psql nicht. Die
-- Funktionsrümpfe verlassen sich NICHT darauf: Jede Funktion trägt ihren
-- eigenen festen search_path (PilzBuddy Patch 036).
set search_path = public, extensions;
grant usage on schema extensions to anon, authenticated;

-- ============================================================
-- Tabellen: Konto und Buddys (aus PilzBuddy übernommen)
-- ============================================================

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text unique not null,
  display_name text,
  avatar int not null default 0,               -- Index im Avatar-Katalog
  created_at timestamptz not null default now()
);
-- Einmalig auch über Groß-/Kleinschreibung hinweg (PilzBuddy Patch 013):
-- Die Buddy-Suche matcht per ilike auf das Namens-Präfix, „Trailbiker"
-- und „trailbiker" wären für Suchende dasselbe Konto.
create unique index profiles_username_lower_key
  on public.profiles (lower(username));

create table public.friendships (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references public.profiles(id) on delete cascade,
  addressee_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','accepted')),
  created_at timestamptz not null default now(),
  check (requester_id <> addressee_id)
);
-- verhindert doppelte Paare in beiden Richtungen
create unique index friendships_pair_uidx on public.friendships
  (least(requester_id, addressee_id), greatest(requester_id, addressee_id));
-- RLS-Policies und are_friends filtern über diese Spalten
create index friendships_requester_idx on public.friendships (requester_id);
create index friendships_addressee_idx on public.friendships (addressee_id);

-- Aliase für Buddys (PilzBuddy Patch 032): eine private Notiz je Buddy,
-- nur für den, der sie vergibt; nur für bestätigte Buddys; Ende der
-- Freundschaft löscht sie (Trigger unten). Beide Personen auf auth.users,
-- nicht auf profiles — sonst hielte PostgREST die Tabelle für eine
-- Verbindungstabelle und Embeds auf profiles würden mehrdeutig (PGRST201).
create table public.friend_aliases (
  owner_id uuid not null default auth.uid()
    references auth.users(id) on delete cascade,
  friend_id uuid not null references auth.users(id) on delete cascade,
  alias text not null check (char_length(btrim(alias)) between 1 and 40),
  updated_at timestamptz not null default now(),
  primary key (owner_id, friend_id),
  check (owner_id <> friend_id)
);
create index friend_aliases_friend_idx on public.friend_aliases (friend_id);

-- Feedback aus der App. Ohne Bilder und ohne Arten (das war PilzBuddy);
-- `processed_at` setzt der Feedback-Bot, wenn er daraus ein Issue macht.
create table public.feedback (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  type text not null default 'feature' check (type in ('feature', 'bug')),
  message text not null check (char_length(message) between 3 and 2000),
  app_version text check (char_length(app_version) <= 40),
  processed_at timestamptz,
  created_at timestamptz not null default now()
);

-- Gefangene Fehler aus dem Feld (PilzBuddy Patch 009). Android Vitals
-- sieht nur harte Abstürze auf Play-Installationen — die abgefangenen
-- Fehler, bei denen die App mit einer SnackBar weiterläuft, landen hier.
-- Absichtlich ohne Nutzdaten: kein Standort, keine Namen, keine Linie.
create table public.error_reports (
  id uuid primary key default gen_random_uuid(),
  -- Nullable: die wertvollsten Fehler passieren vor der Anmeldung.
  user_id uuid references public.profiles(id) on delete cascade,
  context text not null check (char_length(context) between 1 and 100),
  error_type text not null check (char_length(error_type) <= 100),
  message text check (char_length(message) <= 1000),
  stack text check (char_length(stack) <= 4000),
  app_version text check (char_length(app_version) <= 40),
  platform text check (char_length(platform) <= 20),
  created_at timestamptz not null default now()
);
create index error_reports_created_idx
  on public.error_reports (created_at desc);

-- Server-seitige App-Konfiguration (PilzBuddy Patch 012). Einzeilige
-- Tabelle: der check lässt nur id = true zu. minimum_supported_version
-- sperrt Clients aus, die zu alt für das aktuelle Schema sind — jede
-- Breaking-Migration setzt den Wert im selben PR hoch, per Patch, nie von
-- Hand. Der Wert darf nie über dem STABILEN Stand liegen
-- (tool/schema_check.sh wacht darüber).
create table public.app_config (
  id boolean primary key default true check (id),
  minimum_supported_version text not null default '0.0.0'
    check (minimum_supported_version ~ '^[0-9]+\.[0-9]+\.[0-9]+$'),
  updated_at timestamptz not null default now()
);
insert into public.app_config (id) values (true);

-- ============================================================
-- Tabellen: Trails (Konzept Abschnitt 3)
-- ============================================================

-- Die Kennung. Bewusst ohne Name, ohne Besitzer, ohne created_at: Nichts
-- in dieser Zeile darf verraten, dass jemand anderes den Trail schon
-- hatte. Der Client liest diese Tabelle NIE — er fragt „welche
-- Aufzeichnungen und Beiträge sehe ich" und gruppiert nach trail_id.
-- Deshalb weiter unten: RLS an, keine Grants für anon und authenticated.
create table public.trails (
  id uuid primary key default gen_random_uuid()
);

-- Ein Beleg: „ich bin das gefahren". Geometrie in WGS84 als geography,
-- damit ST_DWithin in Metern rechnet und der GiST-Index den Vorfilter des
-- Abgleichs trägt (Abschnitt 4.2, Stufe 1).
create table public.trail_recordings (
  id uuid primary key default gen_random_uuid(),
  trail_id uuid not null references public.trails(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  geom geography(LineString, 4326) not null,
  recorded_at timestamptz,             -- null bei Import ohne Zeiten
  -- 'planned': importierte Datei ohne Zeiten oder mit unplausiblen
  -- Geschwindigkeiten — eine geplante Route, keine Fahrt. Zählt als
  -- Beitrag (Entscheidung 2), mit Qualität nahe null.
  source text not null check (source in ('app', 'import', 'planned')),
  reversed boolean not null default false,  -- gegen die Trail-Richtung gefahren (4.3)
  quality real not null check (quality between 0 and 1),  -- 0..1, siehe 4.5
  created_at timestamptz not null default now(),
  -- Vom Gerät vergebene Kennung des Auftrags aus dem Ausgangskorb
  -- (PilzBuddy Patch 016): macht die Wiedervorlage nach einem
  -- abgerissenen Aufruf idempotent. Leer bei allem, was nicht über den
  -- Korb kam.
  client_id uuid
);
create index trail_recordings_geom_gix on public.trail_recordings using gist (geom);
create index trail_recordings_trail_idx on public.trail_recordings (trail_id);
create index trail_recordings_user_idx on public.trail_recordings (user_id);
-- Zweimal derselbe Auftrag ⇒ derselbe Trail statt Dublette. Partiell,
-- weil die Spalte für Aufzeichnungen ohne Korb leer bleibt.
create unique index trail_recordings_user_client_id_key
  on public.trail_recordings (user_id, client_id)
  where client_id is not null;

-- Was ein Nutzer über einen Trail sagt. Genau eine Zeile je Nutzer und
-- Trail. Entsteht mit der ersten Aufzeichnung (contribute_recording).
create table public.trail_details (
  trail_id uuid not null references public.trails(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  name text check (name is null or char_length(name) between 1 and 80),
  description text check (description is null or char_length(description) <= 2000),
  grade smallint check (grade between 0 and 5),   -- Singletrail-Skala S0–S5
  kind text check (kind in ('natural', 'flow', 'tech', 'jump', 'connection')),
  visibility text not null default 'buddies' check (visibility in ('buddies', 'private')),
  status text not null default 'open' check (status in ('open', 'closed', 'destroyed', 'changed')),
  status_at timestamptz,
  -- Nicht in der Skizze des Konzepts, aber von ihr verlangt: „Name =
  -- eigener Name, sonst der Name des ÄLTESTEN sichtbaren Beitrags"
  -- (Abschnitt 3) braucht das Alter des Beitrags, und updated_at ändert
  -- sich mit jeder Korrektur.
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (trail_id, user_id)
);
create index trail_details_user_idx on public.trail_details (user_id);

-- ============================================================
-- Profil automatisch bei Registrierung anlegen
-- (Username kommt aus den Signup-Metadaten der App)
-- ============================================================

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, username)
  values (new.id,
          coalesce(new.raw_user_meta_data->>'username',
                   'trailbuddy_' || substr(new.id::text, 1, 8)));
  return new;
end $$;

-- Nur der Trigger ruft die Funktion — die Default-Grants an die API-Rollen
-- sind unnötig (EXECUTE wird beim Anlegen des Triggers geprüft, nicht beim
-- Feuern).
revoke all on function public.handle_new_user() from public, anon, authenticated;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

-- ============================================================
-- app_internal: Hilfsfunktionen, Matcher, unsichtbare Nachbarschaft
--
-- Bewusst NICHT in public: PostgREST exponiert jede Funktion im
-- public-Schema als /rest/v1/rpc/-Endpunkt für anon+authenticated.
-- EXECUTE entziehen geht bei Policy-Helfern nicht — die Policies werten
-- die Funktionen mit den Rechten der anfragenden Rolle aus. Deshalb liegen
-- sie in app_internal, das die API nie sieht (PilzBuddy Patch 011).
-- ============================================================

create schema if not exists app_internal;
grant usage on schema app_internal to anon, authenticated;

-- Unsichtbare Nachbarschaft (Abschnitt 4.4): „Trail A überlappt Trail B
-- zu 45 %". Der Vorrat für ein späteres „Sind das dieselben?" zwischen
-- zwei Buddys, die beide Linien sehen. KEIN Client liest diese Tabelle —
-- ein Zähler oder eine Kante nach außen verriete, dass jemand anderes
-- den Nachbarn kennt (4.6).
create table app_internal.trail_overlaps (
  a uuid not null references public.trails(id) on delete cascade,
  b uuid not null references public.trails(id) on delete cascade,
  coverage_ab real,   -- Anteil von A im Korridor von B
  coverage_ba real,   -- Anteil von B im Korridor von A
  created_at timestamptz not null default now(),
  primary key (a, b)
);
create index trail_overlaps_b_idx on app_internal.trail_overlaps (b);

create or replace function app_internal.are_friends(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from friendships
    where status = 'accepted'
      and ((requester_id = a and addressee_id = b)
        or (requester_id = b and addressee_id = a)));
$$;

-- Auch offene Anfragen zählen — nötig, damit man den Namen des
-- Absenders einer Freundschaftsanfrage sehen kann.
create or replace function app_internal.involved_in_friendship(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from friendships
    where (requester_id = a and addressee_id = b)
       or (requester_id = b and addressee_id = a));
$$;

-- Teilt [contributor] seinen Beitrag zu [trail] mit Buddys? Die
-- Sichtbarkeit steht am BEITRAG (trail_details.visibility). Fehlt die
-- Zeile noch, gilt die Vorgabe `buddies` — dieselbe Antwort, die die
-- Zeile mit ihrem Default gäbe, wenn sie schon da wäre.
create or replace function app_internal.contributor_shares(contributor uuid, trail uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(
    (select d.visibility = 'buddies'
       from trail_details d
      where d.trail_id = trail and d.user_id = contributor),
    true);
$$;

-- ------------------------------------------------------------
-- Der Abgleich (Abschnitt 4). Spiegel von tool/trail_match.py —
-- dieselbe Pipeline, dieselben Schwellen. Wer hier eine Zahl ändert,
-- misst sie dort nach und ändert beide im selben PR.
-- ------------------------------------------------------------

-- Alle Schwellen an EINER Stelle. Gemessen am 2026-09-27 an 584 Tracks
-- (docs/trail-abgleich-messung.md); Begründung je Wert in Abschnitt 4.2:
--   corridor_m        15   GPS unter Blätterdach liegt 10–20 m daneben
--   coverage_same     0.8  Lücke in der Verteilung zwischen 0,7 und 0,9
--   frechet_factor    2    „gleich" ≤ 2·d; alle Gleichen ≤ 19,4 m, der
--                          nächste Wert 84 m
--   min_trail_m       150  darunter Zufahrt oder Fragment
--   step_m            5    Kehren mit 10 m Radius bleiben sichtbar
--   frechet_max_points 400 Kappe für die O(n·m)-DP in PL/pgSQL (unten)
--   overlap_min       0.3  ab hier eine Kante in trail_overlaps (Gabel)
--   direction_same / direction_reversed: Anteil steigender Schritte
--                          entlang der anderen Linie (≥ 0,7 / ≤ 0,3)
--   daily_limit       50   Aufzeichnungen je Nutzer und Tag (4.6, „Rate")
create type app_internal.match_params as (
  corridor_m double precision,
  coverage_same double precision,
  frechet_factor double precision,
  min_trail_m double precision,
  step_m double precision,
  frechet_max_points integer,
  overlap_min double precision,
  direction_same double precision,
  direction_reversed double precision,
  daily_limit integer
);

create or replace function app_internal.match_params()
returns app_internal.match_params
language sql immutable set search_path = '' as $$
  select row(15.0, 0.8, 2.0, 150.0, 5.0, 400, 0.3, 0.7, 0.3, 50)::app_internal.match_params;
$$;

-- Ergebnis eines Vergleichs Kandidat (a) gegen Bestand (b). `class` ist
-- das Wort aus PairResult.classify(): same, same-reversed, neighbour,
-- a-in-b, b-in-a, fork, different.
create type app_internal.match_result as (
  cov_ab real,
  cov_ba real,
  direction text,
  frechet_m real,
  class text
);

-- Metrische Projektion: die UTM-Zone des Schwerpunkts. Beide Linien eines
-- Paars werden in DIESELBE Zone projiziert, damit Abstände vergleichbar
-- sind; ein Paar am Zonenrand bleibt auf wenige Promille genau — mehr
-- braucht ein 15-m-Korridor nicht. (trail_match.py nimmt eine
-- äquirektanguläre Näherung um die mittlere Breite; dieselbe Klasse
-- Genauigkeit.)
create or replace function app_internal.utm_srid(g geometry)
returns integer
language sql immutable set search_path = public, extensions as $$
  select (case when st_y(c) >= 0 then 32600 else 32700 end)
       + least(60, greatest(1, floor((st_x(c) + 180) / 6)::int + 1))
    from (select st_centroid(g) as c) s;
$$;

-- Punkte alle `step` Meter entlang der Linie, Anfang und Ende dabei — wie
-- resample() im Werkzeug. Locus-Exporte sind auf ~13 m gedünnt und
-- gezeichnete Routen haben 100-m-Schenkel; ein Korridortest auf den
-- Stützpunkten allein übersähe die Linie dazwischen.
create or replace function app_internal.resample(g geometry, step double precision)
returns geometry[]
language plpgsql immutable set search_path = public, extensions as $$
declare
  len double precision := st_length(g);
  pts geometry[];
begin
  if len <= step then
    return array[st_startpoint(g), st_endpoint(g)];
  end if;
  select array_agg(d.geom order by d.path)
    into pts
    from st_dumppoints(st_lineinterpolatepoints(g, step / len, true)) d;
  pts := array[st_startpoint(g)] || pts;
  if st_distance(pts[array_upper(pts, 1)], st_endpoint(g)) > 0.01 then
    pts := pts || st_endpoint(g);
  end if;
  return pts;
end $$;

-- Diskrete Fréchet-Distanz, Zwei-Zeilen-DP — Zeile für Zeile frechet()
-- aus trail_match.py. O(n·m): Deshalb kappt match_lines die Punktzahl
-- je Linie auf frechet_max_points (400 ⇒ höchstens 160 000 Zellen; auf
-- dem lokalen Postgres gemessen im Bereich von Zehntelsekunden). Das
-- Werkzeug rechnet mit 1200, hat aber Python-Zeit statt Datenbankzeit.
-- PostGIS hätte ST_FrechetDistance in C; die eigene DP steht hier, damit
-- Werkzeug und Datenbank nachweislich denselben Algorithmus fahren
-- (tool/matcher_check.sql vergleicht beide an einem Beispiel).
create or replace function app_internal.frechet(p geometry[], q geometry[])
returns double precision
language plpgsql immutable set search_path = public, extensions as $$
declare
  n integer := coalesce(array_length(p, 1), 0);
  m integer := coalesce(array_length(q, 1), 0);
  px double precision[]; py double precision[];
  qx double precision[]; qy double precision[];
  prev double precision[];
  cur double precision[];
  d double precision;
  best double precision;
  i integer; j integer;
begin
  if n < 2 or m < 2 then
    return 'infinity'::double precision;
  end if;
  select array_agg(st_x(g) order by o), array_agg(st_y(g) order by o)
    into px, py from unnest(p) with ordinality t(g, o);
  select array_agg(st_x(g) order by o), array_agg(st_y(g) order by o)
    into qx, qy from unnest(q) with ordinality t(g, o);
  prev := array_fill('infinity'::double precision, array[m]);
  for i in 1..n loop
    cur := array_fill('infinity'::double precision, array[m]);
    for j in 1..m loop
      d := sqrt((px[i] - qx[j]) * (px[i] - qx[j]) + (py[i] - qy[j]) * (py[i] - qy[j]));
      if i = 1 and j = 1 then
        cur[1] := d;
      else
        best := 'infinity'::double precision;
        if i > 1 then best := least(best, prev[j]); end if;
        if j > 1 then best := least(best, cur[j - 1]); end if;
        if i > 1 and j > 1 then best := least(best, prev[j - 1]); end if;
        cur[j] := greatest(best, d);
      end if;
    end loop;
    prev := cur;
  end loop;
  return prev[m];
end $$;

-- Ein Paar vergleichen: a = Kandidat, b = beste Aufzeichnung eines
-- bestehenden Trails, beide schon metrisch projiziert (gleiche SRID).
-- Stufen wie compare() im Werkzeug:
--   2. Deckung beidseitig auf 5-m-Abtastung, Abstand zum nächsten
--      SEGMENT (ST_DWithin gegen die Linie, nicht gegen Stützpunkte);
--   3. Richtung aus der Reihenfolge der Fußpunkte auf b
--      (ST_LineLocatePoint steigt monoton mit der Bogenlänge);
--   4. Fréchet NUR auf den Punkten im Korridor, beide Seiten vorher
--      beschnitten, bei Gegenrichtung auf der umgedrehten Linie — der
--      Test, der einen Serpentinen-Trail von seinem um eine Kehre
--      versetzten Nachbarn trennt, was Deckung allein nicht kann.
create or replace function app_internal.match_lines(a geometry, b geometry)
returns app_internal.match_result
language plpgsql stable set search_path = public, extensions as $$
declare
  p app_internal.match_params := app_internal.match_params();
  sa geometry[] := app_internal.resample(a, p.step_m);
  sb geometry[] := app_internal.resample(b, p.step_m);
  cov_ab double precision;
  cov_ba double precision;
  ups integer;
  diffs integer;
  direction text := 'mixed';
  fstep double precision;
  fa geometry[];
  fb geometry[];
  fr double precision;
  cls text;
begin
  select count(*) filter (where st_dwithin(s, b, p.corridor_m))::double precision / count(*)
    into cov_ab from unnest(sa) s;
  select count(*) filter (where st_dwithin(s, a, p.corridor_m))::double precision / count(*)
    into cov_ba from unnest(sb) s;

  -- Richtung: Anteil der Schritte, bei denen der Fußpunkt auf b weiter
  -- vorn liegt als beim vorigen Punkt. Unter drei Schritten keine Aussage.
  with near as (
    select o, st_linelocatepoint(b, s) as frac
      from unnest(sa) with ordinality t(s, o)
     where st_dwithin(s, b, p.corridor_m)
  ), steps as (
    select frac - lag(frac) over (order by o) as df from near
  )
  select count(*) filter (where df > 0), count(*)
    into ups, diffs from steps where df is not null;
  if diffs >= 3 then
    if ups::double precision / diffs >= p.direction_same then
      direction := 'same';
    elsif ups::double precision / diffs <= p.direction_reversed then
      direction := 'reversed';
    end if;
  end if;

  -- Fréchet nur, wo es die Entscheidung ändern kann: bei beidseitiger
  -- Deckung. Schrittweite so, dass je Linie höchstens frechet_max_points
  -- bleiben (Kappe, siehe frechet()).
  if cov_ab >= p.coverage_same and cov_ba >= p.coverage_same then
    fstep := greatest(p.step_m, greatest(st_length(a), st_length(b)) / p.frechet_max_points);
    select array_agg(s order by o) into fa
      from unnest(app_internal.resample(a, fstep)) with ordinality t(s, o)
     where st_dwithin(s, b, p.corridor_m);
    select array_agg(s order by case when direction = 'reversed' then -o else o end) into fb
      from unnest(app_internal.resample(b, fstep)) with ordinality t(s, o)
     where st_dwithin(s, a, p.corridor_m);
    fr := app_internal.frechet(fa, fb);
  end if;

  -- Einordnung — Spiegel von PairResult.classify().
  if cov_ab >= p.coverage_same and cov_ba >= p.coverage_same then
    if fr is not null and fr > p.frechet_factor * p.corridor_m then
      cls := 'neighbour';        -- deckt sich, aber die Reihenfolge folgt nicht
    elsif direction = 'reversed' then
      cls := 'same-reversed';
    else
      cls := 'same';
    end if;
  elsif cov_ab >= p.coverage_same then
    cls := 'a-in-b';
  elsif cov_ba >= p.coverage_same then
    cls := 'b-in-a';
  elsif greatest(cov_ab, cov_ba) >= p.overlap_min then
    cls := 'fork';
  else
    cls := 'different';
  end if;

  return row(cov_ab::real, cov_ba::real, direction,
             case when fr is null or fr = 'infinity'::double precision then null else fr::real end,
             cls)::app_internal.match_result;
end $$;

-- Nur der Definer-RPC ruft die Matcher-Funktionen; er läuft als
-- Eigentümer. Die API sieht app_internal ohnehin nicht — der Entzug ist
-- Gürtel zum Hosenträger.
revoke all on function app_internal.match_params() from public, anon, authenticated;
revoke all on function app_internal.utm_srid(geometry) from public, anon, authenticated;
revoke all on function app_internal.resample(geometry, double precision) from public, anon, authenticated;
revoke all on function app_internal.frechet(geometry[], geometry[]) from public, anon, authenticated;
revoke all on function app_internal.match_lines(geometry, geometry) from public, anon, authenticated;

-- Trails ohne jeden Beitrag verschwinden (Abschnitt 3, „Löschen und
-- DSGVO": kein Cascade vom Beitrag zur Kennung, sondern ein Aufräumjob).
-- Overlap-Kanten fallen per Cascade mit. Eingeplant unten per pg_cron,
-- wo es das gibt.
create or replace function app_internal.sweep_orphan_trails()
returns integer
language plpgsql security definer set search_path = public as $$
declare
  n integer;
begin
  delete from trails t
   where not exists (select 1 from trail_recordings r where r.trail_id = t.id)
     and not exists (select 1 from trail_details d where d.trail_id = t.id);
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function app_internal.sweep_orphan_trails() from public, anon, authenticated;

-- updated_at am Beitrag pflegt die Datenbank, nicht der Client.
create or replace function app_internal.touch_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end $$;
revoke all on function app_internal.touch_updated_at() from public, anon, authenticated;
create trigger trail_details_touch
  before update on public.trail_details
  for each row execute function app_internal.touch_updated_at();

-- Aliase: Ende der Freundschaft löscht sie beider Seiten (PilzBuddy
-- Patch 032; Definer, weil die delete-Policy jedem nur die EIGENEN gibt).
create or replace function app_internal.aliases_on_unfriend()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  delete from friend_aliases a
  where (a.owner_id = old.requester_id and a.friend_id = old.addressee_id)
     or (a.owner_id = old.addressee_id and a.friend_id = old.requester_id);
  return old;
end;
$$;
revoke all on function app_internal.aliases_on_unfriend() from public, anon, authenticated;
create trigger friendships_delete_aliases
  after delete on public.friendships
  for each row execute function app_internal.aliases_on_unfriend();

-- ============================================================
-- RPCs in public (API-Endpunkte)
-- ============================================================

-- Der EINE Schreibweg für Aufzeichnungen (Abschnitt 4.1). Der Client kann
-- nicht gegen fremde Trails vergleichen, weil er sie nicht sehen darf —
-- also tut es die Datenbank, als Definer. Zurück kommt NUR die
-- Trail-Kennung; ob sie neu ist, sagt die Funktion nicht (4.6).
--
-- coords: flache Liste [lon1, lat1, lon2, lat2, …] in WGS84 — die
-- einfachste Form, die sich aus Dart als JSON-Array übergeben lässt.
--
-- Ablauf:
--   1. Angemeldet? Quelle bekannt? Mindestens zwei Punkte? Länge ≥ 150 m?
--      Tageslimit (4.6)? Sonst Ausnahme mit klarem Text.
--   2. Idempotenz: (user_id, client_id) schon da ⇒ dessen trail_id.
--   3. Vorfilter (GiST): Trails, deren Aufzeichnungen dem Kandidaten
--      näher als der Korridor kommen. Je Trail EINE Vertreterin — die
--      Aufzeichnung mit der höchsten Qualität (4.5: keine gemittelte
--      Linie).
--   4. match_lines je Vertreterin. Nur „gleich" hängt an (4.4, v1
--      bewusst konservativ) — bei mehreren Treffern der mit der höchsten
--      beidseitigen Deckung. „gleich-gegen" heißt reversed, RELATIV zur
--      Vertreterin: War die selbst gegen die Trail-Richtung unterwegs,
--      dreht sich das Vorzeichen (XOR).
--   5. Sonst neuer Trail, und je Nachbar mit Deckung ≥ 0,3 in einer
--      Richtung eine Kante in trail_overlaps (Teil, Enthält, Gabel,
--      Nachbar).
--   6. Aufzeichnung schreiben. Qualität vorerst nur aus der Quelle
--      (0,6 app / 0,4 import / 0,1 planned): Genauigkeit je Punkt und
--      Lückenprüfung (4.5) kommen, sobald der Client sie mitschickt —
--      dann als weiterer Parameter, nicht als andere Zahl hier.
--   7. Beitrag des Aufrufers anlegen, falls er fehlt; sonst seinen
--      Status auf „offen" setzen — wer den Trail fährt, hat ihn
--      befahrbar vorgefunden (Abschnitt 3, Entscheidung 6).
create or replace function public.contribute_recording(
  coords double precision[],
  source text,
  recorded_at timestamptz default null,
  client_id uuid default null)
returns uuid
language plpgsql security definer set search_path = public, extensions as $$
declare
  p app_internal.match_params := app_internal.match_params();
  uid uuid := auth.uid();
  npts integer;
  line geometry;
  geog geography;
  len double precision;
  srid integer;
  cand geometry;
  existing uuid;
  best_trail uuid;
  best_cov double precision := -1;
  best_reversed boolean := false;
  rec record;
  res app_internal.match_result;
  ov_trails uuid[] := '{}';
  ov_ab real[] := '{}';
  ov_ba real[] := '{}';
  target uuid;
  q real;
begin
  if uid is null then
    raise exception 'Nicht angemeldet' using errcode = '28000';
  end if;
  if source is null or source not in ('app', 'import', 'planned') then
    raise exception 'Unbekannte Quelle: %', coalesce(source, 'null')
      using errcode = '22023', hint = 'app, import oder planned';
  end if;
  npts := coalesce(array_length(coords, 1), 0);
  if npts < 4 or npts % 2 <> 0 then
    raise exception 'Mindestens zwei Punkte als [lon, lat, lon, lat, …] erwartet'
      using errcode = '22023';
  end if;
  if exists (select 1 from generate_series(1, npts / 2) i
              where coords[2 * i - 1] not between -180 and 180
                 or coords[2 * i] not between -90 and 90) then
    raise exception 'Koordinate außerhalb von WGS84 (lon ±180, lat ±90)'
      using errcode = '22023';
  end if;

  -- 2. Idempotenz (Ausgangskorb): derselbe Auftrag noch einmal ⇒ dieselbe
  -- Antwort, keine zweite Aufzeichnung.
  if contribute_recording.client_id is not null then
    select r.trail_id into existing
      from trail_recordings r
     where r.user_id = uid and r.client_id = contribute_recording.client_id;
    if found then
      return existing;
    end if;
  end if;

  -- Rate (4.6): reicht jedem echten Nutzer, auch für einen Bestandsimport
  -- an einem Abend, und macht das Sondieren als Fläche unattraktiv.
  if (select count(*) from trail_recordings r
       where r.user_id = uid and r.created_at > now() - interval '1 day') >= p.daily_limit then
    raise exception 'Tageslimit von % Aufzeichnungen erreicht', p.daily_limit
      using errcode = '54000';
  end if;

  select st_removerepeatedpoints(
           st_setsrid(st_makeline(array_agg(st_makepoint(coords[2 * i - 1], coords[2 * i]) order by i)), 4326))
    into line
    from generate_series(1, npts / 2) i;
  if st_npoints(line) < 2 then
    raise exception 'Mindestens zwei verschiedene Punkte erwartet' using errcode = '22023';
  end if;
  geog := line::geography;
  len := st_length(geog);
  if len < p.min_trail_m then
    raise exception 'Aufzeichnung zu kurz: % m, ein Trail hat mindestens % m',
      round(len), p.min_trail_m::integer using errcode = '22023';
  end if;

  -- 3./4. Abgleich gegen die Vertreterinnen aller Trails in Reichweite.
  srid := app_internal.utm_srid(line);
  cand := st_transform(line, srid);
  for rec in
    with near as (
      select distinct r.trail_id
        from trail_recordings r
       where st_dwithin(r.geom, geog, p.corridor_m)
    )
    select n.trail_id, b.geom, b.reversed
      from near n
      cross join lateral (
        select r.geom, r.reversed
          from trail_recordings r
         where r.trail_id = n.trail_id
         order by r.quality desc, r.created_at asc
         limit 1) b
  loop
    res := app_internal.match_lines(cand, st_transform(rec.geom::geometry, srid));
    if res.class in ('same', 'same-reversed') then
      if least(res.cov_ab, res.cov_ba) > best_cov then
        best_trail := rec.trail_id;
        best_cov := least(res.cov_ab, res.cov_ba);
        best_reversed := (res.class = 'same-reversed') <> rec.reversed;
      end if;
    elsif greatest(res.cov_ab, res.cov_ba) >= p.overlap_min then
      ov_trails := ov_trails || rec.trail_id;
      ov_ab := ov_ab || res.cov_ab;
      ov_ba := ov_ba || res.cov_ba;
    end if;
  end loop;

  -- 5. Anhängen oder neu — nur „gleich" verschmilzt.
  if best_trail is not null then
    target := best_trail;
  else
    insert into trails default values returning id into target;
    insert into app_internal.trail_overlaps (a, b, coverage_ab, coverage_ba)
      select target, t, ab, ba
        from unnest(ov_trails, ov_ab, ov_ba) as u(t, ab, ba);
  end if;

  -- 6. Die Aufzeichnung.
  q := case source when 'app' then 0.6 when 'import' then 0.4 else 0.1 end;
  begin
    insert into trail_recordings
      (trail_id, user_id, geom, recorded_at, source, reversed, quality, client_id)
    values
      (target, uid, geog, recorded_at, source, best_reversed, q, contribute_recording.client_id);
  exception when unique_violation then
    -- Wettlauf zweier Wiedervorlagen desselben Auftrags: Die erste hat
    -- gewonnen, ihre Antwort gilt. Ein eben angelegter leerer Trail geht
    -- wieder weg.
    if best_trail is null then
      delete from trails where id = target;
    end if;
    select r.trail_id into existing
      from trail_recordings r
     where r.user_id = uid and r.client_id = contribute_recording.client_id;
    return existing;
  end;

  -- 7. Der Beitrag.
  insert into trail_details (trail_id, user_id)
  values (target, uid)
  on conflict (trail_id, user_id) do update
    set status = 'open', status_at = now()
    where trail_details.status <> 'open';

  return target;
end $$;

-- Nur für Angemeldete. anon hätte die Funktion sonst über
-- /rest/v1/rpc/contribute_recording (Default-Grant an PUBLIC).
revoke all on function public.contribute_recording(double precision[], text, timestamptz, uuid)
  from public, anon;
grant execute on function public.contribute_recording(double precision[], text, timestamptz, uuid)
  to authenticated;

-- Buddy-Suche: exakte E-Mail oder Username-Präfix; gibt nie E-Mails zurück.
create or replace function public.search_profiles(query text)
returns table (id uuid, username text, display_name text, avatar int)
language sql stable security definer set search_path = public as $$
  select p.id, p.username, p.display_name, p.avatar
  from profiles p
  left join auth.users u on u.id = p.id
  where p.id <> auth.uid()
    and (lower(u.email) = lower(query) or p.username ilike query || '%')
  limit 10;
$$;
-- Nur für Angemeldete: für anon wäre der exakte E-Mail-Vergleich ein
-- E-Mail-Orakel (verrät ohne Konto, ob eine Adresse registriert ist).
revoke all on function public.search_profiles(text) from public, anon;
grant execute on function public.search_profiles(text) to authenticated;

-- Konto-Löschung durch den Nutzer selbst (Play-Anforderung). Alle Tabellen
-- hängen per `on delete cascade` an profiles und profiles an auth.users —
-- das Löschen des Auth-Users räumt daher alles mit ab. Trails ohne
-- verbleibenden Beitrag holt sweep_orphan_trails.
-- Kein Parameter: auth.uid() kommt aus dem JWT, eine übergebene id wäre eine
-- Einladung, fremde Konten zu löschen.
create or replace function public.delete_own_account()
returns void
language plpgsql security definer set search_path = public, auth as $$
begin
  if auth.uid() is null then
    raise exception 'Nicht angemeldet' using errcode = '28000';
  end if;
  delete from auth.users where id = auth.uid();
end;
$$;
revoke all on function public.delete_own_account() from public, anon;
grant execute on function public.delete_own_account() to authenticated;

-- ============================================================
-- Sicht für den Client: Aufzeichnungen als GeoJSON
-- ============================================================
-- PostgREST gäbe die geography als WKB-Hex zurück; die App will GeoJSON
-- und die Länge. `security_invoker`: Die RLS der Tabelle gilt weiter, die
-- Sicht öffnet nichts. Was auf der Karte steht, rechnet der Client aus
-- dieser Liste (beste sichtbare Aufzeichnung je trail_id, Abschnitt 3).
create view public.recordings_visible
with (security_invoker = true) as
  select id, trail_id, user_id, source, recorded_at, reversed, quality, created_at,
         st_asgeojson(geom::geometry) as geojson,
         st_length(geom) as length_m
    from public.trail_recordings;

-- ============================================================
-- Row Level Security
-- ============================================================

alter table public.profiles          enable row level security;
alter table public.friendships       enable row level security;
alter table public.friend_aliases    enable row level security;
alter table public.feedback          enable row level security;
alter table public.error_reports     enable row level security;
alter table public.app_config        enable row level security;
alter table public.trails            enable row level security;
alter table public.trail_recordings  enable row level security;
alter table public.trail_details     enable row level security;
alter table app_internal.trail_overlaps enable row level security;

-- Ausdrücklich gesperrt (PilzBuddy Patch 037): RLS ohne Policy verweigert
-- ohnehin alles, aber der Security Advisor meldet es dauerhaft, und
-- dismissen lässt es sich im Dashboard nicht. Benutzt wird beides nur vom
-- Eigentümer (Definer-RPC, Aufräumjob), der RLS umgeht.
create policy trails_no_client on public.trails
  for all to anon, authenticated using (false) with check (false);
create policy trail_overlaps_no_client on app_internal.trail_overlaps
  for all to anon, authenticated using (false) with check (false);

-- profiles: ich selbst + alle, mit denen eine (auch offene) Freundschaft
-- besteht (Suche läuft über search_profiles)
create policy profiles_select on public.profiles for select
  using (id = auth.uid() or app_internal.involved_in_friendship(id, auth.uid()));
create policy profiles_update on public.profiles for update
  using (id = auth.uid()) with check (id = auth.uid());

-- friendships
create policy fr_select on public.friendships for select
  using (requester_id = auth.uid() or addressee_id = auth.uid());
create policy fr_insert on public.friendships for insert
  with check (requester_id = auth.uid() and status = 'pending');
create policy fr_accept on public.friendships for update
  using (addressee_id = auth.uid() and status = 'pending')
  with check (status = 'accepted');
create policy fr_delete on public.friendships for delete   -- ablehnen / zurückziehen / entfreunden
  using (requester_id = auth.uid() or addressee_id = auth.uid());

-- friend_aliases: alles nur für den Besitzer; anlegen und ändern nur für
-- bestätigte Buddys.
create policy fa_select on public.friend_aliases for select
  using (owner_id = auth.uid());
create policy fa_insert on public.friend_aliases for insert
  with check (owner_id = auth.uid()
    and app_internal.are_friends(owner_id, friend_id));
create policy fa_update on public.friend_aliases for update
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid()
    and app_internal.are_friends(owner_id, friend_id));
create policy fa_delete on public.friend_aliases for delete
  using (owner_id = auth.uid());

-- feedback: eigene Wünsche einreichen und nachlesen
create policy feedback_insert on public.feedback for insert
  with check (user_id = auth.uid());
create policy feedback_select_own on public.feedback for select
  using (user_id = auth.uid());

-- error_reports: schreiben darf jeder, auch anon — sonst fehlen genau die
-- Fehler aus Login und Registrierung. Eine fremde user_id lässt sich nicht
-- unterschieben. LESEN darf niemand über die API: es gibt bewusst keine
-- select-Policy, die Auswertung läuft über das Dashboard.
create policy er_insert on public.error_reports for insert
  with check (user_id is null or user_id = auth.uid());

-- app_config: lesen darf jeder, auch anon — die Mindestversion wird beim
-- Start und damit vor der Anmeldung geprüft. Geändert wird der Wert über
-- einen Patch, deshalb kein insert/update/delete-Grant.
create policy app_config_read on public.app_config for select using (true);

-- trail_recordings — DIE Sichtbarkeitsregel (Abschnitt 3), formal:
-- „U sieht T, wenn es eine Aufzeichnung zu T von U gibt, oder eine von
-- einem Buddy B, dessen Beitrag zu T die Sichtbarkeit `buddies` hat."
-- Kein insert und kein update über die API: Schreiben geht nur durch
-- contribute_recording, denn nur dort läuft der Abgleich. Löschen darf
-- man die eigenen (Abschnitt 3, „Löschen und DSGVO").
create policy recordings_select on public.trail_recordings for select
  using (user_id = auth.uid()
     or (app_internal.are_friends(user_id, auth.uid())
         and app_internal.contributor_shares(user_id, trail_id)));
create policy recordings_delete_own on public.trail_recordings for delete
  using (user_id = auth.uid());

-- trail_details: der eigene Beitrag ganz; fremde nur von Buddys und nur,
-- wenn sie ihn teilen. `visibility = 'private'` nimmt damit BEIDES aus
-- der Sicht des Buddys: die Aufzeichnungen (über contributor_shares) und
-- den Beitrag selbst.
create policy td_owner_all on public.trail_details for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy td_friend_select on public.trail_details for select
  using (user_id <> auth.uid()
     and visibility = 'buddies'
     and app_internal.are_friends(user_id, auth.uid()));

-- ============================================================
-- Grants — ausdrücklich, nicht über auto_expose
-- ============================================================
-- Die Legacy-Vorgabe `auto_expose_new_tables` (config.toml, fällt am
-- 2026-10-30) gäbe anon und authenticated auf jeder Tabelle alle Rechte.
-- Deshalb ERST alles weg, dann gezielt zurück. anon bekommt genau zwei
-- Dinge: app_config lesen und error_reports schreiben — beides läuft vor
-- der Anmeldung. Alles andere ist für Angemeldete, und `trails` sowie
-- app_internal.* für niemanden (4.6: ein Wächter-Test in
-- tool/schema_check.sh prüft das über die API).
revoke all on all tables in schema public from anon, authenticated;
revoke all on all tables in schema app_internal from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;

grant select, update on public.profiles to authenticated;
grant select, insert, update, delete on public.friendships to authenticated;
grant select, insert, update, delete on public.friend_aliases to authenticated;
grant select on public.app_config to anon, authenticated;
grant insert on public.error_reports to anon, authenticated;
grant insert, select on public.feedback to authenticated;
grant select, delete on public.trail_recordings to authenticated;   -- insert nur per RPC
grant select, insert, update, delete on public.trail_details to authenticated;
grant select on public.recordings_visible to authenticated;
-- KEIN Grant auf public.trails, KEINER auf app_internal.trail_overlaps.

-- Der Feedback-Bot (tool/feedback_bot.py, patch_001) arbeitet mit dem
-- Service-Schlüssel: Feedback lesen und abstempeln, Fehlerberichte nach
-- 90 Tagen löschen. service_role umgeht RLS, aber NICHT fehlende Grants —
-- und ein Projekt ohne automatische Tabellenfreigabe gibt ihm keine von
-- selbst. Ausdrücklich, damit der Bot nicht an einer Vorgabe hängt.
grant select, update on public.feedback to service_role;
grant select, delete on public.error_reports to service_role;

-- ============================================================
-- Aufräumjob (nur wo pg_cron verfügbar ist)
-- ============================================================
-- Supabase hat pg_cron; der nackte Postgres des Matcher-Tests nicht. Ein
-- hartes `create extension pg_cron` bräche dort die Frischinstallation,
-- die diese Datei beweisen soll — deshalb der Umweg über
-- pg_available_extensions und dynamisches SQL (die Referenz auf
-- cron.schedule wird nur aufgelöst, wenn es das Schema gibt).
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    execute $cron$select cron.schedule('trails-sweep', '23 3 * * *',
              'select app_internal.sweep_orphan_trails()')$cron$;
  else
    raise notice 'pg_cron nicht verfügbar — sweep_orphan_trails() ist nicht eingeplant (lokaler Testlauf).';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Patch-Buchführung
-- ---------------------------------------------------------------------------
-- Dieselbe Tabelle legt auch tool/db_migrate.sh an (`if not exists`) — sie
-- muss dort stehen, weil die Live-Datenbank diese Datei nie im Ganzen sieht.
create table if not exists public.applied_patches (
  filename text primary key,
  applied_at timestamptz not null default now()
);
alter table public.applied_patches enable row level security;
revoke all on table public.applied_patches from anon, authenticated;
-- Sperr-Policy (PilzBuddy Patch 037, Grund siehe trails oben).
create policy applied_patches_no_client on public.applied_patches
  for all to anon, authenticated using (false) with check (false);

-- Saat-Liste. Diese Datei bildet den Stand NACH allen Patches ab, die
-- hier stehen; sie werden bei einer Frischinstallation nur EINGETRAGEN,
-- nicht ausgeführt. Grund (PilzBuddy-Lehre): Ein erneuter Lauf über ein
-- Schema, das ihr Ergebnis schon enthält, verlangte von jedem alten Patch
-- auf Dauer Idempotenz und zwang dazu, alte Patches nachträglich zu
-- ändern — live läuft ein eingespielter Patch aber nie wieder, die
-- Änderung landete also nur in Frischinstallationen, und beide Welten
-- drifteten still auseinander.
--
-- Regel: Ein neuer supabase/patch_NNN_*.sql gehört im selben PR (1) als
-- Datei, (2) in die Struktur oben und (3) HIER in die Liste.
-- tool/patch_guard.sh vergleicht Liste und Dateien und lässt keinen
-- Unterschied durch.
insert into public.applied_patches (filename) values
  ('patch_001_feedback_bot_grants.sql')
on conflict do nothing;
