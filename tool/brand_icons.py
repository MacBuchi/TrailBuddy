#!/usr/bin/env python3
"""Erzeugt alle App-Symbole aus dem EINEN Logo (Design Turn 1b).

Das Logo ist die Serpentine: zwei Kehren und ein Ziel —
Pfad `LOGO_PATH`, Strich 14 mit runden Enden und Ecken, Endpunkt Kreis
(82, 72) r 7, viewBox 100. Dieselbe Geometrie steht in Dart
(`lib/core/widgets/trailbuddy_logo.dart`, `kLogoSvgPath`);
`test/brand_icons_test.dart` hält beide zusammen.

Geschrieben werden:

- `drawable/ic_notification.xml` — das Statusleisten-Symbol für Push UND
  die Dauerbenachrichtigung der Fahrt: weiß, nur Alphakanal, 12 % Rand.
  Ein Vektor statt PNGs je Dichte: dieselbe Form auf jedem Gerät, und
  Android rastert ihn selbst.
- `drawable/ic_launcher_foreground.xml` + `mipmap-anydpi-v26/ic_launcher.xml`
  — das adaptive Symbol (Vordergrund dunkel, Hintergrund Lime aus
  `values/colors.xml`), dazu `monochrome` für Androids Themen-Symbole.
- `mipmap-*/ic_launcher.png` — dasselbe Bild für Android vor 8.0.
- `web/icons/Icon-{192,512}.png`, `Icon-maskable-{192,512}.png`,
  `web/favicon.png`.

Die Vektoren prüft `--check` als Fixpunkt (ohne Werkzeug); die PNGs
braucht `rsvg-convert` (librsvg) und stehen mit Prüfsumme in
`tool/generated_assets.json`. Nach einer Änderung hier:
`python3 tool/brand_icons.py && python3 tool/generated_assets.py --update`.
"""
import argparse
import os
import subprocess
import sys
import tempfile

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join("android", "app", "src", "main", "res")

LOGO_PATH = "M20 20H62a13 13 0 0 1 0 26H38a13 13 0 0 0 0 26H72"
LOGO_STROKE = 14
LOGO_DOT = (82, 72, 7)
# Die Mitte der Form MIT Strich und Punkt: x 13…89, y 13…79.
LOGO_CENTER = (51, 46)
LOGO_EXTENT = 76  # die längere Seite (Breite)

BRAND = "#B6F04A"
ON_BRAND = "#0E1411"

# Anteil der Symbolbreite an der Kante — für jedes Ziel einmal gewählt.
# Adaptiv: sichtbar ist der Kreis mit 66 von 108 dp; 0.62 lässt die Ecken
# der Form (halbe Diagonale 50 Einheiten) innerhalb von 33.
ADAPTIVE_SCALE = 0.62
LEGACY_SCALE = 0.72
MASKABLE_SCALE = 0.62  # sicher: Kreis mit 40 % Radius
FAVICON_SCALE = 0.86

# Android-Pfade kennen dieselbe Syntax, wollen aber Kommas nicht zwingend.
ANDROID_PATH = LOGO_PATH


def _dot_path(cx, cy, r):
    return f"M{cx - r},{cy}a{r},{r} 0 1,0 {2 * r},0a{r},{r} 0 1,0 {-2 * r},0"


def _transform(size, scale_of_size):
    """Skalierung und Verschiebung, die die Form mittig auf `size` legt."""
    k = size * scale_of_size / LOGO_EXTENT
    tx = size / 2 - k * LOGO_CENTER[0]
    ty = size / 2 - k * LOGO_CENTER[1]
    return k, tx, ty


def _fmt(x):
    return f"{x:.4f}".rstrip("0").rstrip(".")


def notification_xml():
    # viewBox 100, Form 76 breit ⇒ genau 12 % Rand links und rechts.
    tx = 50 - LOGO_CENTER[0]
    ty = 50 - LOGO_CENTER[1]
    return f"""<?xml version="1.0" encoding="utf-8"?>
<!-- ERZEUGT von tool/brand_icons.py — nicht von Hand ändern.

     Das Symbol in der Statusleiste, für Push (#34) und die
     Dauerbenachrichtigung der Fahrt (#28): die Serpentine aus dem Logo.
     Android wertet ein Statusleisten-Symbol NUR über den Alphakanal aus
     (jedes nicht durchsichtige Pixel wird weiß), deshalb weiß, eine
     Farbe, 12 % Rand. -->
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp"
    android:height="24dp"
    android:viewportWidth="100"
    android:viewportHeight="100">
    <group
        android:translateX="{_fmt(tx)}"
        android:translateY="{_fmt(ty)}">
        <path
            android:pathData="{ANDROID_PATH}"
            android:strokeColor="#FFFFFFFF"
            android:strokeWidth="{LOGO_STROKE}"
            android:strokeLineCap="round"
            android:strokeLineJoin="round" />
        <path
            android:fillColor="#FFFFFFFF"
            android:pathData="{_dot_path(*LOGO_DOT)}" />
    </group>
</vector>
"""


def launcher_foreground_xml(color, what):
    k, tx, ty = _transform(108, ADAPTIVE_SCALE)
    return f"""<?xml version="1.0" encoding="utf-8"?>
<!-- ERZEUGT von tool/brand_icons.py — nicht von Hand ändern.
     {what} des adaptiven App-Symbols: die Serpentine, mittig im
     sichtbaren Kreis (66 von 108 dp). -->
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
    <group
        android:scaleX="{_fmt(k)}"
        android:scaleY="{_fmt(k)}"
        android:translateX="{_fmt(tx)}"
        android:translateY="{_fmt(ty)}">
        <path
            android:pathData="{ANDROID_PATH}"
            android:strokeColor="{color}"
            android:strokeWidth="{LOGO_STROKE}"
            android:strokeLineCap="round"
            android:strokeLineJoin="round" />
        <path
            android:fillColor="{color}"
            android:pathData="{_dot_path(*LOGO_DOT)}" />
    </group>
</vector>
"""


ADAPTIVE_XML = """<?xml version="1.0" encoding="utf-8"?>
<!-- ERZEUGT von tool/brand_icons.py — nicht von Hand ändern. -->
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@drawable/ic_launcher_foreground" />
    <monochrome android:drawable="@drawable/ic_launcher_monochrome" />
</adaptive-icon>
"""


def vector_files():
    return {
        os.path.join(RES, "drawable", "ic_notification.xml"): notification_xml(),
        os.path.join(RES, "drawable", "ic_launcher_foreground.xml"):
            launcher_foreground_xml("#FF0E1411", "Vordergrund"),
        os.path.join(RES, "drawable", "ic_launcher_monochrome.xml"):
            launcher_foreground_xml("#FFFFFFFF", "Themen-Variante (nur Alpha)"),
        os.path.join(RES, "mipmap-anydpi-v26", "ic_launcher.xml"): ADAPTIVE_XML,
    }


def symbol_svg(px, scale, background, radius_ratio, color=ON_BRAND):
    k, tx, ty = _transform(100, scale)
    bg = ""
    if background:
        r = 100 * radius_ratio
        bg = f'<rect width="100" height="100" rx="{_fmt(r)}" fill="{background}"/>'
    cx, cy, r = LOGO_DOT
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{px}" height="{px}" '
        f'viewBox="0 0 100 100">{bg}'
        f'<g transform="translate({_fmt(tx)} {_fmt(ty)}) scale({_fmt(k)})">'
        f'<path d="{LOGO_PATH}" fill="none" stroke="{color}" '
        f'stroke-width="{LOGO_STROKE}" stroke-linecap="round" stroke-linejoin="round"/>'
        f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{color}"/></g></svg>'
    )


def png_targets():
    t = {}
    for density, px in [("mdpi", 48), ("hdpi", 72), ("xhdpi", 96),
                         ("xxhdpi", 144), ("xxxhdpi", 192)]:
        t[os.path.join(RES, f"mipmap-{density}", "ic_launcher.png")] = \
            symbol_svg(px, LEGACY_SCALE, BRAND, 0.22)
    for px in (192, 512):
        t[f"web/icons/Icon-{px}.png"] = symbol_svg(px, LEGACY_SCALE, BRAND, 0.22)
        t[f"web/icons/Icon-maskable-{px}.png"] = symbol_svg(px, MASKABLE_SCALE, BRAND, 0)
    t["web/favicon.png"] = symbol_svg(32, FAVICON_SCALE, BRAND, 0.22)
    return t


def write_all(root):
    for rel, text in vector_files().items():
        path = os.path.join(root, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            f.write(text)
    with tempfile.TemporaryDirectory() as tmp:
        for rel, svg in png_targets().items():
            src = os.path.join(tmp, "icon.svg")
            with open(src, "w", encoding="utf-8") as f:
                f.write(svg)
            subprocess.run(["rsvg-convert", src, "-o", os.path.join(root, rel)],
                           check=True)


def check(root):
    """Die Vektoren sind ein Fixpunkt dieses Skripts."""
    stale = []
    for rel, text in vector_files().items():
        path = os.path.join(root, rel)
        try:
            with open(path, encoding="utf-8") as f:
                if f.read() == text:
                    continue
        except FileNotFoundError:
            pass
        stale.append(rel)
    for rel in stale:
        print(f"{rel}: nicht aus tool/brand_icons.py erzeugt — "
              f"python3 tool/brand_icons.py laufen lassen", file=sys.stderr)
    return not stale


def self_test():
    k, tx, ty = _transform(100, 0.76)
    # 76 % der Kante bei Maßstab 1: die Form sitzt genau auf 12…88.
    assert abs(k - 1) < 1e-9, k
    assert (13 * k + tx, 89 * k + tx) == (12, 88), (tx,)
    assert abs((13 + 79) / 2 * k + ty - 50) < 1e-9
    xml = notification_xml()
    assert 'android:translateX="-1"' in xml and 'android:translateY="4"' in xml
    assert "#FFFFFFFF" in xml and "0E1411" not in xml
    svg = symbol_svg(48, LEGACY_SCALE, BRAND, 0.22)
    assert LOGO_PATH in svg and 'width="48"' in svg
    print("brand_icons self-test ok")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args()
    if args.self_test:
        self_test()
        return
    if args.check:
        sys.exit(0 if check(REPO_ROOT) else 1)
    write_all(REPO_ROOT)


if __name__ == "__main__":
    main()
