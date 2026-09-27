#!/usr/bin/env python3
"""Measure how many metres up and down a trail really has (issue #14).

GPS and barometric altitudes are noisy: summing every step of a downhill
trail yields tens of metres "uphill" that nobody pedalled. The app counts
a change only once it exceeds a threshold (hysteresis). This tool
measures WHICH threshold, against the operator's own recordings, before
the number is cast into lib/features/trails/trail_elevation.dart --
the same rule as for the matcher: measured, not guessed.

It also measures what the thinning before upload costs: the app keeps a
point when it lies more than 3 m off the line horizontally OR more than
VTOL metres off vertically (3D Douglas-Peucker). Without the vertical
part, a straight but bumpy stretch would lose its bumps.

Input is the same zip or directory as tool/trail_match.py (TRAIL_GPX),
which is NEVER part of the repository. The report contains counts and
metres only -- no names, no coordinates.

    python3 tool/elevation_measure.py --self-test
    TRAIL_GPX=~/somewhere/Trails.zip python3 tool/elevation_measure.py --report out.md

The two functions `gain_loss` and `simplify_3d` are mirrored in Dart
(`elevationGainLoss`, `simplify`); the self-test vectors are the same as
in test/trails/trail_elevation_test.dart. Change both in the same PR.
"""
from __future__ import annotations

import argparse
import math
import os
import statistics
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from trail_match import MIN_TRAIL_M, Track, load_tracks, project  # noqa: E402

TRAIL_MAX_M = 8000.0            # lib/features/trails/trail_geometry.dart
HTOL_M = 3.0                    # horizontal tolerance of `simplify`
THRESHOLDS = (0.0, 1.0, 2.0, 3.0, 5.0, 8.0, 10.0)
VTOLS = (None, 1.0, 2.0, 3.0, 5.0)
WINDOWS = (50.0, 100.0)


# ------------------------------------------------------------------ rules

def gain_loss(ele: list[float], threshold: float) -> tuple[float, float]:
    """Metres up and down, counting a change only once it exceeds
    `threshold` from the last counted level (hysteresis).

    The rest at the end is booked too, so loss - gain is always exactly
    ele[0] - ele[-1]: the net drop of a trail never depends on the
    threshold, only the noise around it does.
    """
    if len(ele) < 2:
        return 0.0, 0.0
    ref = ele[0]
    gain = loss = 0.0
    for e in ele[1:]:
        d = e - ref
        if d >= threshold and d > 0:
            gain += d
            ref = e
        elif -d >= threshold and d < 0:
            loss -= d
            ref = e
    d = ele[-1] - ref
    if d > 0:
        gain += d
    else:
        loss -= d
    return gain, loss


def simplify_3d(xy: list[tuple[float, float]], ele: list[float] | None,
                htol: float = HTOL_M, vtol: float | None = None) -> list[int]:
    """Douglas-Peucker on metres; returns the indices kept. With `vtol`,
    a point also stays when its altitude is more than vtol off the linear
    interpolation along the chord -- the same parameter t as the
    horizontal projection, exactly like the Dart version."""
    n = len(xy)
    if n <= 2:
        return list(range(n))
    keep = [False] * n
    keep[0] = keep[-1] = True
    stack = [(0, n - 1)]
    while stack:
        a, b = stack.pop()
        if b - a < 2:
            continue
        ax, ay = xy[a]
        bx, by = xy[b]
        dx, dy = bx - ax, by - ay
        l2 = dx * dx + dy * dy
        worst, worst_i = -1.0, -1
        for i in range(a + 1, b):
            px, py = xy[i]
            if l2 == 0:
                t = 0.0
                d = math.hypot(px - ax, py - ay)
            else:
                t = min(1.0, max(0.0, ((px - ax) * dx + (py - ay) * dy) / l2))
                d = math.hypot(px - (ax + t * dx), py - (ay + t * dy))
            score = d / htol
            if vtol is not None and ele is not None:
                dv = abs(ele[i] - (ele[a] + t * (ele[b] - ele[a])))
                score = max(score, dv / vtol)
            if score > worst:
                worst, worst_i = score, i
        if worst > 1.0:
            keep[worst_i] = True
            stack.append((a, worst_i))
            stack.append((worst_i, b))
    return [i for i in range(n) if keep[i]]


def cumulative(xy: list[tuple[float, float]]) -> list[float]:
    out = [0.0]
    for (x1, y1), (x2, y2) in zip(xy, xy[1:]):
        out.append(out[-1] + math.hypot(x2 - x1, y2 - y1))
    return out


def steepest(dist: list[float], ele: list[float], window: float) -> float | None:
    """Steepest descent in percent over at least `window` metres."""
    best = None
    j = 0
    for i in range(len(dist)):
        if j < i:
            j = i
        while j < len(dist) and dist[j] - dist[i] < window:
            j += 1
        if j >= len(dist):
            break
        g = (ele[i] - ele[j]) / (dist[j] - dist[i]) * 100
        best = g if best is None else max(best, g)
    return best


# ---------------------------------------------------------------- measure

def q(values: list[float], p: float) -> float:
    if not values:
        return float("nan")
    s = sorted(values)
    return s[min(len(s) - 1, int(p * len(s)))]


def has_ele(tr: Track) -> bool:
    return all(e is not None for e in tr.ele)


def classify(tr: Track) -> str:
    if tr.length_m < MIN_TRAIL_M:
        return "fragment"
    if tr.length_m >= TRAIL_MAX_M:
        return "ride"
    if not has_ele(tr):
        return "trail"
    raw_gain, raw_loss = gain_loss(tr.ele, 0.0)
    return "trail" if raw_loss > 2 * raw_gain else "ride"


def run(tracks: list[Track], report_path: str | None) -> str:
    lines: list[str] = []
    out = lines.append
    with_ele = [t for t in tracks if has_ele(t)]
    trails = [t for t in with_ele if classify(t) == "trail"]
    rides = [t for t in with_ele if classify(t) == "ride"]
    out("# Höhenmeter: Messung an echten Aufzeichnungen\n")
    out(f"- Dateien: {len(tracks)}, davon mit Höhe an JEDEM Punkt: {len(with_ele)} "
        f"({100 * len(with_ele) / max(1, len(tracks)):.0f} %)")
    out(f"- darunter Trails (< 8 km, bergab): {len(trails)}, Fahrten: {len(rides)}")
    steps = [abs(t.ele[i + 1] - t.ele[i]) for t in with_ele for i in range(len(t.ele) - 1)]
    integral = sum(1 for t in with_ele for e in t.ele if float(e).is_integer())
    total = sum(len(t.ele) for t in with_ele)
    out(f"- Höhenschritt Punkt zu Punkt: Median {q(steps, 0.5):.2f} m, p90 {q(steps, 0.9):.2f} m; "
        f"ganzzahlige Werte {100 * integral / max(1, total):.0f} %\n")

    out("## Schwelle (Hysterese) — Trails\n")
    out("Auf einem Trail, der bergab läuft, ist fast jeder Meter „bergauf“ Rauschen. "
        "Gesucht ist die Schwelle, ab der der Anstieg nicht mehr fällt, der Abstieg "
        "aber noch nicht zusammenschrumpft (Abstieg − Anstieg ist bei jeder Schwelle gleich).\n")
    out("| Schwelle | Anstieg Median | Anstieg p90 | Abstieg Median | Abstieg / Nettogefälle |")
    out("|---:|---:|---:|---:|---:|")
    for h in THRESHOLDS:
        gl = [gain_loss(t.ele, h) for t in trails]
        # 1,0 hieße: kein Meter Abstieg mehr als der Höhenunterschied von
        # Start und Ziel — auf einem reinen Downhill die Wahrheit.
        ratio = [g[1] / (t.ele[0] - t.ele[-1]) for g, t in zip(gl, trails) if t.ele[0] - t.ele[-1] > 20]
        out(f"| {h:g} m | {q([g[0] for g in gl], 0.5):.0f} m | {q([g[0] for g in gl], 0.9):.0f} m "
            f"| {q([g[1] for g in gl], 0.5):.0f} m | {q(ratio, 0.5):.2f} |")

    out("\n## Schwelle — Fahrten (Gegenprobe)\n")
    out("Eine Fahrt hat echten Anstieg; eine zu hohe Schwelle frisst ihn.\n")
    out("| Schwelle | Anstieg Median | Anstieg / roh |")
    out("|---:|---:|---:|")
    raw_r = {t.tid: gain_loss(t.ele, 0.0) for t in rides}
    for h in THRESHOLDS:
        gl = [gain_loss(t.ele, h) for t in rides]
        ratio = [g[0] / raw_r[t.tid][0] for g, t in zip(gl, rides) if raw_r[t.tid][0] > 0]
        out(f"| {h:g} m | {q([g[0] for g in gl], 0.5):.0f} m | {q(ratio, 0.5):.2f} |")

    out("\n## Importregel mit Schwelle? (Gegenprobe)\n")
    out("Die Importregel „Abstieg > 2 × Anstieg“ rechnet heute ROH (so ist sie gemessen). "
        "Wie viele Dateien unter 8 km kippten, rechnete sie mit Schwelle?\n")
    out("| Schwelle | Fahrt → Trail | Trail → Fahrt |")
    out("|---:|---:|---:|")
    short = [t for t in with_ele if MIN_TRAIL_M <= t.length_m < TRAIL_MAX_M]
    for h in THRESHOLDS[1:]:
        to_trail = to_ride = 0
        for t in short:
            g0, l0 = gain_loss(t.ele, 0.0)
            g1, l1 = gain_loss(t.ele, h)
            raw_trail, new_trail = l0 > 2 * g0, l1 > 2 * g1
            to_trail += (not raw_trail) and new_trail
            to_ride += raw_trail and not new_trail
        out(f"| {h:g} m | {to_trail} | {to_ride} |")

    out("\n## Ausdünnen vor dem Hochladen\n")
    out("Punkte, die übrig bleiben, und Abweichung von Anstieg/Abstieg gegenüber allen "
        "Punkten, je Schwelle. „nur 3 m“ ist die heutige Vereinfachung ohne Höhe.\n")
    out("| senkrecht | Punkte übrig | Δ Anstieg p90 (3 m) | Δ Abstieg p90 (3 m) | Δ Anstieg p90 (5 m) | Δ Abstieg p90 (5 m) |")
    out("|---|---:|---:|---:|---:|---:|")
    for vtol in VTOLS:
        kept_share, dg3, dl3, dg5, dl5 = [], [], [], [], []
        for t in trails:
            xy = project(t, statistics.fmean(t.lat))
            idx = simplify_3d(xy, t.ele, vtol=vtol)
            kept_share.append(len(idx) / len(xy))
            sub = [t.ele[i] for i in idx]
            for h, dg, dl in ((3.0, dg3, dl3), (5.0, dg5, dl5)):
                g0, l0 = gain_loss(t.ele, h)
                g1, l1 = gain_loss(sub, h)
                dg.append(abs(g1 - g0))
                dl.append(abs(l1 - l0))
        label = "nur 3 m" if vtol is None else f"{vtol:g} m"
        out(f"| {label} | {100 * q(kept_share, 0.5):.0f} % | {q(dg3, 0.9):.0f} m | {q(dl3, 0.9):.0f} m "
            f"| {q(dg5, 0.9):.0f} m | {q(dl5, 0.9):.0f} m |")

    out("\n## Steilstes Stück — Trails\n")
    out("| Fenster | Median | p90 | über 100 % |")
    out("|---:|---:|---:|---:|")
    for w in WINDOWS:
        vals = []
        for t in trails:
            s = steepest(cumulative(project(t, statistics.fmean(t.lat))), t.ele, w)
            if s is not None:
                vals.append(s)
        over = sum(1 for v in vals if v > 100)
        out(f"| {w:g} m | {q(vals, 0.5):.0f} % | {q(vals, 0.9):.0f} % | {over} |")

    report = "\n".join(lines) + "\n"
    if report_path:
        with open(report_path, "w", encoding="utf-8") as f:
            f.write(report)
    return report


# -------------------------------------------------------------- self-test

# Dieselben Vektoren stehen in test/trails/trail_elevation_test.dart.
VECTORS = [
    # (Höhen, Schwelle, Anstieg, Abstieg)
    ([100, 101, 100, 101, 100, 90], 0.0, 2.0, 12.0),
    ([100, 101, 100, 101, 100, 90], 2.0, 0.0, 10.0),
    ([100, 98, 104, 95, 96, 80], 3.0, 4.0, 24.0),
    ([100, 104, 108, 104, 100], 5.0, 8.0, 8.0),
    ([100, 102, 104], 5.0, 4.0, 0.0),   # Rest am Ende wird gebucht
]


def self_test() -> int:
    for ele, h, g, l in VECTORS:
        got = gain_loss([float(e) for e in ele], h)
        assert got == (g, l), (ele, h, got)
        assert abs((got[1] - got[0]) - (ele[0] - ele[-1])) < 1e-9, "net drop must not depend on h"
    # Gerade Linie mit einer Welle: ohne senkrechte Toleranz geht die
    # Welle verloren, mit ihr bleibt sie.
    xy = [(float(i * 10), 0.0) for i in range(11)]
    ele = [100.0 - i for i in range(11)]
    ele[5] = 110.0
    flat = simplify_3d(xy, ele)
    assert flat == [0, 10], flat
    bumpy = simplify_3d(xy, ele, vtol=2.0)
    assert bumpy == [0, 4, 5, 6, 10], bumpy   # dieselben Indizes im Dart-Test
    assert gain_loss([ele[i] for i in flat], 3.0) == (0.0, 10.0)
    assert gain_loss([ele[i] for i in bumpy], 3.0)[0] >= 13.0, gain_loss([ele[i] for i in bumpy], 3.0)
    # Steilstes Stück: 20 m auf 100 m = 20 %.
    dist = [0.0, 50.0, 100.0, 150.0]
    assert steepest(dist, [100.0, 95.0, 80.0, 78.0], 100.0) == 20.0
    assert steepest([0.0, 50.0], [100.0, 95.0], 100.0) is None
    print("elevation_measure self-test: ok")
    return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("path", nargs="?", default=os.environ.get("TRAIL_GPX"),
                    help="zip or directory of GPX files (default: $TRAIL_GPX)")
    ap.add_argument("--report", help="write the markdown report here")
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args(argv)
    if args.self_test:
        return self_test()
    if not args.path:
        ap.error("no input: pass a path or set TRAIL_GPX")
    tracks = load_tracks(args.path)
    if not tracks:
        print("no tracks found", file=sys.stderr)
        return 1
    print(run(tracks, args.report))
    return 0


if __name__ == "__main__":
    sys.exit(main())
