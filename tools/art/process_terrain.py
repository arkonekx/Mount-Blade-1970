#!/usr/bin/env python3
"""Pipeline tekstur terenu: surowy obraz AI → kafel gry.

Użycie:
    python3 tools/art/process_terrain.py --raw /tmp/art/raw

Wejście:  <raw>/<klucz>.png — surowy obraz z generatora (dowolny rozmiar).
Wyjście:  assets/textures/terrain/<klucz>.png       512×512 — materiały 3D bitwy
          assets/textures/terrain/tiles/<klucz>.png  16×16  — kafle mapy 2D

Każda tekstura jest programowo dopasowana do palety z `campaign_view.gd`
(wspólny rdzeń w `pipeline.py`), więc mapa złożona z trzynastu różnych obrazów
czyta się jak jeden obraz. Klucze (i kolejność) odpowiadają `Terrain.Kind`
z `scripts/logic/terrain.gd`.

Wymaga Pillow.
"""

import argparse
import pathlib

from PIL import Image, ImageEnhance

import pipeline

PROJECT_ROOT = pathlib.Path(__file__).resolve().parents[2]
DEFAULT_OUT = PROJECT_ROOT / "assets" / "textures" / "terrain"

MASTER_SIZE = 512
# Mapa kampanii rysuje jedno pole w rozmiarze 16 px, więc kafel ma dokładnie
# tyle pikseli — dzięki temu Godot nie skaluje go i nic się nie rozmywa.
TILE_SIZE = 16

# Paleta z scripts/campaign_view.gd (COLORS) — kolejność jak Terrain.Kind.
PALETTE = {
    "plains":   (0.42, 0.55, 0.31),
    "forest":   (0.18, 0.36, 0.20),
    "hills":    (0.52, 0.45, 0.32),
    "mountain": (0.42, 0.40, 0.38),
    "marsh":    (0.30, 0.40, 0.34),
    "river":    (0.20, 0.38, 0.62),
    "ford":     (0.40, 0.60, 0.78),
    "lake":     (0.16, 0.28, 0.50),
    "city":     (0.72, 0.66, 0.55),
    "road":     (0.62, 0.56, 0.42),
    "bridge":   (0.70, 0.58, 0.38),
    "sand":     (0.80, 0.74, 0.52),
    "snow":     (0.92, 0.94, 0.97),
}

NAMES = {
    "plains": "równina", "forest": "las", "hills": "wzgórza",
    "mountain": "góry", "marsh": "bagno", "river": "rzeka",
    "ford": "bród", "lake": "jezioro", "city": "miasto",
    "road": "droga", "bridge": "most", "sand": "piasek", "snow": "śnieg",
}


def process(key, raw_path, out_dir):
    target = pipeline.target_rgb(PALETTE[key])
    master_image = pipeline.from_raw(raw_path, MASTER_SIZE, target)

    master = out_dir / f"{key}.png"
    master_image.save(master, "PNG", optimize=True)

    tile = master_image.resize((TILE_SIZE, TILE_SIZE), Image.LANCZOS)
    tile = ImageEnhance.Sharpness(tile).enhance(1.15)
    tile.save(out_dir / "tiles" / f"{key}.png", "PNG", optimize=True)

    got = tuple(round(v) for v in pipeline.mean_rgb(master_image))
    print(f"{key:9s} {NAMES[key]:8s} cel={target} wynik={got} "
          f"master={master.stat().st_size // 1024:4d} kB")


def main():
    parser = argparse.ArgumentParser(description="Przetwarza surowe tekstury AI na kafle terenu.")
    parser.add_argument("--raw", required=True, help="katalog z surowymi obrazami <klucz>.png")
    parser.add_argument("--out", default=str(DEFAULT_OUT), help="katalog docelowy")
    args = parser.parse_args()

    raw_dir = pathlib.Path(args.raw)
    out_dir = pathlib.Path(args.out)
    (out_dir / "tiles").mkdir(parents=True, exist_ok=True)

    done, missing = [], []
    for key in PALETTE:
        raw = raw_dir / f"{key}.png"
        if raw.exists():
            process(key, raw, out_dir)
            done.append(key)
        else:
            missing.append(key)
    print(f"\ngotowe: {len(done)}/{len(PALETTE)}")
    if missing:
        print("brakuje surowych plików: " + ", ".join(missing))


if __name__ == "__main__":
    main()
