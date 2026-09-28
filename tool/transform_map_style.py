#!/usr/bin/env python3
"""Adapts the generated Protomaps style for BOTH renderers we ship.

The style from @protomaps/basemaps uses MapLibre expressions the Flutter
renderer (vector_tile_renderer 6.x) does not support; affected layers were
silently dropped — no labels, gray landcover. This script rewrites them:

- "ist der Wert einer davon" wird vereinheitlicht — siehe [rewrite_in]:
  im Filter die alte Kurzform, in `paint`/`layout` ein "match".
- complex "format"/multi-script text-field expressions
  -> ["coalesce", ["get", "name:de"], ["get", "name"]]
- drops icon-based layers (shields, oneway arrows) — we ship no sprites.

Beyond the renderer fixes it makes one deliberate design change:
hiking paths, forest tracks and trails get their own visible layers
instead of disappearing into the `roads_other` catch-all — see
`emphasize_paths`.

Usage (after regenerating the style with @protomaps/basemaps):
    python3 tool/transform_map_style.py assets/map_style/protomaps_light_de.json
"""
import json
import sys

SIMPLE_NAME = ["coalesce", ["get", "name:de"], ["get", "name"]]

# Die Wanderwege-Töne stehen bewusst HIER und nicht in
# `lib/core/app_colors.dart`: Diesen Stil erzeugt ein Werkzeug, das kein
# Dart liest.
#
# **Zurückgenommen am 2026-08-21** (Betreiber: „die Wege könnten
# deutlich dezenter dargestellt werden", am Emulator nachgesehen). Das
# Ockerbraun von 1.97.0 (#9a6b3f/#a9793f) war der stärkste Kontrast auf
# der ganzen Karte — kräftiger als die Straßen, über die es lief, und
# im Feldgebiet ein braunes Netz über allem. Es sollte sichtbar sein,
# nicht laut. Jetzt ein gebrochenes Graubraun: über dem Erdton
# (#e2dfda) und über dem Waldgrün (#9cd3b4) lesbar, aber ruhiger als
# jede Straße.
PATH_TRACK_COLOR = "#a58a6a"
PATH_COLOR = "#b6a08a"

# Wegarten, die keine Wanderwege sind: Bürgersteige und Fußgängerüberwege
# hängen an jeder Stadtstraße. Sie fallen damit ganz weg — für eine
# Pilz-App ist das Gewinn, nicht Verlust.
URBAN_PATH_DETAILS = ("sidewalk", "crossing")


def path_layers():
    """Die zwei Wanderwege-Ebenen — bei jedem Aufruf gleich aufgebaut.

    Eigene Funktion, damit [emphasize_paths] sie ERSETZEN statt ergänzen
    kann: Nur so bleibt [transform] ein Fixpunkt.

    **Der Strich ist Zugabe, die Aussage tragen Farbe und Breite.**
    `vector_tile_renderer` 6.1.0 prüft in `paint_factory.dart`
    `dashJson is List<num>` — `jsonDecode` liefert aber `List<dynamic>`,
    und das ist in Dart kein `List<num>`. Auf dem klassischen Renderer
    (Web und `classicMapEnabled`) sind die Wege deshalb durchgezogen,
    in MapLibre gestrichelt. Dieselbe Lage wie bei `roads_rail` und
    allen `roads_tunnels_*` seit jeher. Darum liegen die Breiten von
    Forstweg und Pfad bewusst weit auseinander (Faktor ~1,75 statt
    ~1,3): Wo der Strich fehlt, muss die Breite die Wegart allein
    tragen. Genau das prüft [self_test].
    """
    common = [["!has", "is_tunnel"], ["!has", "is_bridge"], ["==", "kind", "path"]]
    return [
        {
            "id": "roads_path_track",
            "type": "line",
            "source": "protomaps",
            "source-layer": "roads",
            # Ab z12 liegen Forstwege in den Kacheln (nachgemessen, s. u.).
            "minzoom": 12,
            "filter": ["all"] + common + [["==", "kind_detail", "track"]],
            "paint": {
                "line-color": PATH_TRACK_COLOR,
                "line-dasharray": [4, 2],
                "line-width": [
                    "interpolate", ["exponential", 1.6], ["zoom"],
                    12, 0.5, 15, 1.4, 20, 5,
                ],
            },
        },
        {
            "id": "roads_path",
            "type": "line",
            "source": "protomaps",
            "source-layer": "roads",
            # Pfade und Steige erst ab z13 — vorher stehen sie gar nicht
            # in den Kacheln, und in der Übersicht wären sie Rauschen.
            "minzoom": 13,
            "filter": ["all"] + common
            + [["!=", "kind_detail", "track"], ["!=", "kind_detail", "pier"]]
            + [["!=", "kind_detail", detail] for detail in URBAN_PATH_DETAILS],
            "paint": {
                "line-color": PATH_COLOR,
                "line-dasharray": [2, 2],
                "line-width": [
                    "interpolate", ["exponential", 1.6], ["zoom"],
                    13, 0.35, 15, 0.8, 20, 3,
                ],
            },
        },
    ]


def emphasize_paths(style):
    """Wanderwege bekommen eine eigene Ebene statt der Sammelgrube.

    **Das Problem:** Protomaps steckt Pfade, Forstwege, Steige und
    Reitwege als `kind == "path"` in dieselbe Ebene wie Zufahrten und
    Bahnsteige (`kind == "other"`). Der LIGHT-Flavor malt die Ebene
    `#ebebeb` auf einen `#e2dfda`-Boden und bei z14 mit 0,5 px — für
    eine Pilz-App ist damit ausgerechnet das unsichtbar, worauf man
    läuft. Kein Datenproblem: Die Wege stehen vollständig in den
    Kacheln.

    **Nachgemessen** (2026-08-20, Archiv `de_saarland` aus den
    Nomad-Releases, Kacheln z12–z14 über Range-Requests): Forstwege
    (`kind_detail == "track"`) liegen ab z12 in den Kacheln, alles
    Übrige (`path`, `footway`, `cycleway`, `steps`) ab z13. Genau dort
    setzen die beiden `minzoom` an.

    **Wie laut, ist am 2026-08-21 korrigiert worden** (siehe
    [PATH_TRACK_COLOR]): sichtbar, aber leiser als die Straßen. Die
    erste Fassung war am Emulator das Auffälligste auf der ganzen
    Karte — auch deshalb, weil die Flächen darunter fehlten, siehe
    [rewrite_in].

    **Idempotent, und das ist Pflicht:** `tool/generated_assets.py`
    wendet [transform] auf das committete Asset an und verlangt
    byteidentische Ausgabe. Deshalb stellt dieser Schritt einen
    Endzustand her — alte Ebenen gleicher id raus, frische rein — statt
    etwas anzuhängen.
    """
    layers = style["layers"]
    if not any(layer["id"] == "roads_other" for layer in layers):
        raise SystemExit("roads_other fehlt — der erzeugte Stil sieht anders aus als erwartet")
    fresh = path_layers()
    ours = {layer["id"] for layer in fresh}
    layers = [layer for layer in layers if layer["id"] not in ours]
    at = next(i for i, layer in enumerate(layers) if layer["id"] == "roads_other")
    # Die Sammelgrube behält nur noch, was wirklich Nebensache ist.
    layers[at]["filter"] = [
        "all",
        ["!has", "is_tunnel"],
        ["!has", "is_bridge"],
        ["==", "kind", "other"],
        ["!=", "kind_detail", "pier"],
    ]
    # Hinter roads_other, also UNTER den Straßen — eine Straße, die einen
    # Forstweg kreuzt, gehört obenauf.
    layers[at + 1:at + 1] = fresh
    style["layers"] = layers
    return style


# Die Operatoren der ALTEN Filter-Kurzform. Sie ist kein Ausdruck: Ein
# `["in", "kind", "a", "b"]` versteht MapLibre nur, solange der GANZE
# Filter in dieser Sprache steht — in `paint` oder neben einem echten
# Ausdruck ist es ein Syntaxfehler.
LEGACY_OPS = {
    "==", "!=", "<", ">", "<=", ">=",
    "in", "!in", "has", "!has", "all", "any", "none",
}


def in_parts(expr):
    """`(Schlüssel, Werte, verneint)` — oder None, wenn das keine
    „ist der Wert einer davon"-Prüfung ist.

    Erkennt BEIDE Schreibweisen, und das ist Pflicht: [main] läuft auf
    das bereits umgebaute Asset (Fixpunkt), findet dort also die alte
    Kurzform von gestern und muss sie genauso einordnen können wie die
    frisch erzeugte Ausdrucksform.
    """
    if not isinstance(expr, list) or len(expr) < 2:
        return None
    op = expr[0]
    if op not in ("in", "!in"):
        return None
    if (
        op == "in"
        and len(expr) == 3
        and isinstance(expr[1], list)
        and len(expr[1]) == 2
        and expr[1][0] == "get"
        and isinstance(expr[2], list)
        and len(expr[2]) == 2
        and expr[2][0] == "literal"
    ):
        return expr[1][1], list(expr[2][1]), False
    if isinstance(expr[1], str):
        return expr[1], list(expr[2:]), op == "!in"
    return None


def needs_expression(node):
    """Steht in diesem Filter etwas, das NUR als Ausdruck gültig ist?

    Entscheidet, in welcher Sprache [rewrite_in] den Filter verlässt.
    „Ist der Wert einer davon" zählt dabei ausdrücklich NICHT mit — die
    Form wählt ja gerade diese Funktion, und beide Sprachen können sie.
    """
    if not isinstance(node, list) or not node:
        return False
    if in_parts(node) is not None:
        return False
    op = node[0]
    if op in ("all", "any", "none"):
        return any(needs_expression(part) for part in node[1:])
    if not isinstance(op, str) or op not in LEGACY_OPS:
        return True
    # Alte Kurzform heißt: erstes Argument ist der nackte Feldname.
    return len(node) > 1 and not isinstance(node[1], str)


def rewrite_in(expr, *, as_expression):
    """Vereinheitlicht jedes „ist der Wert einer davon" im Baum.

    **Warum zwei Zielformen und nicht eine:** `vector_tile_renderer`
    6.1.0 nimmt `in` ausschließlich in der alten Kurzform an
    (`json[1] is String`, boolean_operator_expression_parser.dart) —
    daher gab es diesen Umbau überhaupt. MapLibre versteht die alte
    Form aber nur in einem Filter, der DURCHGEHEND alt ist; in `paint`
    ist sie ein Syntaxfehler, und der kostet die ganze Ebene.

    Genau das war seit 1.43.0 der Fall und ist am 2026-08-21 am
    Emulator aufgefallen: `landuse_park` (Wald, Wiese, Park) und `pois`
    fielen in MapLibre lautlos aus — die Offline-Karte zeigte fast nur
    noch Straßen. Beide Renderer können `match`, also steht dort jetzt
    `["match", ["get", k], [...], true, false]`.

    [as_expression] wählt die Sprache: `paint`/`layout` immer Ausdruck,
    ein Filter nur dann, wenn [needs_expression] sagt, dass er ohnehin
    schon einer ist. Sonst entstünde aus einem heilen alten Filter ein
    gemischter — derselbe Fehler, nur andersherum.
    """
    if not isinstance(expr, list):
        return expr
    parts = in_parts(expr)
    if parts is not None:
        key, values, negated = parts
        if as_expression:
            hit, miss = (False, True) if negated else (True, False)
            return ["match", ["get", key], values, hit, miss]
        return ["!in" if negated else "in", key, *values]
    return [rewrite_in(part, as_expression=as_expression) for part in expr]


def is_complex(expr):
    if not isinstance(expr, list) or not expr:
        return False
    # Auch tief verschachtelte format-/Mehrschrift-Konstrukte erwischen.
    return expr[0] in ("format", "case") or '"format"' in json.dumps(expr)


def transform(style):
    """Der Umbau selbst — mutiert [style] und gibt ihn zurück.

    Von [main] getrennt, damit `tool/generated_assets.py` ihn AUF das
    committete Asset anwenden und prüfen kann, dass nichts passiert.
    Genau dieser Fixpunkt ist die Aussage: Wer den Stil neu generiert
    und diesen Schritt vergisst, hat wieder graue Landflächen ohne
    Beschriftung — und zwar lautlos, denn der Renderer lässt die
    Ebenen, die er nicht versteht, einfach weg.
    """
    kept = []
    for layer in style["layers"]:
        layout = layer.get("layout", {})
        if "icon-image" in layout:
            # Icons brauchen Sprites, die wir nicht ausliefern. Ebenen mit
            # Text (Städtenamen, POIs) behalten wir ohne Icon; reine
            # Icon-Ebenen und Straßenschilder fliegen ganz raus.
            if "text-field" not in layout or layer["id"] == "roads_shields":
                continue
            for key in [k for k in layout if k.startswith("icon-")]:
                del layout[key]
            for key in [k for k in layer.get("paint", {}) if k.startswith("icon-")]:
                del layer["paint"][key]
        for section in ("paint", "layout", "filter"):
            if section == "filter":
                if "filter" in layer:
                    layer["filter"] = rewrite_in(
                        layer["filter"],
                        as_expression=needs_expression(layer["filter"]),
                    )
                continue
            block = layer.get(section)
            if not block:
                continue
            for key, value in list(block.items()):
                block[key] = rewrite_in(value, as_expression=True)
        if is_complex(layout.get("text-field")):
            layout["text-field"] = SIMPLE_NAME
        kept.append(layer)

    style["layers"] = kept
    return emphasize_paths(style)


def render(style):
    """Die EINE Schreibweise des Assets.

    Eigene Funktion, weil die Fixpunkt-Prüfung Byte für Byte vergleicht:
    Stünde die Formatierung an zwei Stellen, wiche sie beim ersten
    Eingriff ab, und die Prüfung meldete einen Unterschied, den es
    inhaltlich nicht gibt.
    """
    return json.dumps(style, ensure_ascii=False, indent=1)


def self_test():
    """Netzfrei, in Sekunden — läuft in CI mit den anderen Werkzeugen.

    Der Fixpunkt wird zwar auch von `tool/generated_assets.py` geprüft,
    aber der sagt nur DASS etwas nicht mehr passt. Hier steht, WAS.
    """
    def sample():
        modern_in = ["in", ["get", "kind"], ["literal", ["park", "forest"]]]
        return {"layers": [
            {"id": "earth", "type": "fill"},
            # Die Fläche, die es 1.97.0 zerlegt hat: ein `in` MITTEN in
            # einem paint-Ausdruck.
            {"id": "landuse_park", "type": "fill", "source-layer": "landuse",
             "filter": modern_in,
             "paint": {"fill-color": ["case", modern_in, "#9cd3b4", "#e2dfda"]}},
            # Und der gemischte Filter: alte Kurzform neben ["zoom"].
            {"id": "pois", "type": "symbol", "source-layer": "pois",
             "filter": ["all", modern_in, [">=", ["zoom"], ["get", "min_zoom"]]]},
            {"id": "roads_other", "type": "line", "source-layer": "roads",
             "filter": ["all", ["in", "kind", "other", "path"]]},
            {"id": "roads_minor", "type": "line", "source-layer": "roads"},
            {"id": "roads_labels_minor", "type": "symbol",
             "layout": {"text-field": ["format", "x"]}},
        ]}

    def legacy_in_inside(node):
        """Steckt irgendwo eine alte `in`-Kurzform in diesem Baum?"""
        if not isinstance(node, list):
            return False
        if node and node[0] in ("in", "!in") and len(node) > 1 \
                and isinstance(node[1], str):
            return True
        return any(legacy_in_inside(part) for part in node)

    once = transform(sample())
    ids = [layer["id"] for layer in once["layers"]]
    assert ids.index("roads_path_track") == ids.index("roads_other") + 1, ids
    assert ids.index("roads_path") == ids.index("roads_other") + 2, ids
    assert ids.index("roads_path") < ids.index("roads_minor"), \
        "Wege gehören UNTER die Straßen"

    other = next(l for l in once["layers"] if l["id"] == "roads_other")
    assert "path" not in json.dumps(other["filter"]), \
        "roads_other sammelt kind == path immer noch ein"

    # Der Fixpunkt: ein zweiter Lauf darf nichts mehr ändern. Genau das
    # verlangt `generated_assets.py` vom ausgelieferten Asset.
    assert render(transform(json.loads(render(once)))) == render(once), \
        "transform ist kein Fixpunkt — der zweite Lauf ändert etwas"

    # Farbe UND Breite müssen die zwei Wegarten allein tragen: Der
    # klassische Renderer wirft den Strich weg (siehe path_layers).
    def width_at(layer_id, zoom):
        layer = next(l for l in once["layers"] if l["id"] == layer_id)
        stops = layer["paint"]["line-width"][3:]
        return dict(zip(stops[::2], stops[1::2]))[zoom]

    assert width_at("roads_path_track", 15) >= width_at("roads_path", 15) * 1.5, \
        "ohne Strich bleibt nur die Breite — der Abstand ist zu klein"

    # DER WÄCHTER: In paint/layout darf die alte Kurzform nie stehen.
    # MapLibre wirft eine Ebene mit diesem Syntaxfehler weg — lautlos.
    # Genau so waren Wald, Wiese und POI-Namen seit 1.43.0 unsichtbar.
    for layer in once["layers"]:
        for section in ("paint", "layout"):
            for key, value in (layer.get(section) or {}).items():
                assert not legacy_in_inside(value), \
                    f"{layer['id']}.{section}.{key} trägt die alte " \
                    "in-Kurzform — MapLibre wirft die Ebene weg"

    # Und ein Filter, in dem schon ein Ausdruck steht, muss GANZ
    # Ausdruck bleiben; gemischt lehnt MapLibre ihn genauso ab.
    pois = next(l for l in once["layers"] if l["id"] == "pois")
    assert not legacy_in_inside(pois["filter"]), \
        "gemischter Filter: alte Kurzform neben einem Ausdruck"

    # Umgekehrt: Ein durchgehend alter Filter BLEIBT alt — sonst
    # entstünde aus einem heilen Filter ein gemischter, und der
    # klassische Renderer kennt `in` NUR in der alten Kurzform.
    landuse = next(l for l in once["layers"] if l["id"] == "landuse_park")
    assert legacy_in_inside(landuse["filter"]), \
        "reiner in-Filter gehört in die alte Kurzform (vector_tile_renderer)"

    # Fehlt roads_other, wird abgebrochen statt hinten angehängt: dort
    # lägen die Wege über den Beschriftungen.
    broken = {"layers": [{"id": "earth", "type": "fill"}]}
    try:
        transform(broken)
    except SystemExit:
        pass
    else:  # pragma: no cover
        raise AssertionError("fehlendes roads_other muss abbrechen")

    print("self-test: ok")


def main(path):
    with open(path, encoding="utf-8") as f:
        style = json.load(f)
    style = transform(style)
    with open(path, "w", encoding="utf-8") as f:
        f.write(render(style))
    print(f"OK: {len(style['layers'])} Ebenen geschrieben")


if __name__ == "__main__":
    if "--self-test" in sys.argv:
        self_test()
    else:
        main(sys.argv[1])
