#!/usr/bin/env python3
"""Feedback bot for TrailBuddy (adapted from PilzBuddy's tool/feedback_bot.py).

Reads unprocessed rows from the Supabase `feedback` table, creates one
public GitHub issue per row (label `enhancement` or `bug`) and stamps the
row with processed_at. On the same tick it deletes `error_reports` older
than 90 days — the privacy policy promises that, so something has to do it.

Differences to PilzBuddy, both on purpose:
- No username in the issue. The issue is public; who wrote it stays in
  the database (user_id), where only the operator reads it.
- No species PRs, no photos, no weekly error digest (yet).

@-mentions in the text are defused: a public issue must not ping people
because someone typed their handle into the app.

Required environment: SUPABASE_SERVICE_ROLE_KEY, GH_TOKEN (the workflow
provides both). The project URL comes from lib/core/supabase_config.dart,
the same file the app and tool/schema_check.sh read, so it cannot drift.

Self-test without any network access:
    python3 tool/feedback_bot.py --self-test
"""
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone

CONFIG = "lib/core/supabase_config.dart"
ERROR_REPORT_RETENTION_DAYS = 90
TITLE_CHARS = 60


def supabase_url() -> str:
    with open(CONFIG, encoding="utf-8") as f:
        m = re.search(r"'SUPABASE_URL',\s*defaultValue:\s*'([^']+)'", f.read())
    if not m or not m.group(1).startswith("https://"):
        raise SystemExit(f"No live https URL in {CONFIG}")
    return m.group(1)


def api(method: str, path: str, body=None):
    key = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
    headers = {"apikey": key, "Content-Type": "application/json"}
    # Legacy service_role keys are JWTs and also go into Authorization;
    # the new sb_secret_* keys must only use apikey.
    if key.startswith("eyJ"):
        headers["Authorization"] = f"Bearer {key}"
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(supabase_url() + path, data=data,
                                     headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            text = response.read().decode()
            return json.loads(text) if text else None
    except urllib.error.HTTPError as e:
        # PostgREST sagt im Rumpf, WAS nicht stimmt ("invalid input syntax
        # for type timestamp …") — ohne ihn stand im Log nur „400". Der
        # Rumpf enthält keine Daten, nur die Fehlermeldung.
        raise SystemExit(f"{method} {path.split('?')[0]} → HTTP {e.code}: "
                         f"{e.read().decode(errors='replace')[:500]}") from None


def run(*cmd: str) -> str:
    return subprocess.run(cmd, check=True, capture_output=True,
                          text=True).stdout.strip()


def defuse(text: str) -> str:
    """No pings from a public issue: `@name` → `@​name`."""
    return re.sub(r"@(?=[A-Za-z0-9])", "@​", text)


def issue_title(row: dict) -> str:
    prefix = "Bug report: " if row["type"] == "bug" else "Feature request: "
    text = " ".join(defuse(row["message"]).split())
    return prefix + text[:TITLE_CHARS] + ("…" if len(text) > TITLE_CHARS else "")


def issue_body(row: dict) -> str:
    """Quoted text, version and date — and nothing about the person."""
    quoted = "\n".join("> " + line if line.strip() else ">"
                       for line in defuse(row["message"].strip()).splitlines())
    version = row.get("app_version")
    aus = f" aus Version {version}" if version else ""
    return (
        f"{quoted}\n\n"
        f"Eingereicht in der App{aus} am {row['created_at'][:10]}.\n\n"
        f"_Automatisch erstellt vom Feedback-Bot._"
    )


def issue_label(row: dict) -> str:
    return "bug" if row["type"] == "bug" else "enhancement"


def issue_exists(title: str) -> bool:
    out = run("gh", "issue", "list", "--state", "all", "--limit", "100",
              "--search", title, "--json", "title")
    return any(item["title"] == title for item in json.loads(out or "[]"))


def ensure_labels() -> None:
    # New repositories usually have both; a missing label would fail every
    # `gh issue create` below, so make sure instead of assuming.
    for name, color in (("bug", "d73a4a"), ("enhancement", "a2eeef")):
        subprocess.run(["gh", "label", "create", name, "--color", color, "--force"],
                       check=False, capture_output=True)


def retention_cutoff(now: datetime) -> str:
    # UTC mit „Z", nicht isoformat(): dessen „+00:00" steht sonst roh in
    # der Adresse, und ein „+" in einer Query heißt Leerzeichen — PostgREST
    # bekam ein ungültiges Datum und antwortete 400 (erster Live-Lauf).
    cutoff = now.astimezone(timezone.utc) - timedelta(days=ERROR_REPORT_RETENTION_DAYS)
    return cutoff.strftime("%Y-%m-%dT%H:%M:%SZ")


def purge_path(cutoff: str) -> str:
    return "/rest/v1/error_reports?created_at=lt." + urllib.parse.quote(cutoff, safe="")


def purge_error_reports() -> None:
    api("DELETE", purge_path(retention_cutoff(datetime.now(timezone.utc))))
    print(f"error_reports older than {ERROR_REPORT_RETENTION_DAYS} days deleted.")


def main() -> None:
    # Before the early return below — otherwise the purge would only run
    # on the rare tick that also has unprocessed feedback.
    purge_error_reports()

    rows = api("GET", "/rest/v1/feedback?processed_at=is.null&order=created_at"
                      "&select=id,type,message,created_at,app_version")
    if not rows:
        print("No unprocessed feedback.")
        return
    ensure_labels()
    for row in rows:
        title = issue_title(row)
        if issue_exists(title):
            print(f"Skip (issue already exists): {title}")
        else:
            run("gh", "issue", "create", "--title", title,
                "--body", issue_body(row), "--label", issue_label(row))
            print(f"Issue created [{issue_label(row)}]: {title}")
        # Stamp each row right away so a later crash never duplicates it.
        now = datetime.now(timezone.utc).isoformat()
        api("PATCH", f"/rest/v1/feedback?id=eq.{row['id']}", {"processed_at": now})
    print("Done.")


def self_test() -> None:
    row = {"id": "x", "type": "feature", "created_at": "2026-09-27T18:00:00Z",
           "app_version": "0.2.0",
           "message": "Offline-Karten wären toll, frag mal @someone\n\nDanke!"}
    title = issue_title(row)
    assert title == "Feature request: Offline-Karten wären toll, frag mal @​someone Danke!", title
    body = issue_body(row)
    assert body.startswith("> Offline-Karten wären toll, frag mal @​someone\n>\n> Danke!"), body
    assert "aus Version 0.2.0 am 2026-09-27" in body, body
    assert "user" not in body.lower() and "von **" not in body, "no person in a public issue"
    assert issue_label(row) == "enhancement"

    bug = dict(row, type="bug", app_version=None, message="x" * 100)
    assert issue_title(bug) == "Bug report: " + "x" * 60 + "…"
    assert issue_label(bug) == "bug"
    assert "aus Version" not in issue_body(bug), "no invented version"

    cutoff = retention_cutoff(datetime(2026, 9, 27, 18, 0, tzinfo=timezone.utc))
    assert cutoff == "2026-06-29T18:00:00Z", cutoff
    # Kein rohes „+" in der Adresse — das war der 400 im ersten Live-Lauf.
    path = purge_path(cutoff)
    assert "+" not in path and path.endswith("lt.2026-06-29T18%3A00%3A00Z"), path

    assert supabase_url().startswith("https://") and supabase_url().endswith(".supabase.co")
    print("feedback_bot self-test: ok")


if __name__ == "__main__":
    if sys.argv[1:] == ["--self-test"]:
        self_test()
    elif not sys.argv[1:]:
        main()
    else:
        raise SystemExit(__doc__)
