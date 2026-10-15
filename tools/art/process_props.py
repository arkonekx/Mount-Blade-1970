#!/usr/bin/env python3
"""Tekstury otoczenia bitwy: surowy obraz AI → materiał 3D.

Użycie:
    python3 tools/art/process_props.py --raw /tmp/art/raw_props

Wyjście: `assets/textures/props/<klucz>.png` (256×256).

W przeciwieństwie do kafli terenu te tekstury są powierzchniami obiektów
(kora pnia, igliwie korony, skała, ściana bloku, dach), więc nie mają
odpowiednika w `Terrain.Kind` — klucze odpowiadają obiektom z
`scripts/battle/battle_view.gd`, a kolory docelowe trzymają je w tej samej
stonowanej palecie co teren.

Wymaga Pillow.
"""

import argparse
import pathlib

import pipeline

PROJECT_ROOT = pathlib.Path(__file__).resolve().parents[2]
DEFAULT_OUT = PROJECT_ROOT / "assets" / "textures" / "props"

SIZE = 256

# Kolejność i klucze jak w scripts/logic/game_textures.gd (PROP_KEYS).
PROPS = {
    "tree_bark":   (0.34, 0.27, 0.20),
    "tree_canopy": (0.15, 0.25, 0.14),
    "rock":        (0.48, 0.47, 0.45),
    "wall":        (0.58, 0.57, 0.54),
    "roof":        (0.38, 0.38, 0.39),
}

NAMES = {
    "tree_bark": "kora pnia", "tree_canopy": "korona drzewa", "rock": "skała",
    "wall": "ściana bloku", "roof": "dach",
}


def process(key, raw_path, out_dir):
    target = pipeline.target_rgb(PROPS[key])
    image = pipeline.from_raw(raw_path, SIZE, target)
    path = out_dir / f"{key}.png"
    image.save(path, "PNG", optimize=True)
    got = tuple(round(v) for v in pipeline.mean_rgb(image))
    print(f"{key:12s} {NAMES[key]:14s} cel={target} wynik={got} {path.stat().st_size // 1024:4d} kB")


def main():
    parser = argparse.ArgumentParser(description="Przetwarza surowe tekstury otoczenia na materiały 3D.")
    parser.add_argument("--raw", required=True, help="katalog z surowymi obrazami <klucz>.png")
    parser.add_argument("--out", default=str(DEFAULT_OUT), help="katalog docelowy")
    args = parser.parse_args()

    raw_dir = pathlib.Path(args.raw)
    out_dir = pathlib.Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)

    done, missing = [], []
    for key in PROPS:
        raw = raw_dir / f"{key}.png"
        if raw.exists():
            process(key, raw, out_dir)
            done.append(key)
        else:
            missing.append(key)
    print(f"\ngotowe: {len(done)}/{len(PROPS)}")
    if missing:
        print("brakuje surowych plików: " + ", ".join(missing))


if __name__ == "__main__":
    main()
