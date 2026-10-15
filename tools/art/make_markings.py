#!/usr/bin/env python3
"""Oznaczenia państwowe na pojazdach: biała gwiazda USA, czerwona gwiazda ZSRR.

Użycie:
    python3 tools/art/make_markings.py

Gwiazdy rysujemy programowo, a nie generatorem obrazów: to znak geometryczny,
więc musi mieć równe ramiona i ostre krawędzie. Pliki lądują w
`assets/textures/markings/` jako 128×128 RGBA (tło przezroczyste), a gra kładzie
je jako cienkie płytki na pancerzu (`_part_marking` w battle_view.gd).
"""

import argparse
import math
import pathlib

from PIL import Image, ImageDraw

PROJECT = pathlib.Path(__file__).resolve().parents[2]
OUT_DIR = PROJECT / "assets" / "textures" / "markings"

SIZE = 128
SS = 4  # nadpróbkowanie, żeby krawędzie gwiazdy były gładkie

# (klucz, kolor gwiazdy, kolor obwódki) — obwódka trzyma znak czytelnym
# na ciemnym pancerzu, tak jak w oryginalnych malowaniach.
MARKS = [
    ("star_us", (238, 238, 232), (32, 34, 28)),
    ("star_su", (176, 34, 30), (232, 232, 226)),
]


def star_points(cx, cy, outer, inner, points=5, start=-90.0):
    """Wierzchołki gwiazdy: na przemian ramię i wcięcie."""
    out = []
    for i in range(points * 2):
        radius = outer if i % 2 == 0 else inner
        angle = math.radians(start + i * 180.0 / points)
        out.append((cx + math.cos(angle) * radius, cy + math.sin(angle) * radius))
    return out


def draw_star(fill, outline):
    big = SIZE * SS
    image = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    cx = cy = big * 0.5
    outer = big * 0.46
    inner = outer * 0.382  # proporcja gwiazdy pięcioramiennej
    shape = star_points(cx, cy, outer, inner)
    draw.polygon(shape, fill=fill + (255,), outline=outline + (255,))
    # obwódka gruba na tyle, by przetrwała zmniejszenie do 128 px
    draw.line(shape + [shape[0]], fill=outline + (255,), width=int(big * 0.022), joint="curve")
    return image.resize((SIZE, SIZE), Image.LANCZOS)


def main():
    parser = argparse.ArgumentParser(description="Rysuje oznaczenia państwowe pojazdów.")
    parser.add_argument("--out", default=str(OUT_DIR))
    args = parser.parse_args()
    out_dir = pathlib.Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)

    for key, fill, outline in MARKS:
        image = draw_star(fill, outline)
        path = out_dir / f"{key}.png"
        image.save(path, "PNG", optimize=True)
        opaque = sum(1 for px in image.getdata() if px[3] > 0)
        print(f"{path.name}: {image.width}×{image.height} RGBA, "
              f"{opaque * 100 // (image.width * image.height)} % pokrycia, "
              f"{path.stat().st_size // 1024} kB")


if __name__ == "__main__":
    main()
