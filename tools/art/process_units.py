#!/usr/bin/env python3
"""Tekstury sprzętu: surowy obraz AI → materiał jednostki i pojazdu.

Użycie:
    python3 tools/art/process_units.py --raw /tmp/art/raw_units

Wyjście: `assets/textures/units/<klucz>.png` (256×256).

Tekstury są **jasne i neutralne** celowo: w grze materiał dostaje jeszcze kolor
strony (`albedo_color` = zielony gracz / niebiescy sojusznicy / czerwony wróg),
a Godot mnoży kolor przez teksturę. Dzięki temu detal pochodzi z tekstury,
a przynależność do strony pozostaje czytelna na pierwszy rzut oka.

Wymaga Pillow.
"""

import argparse
import pathlib

import pipeline

PROJECT_ROOT = pathlib.Path(__file__).resolve().parents[2]
DEFAULT_OUT = PROJECT_ROOT / "assets" / "textures" / "units"

SIZE = 256

# Klucze jak w scripts/logic/game_textures.gd (UNIT_KEYS).
UNITS = {
    "uniform": (0.75, 0.73, 0.67),   # tkanina munduru — pod barwienie strony
    "armor":   (0.69, 0.70, 0.67),   # blacha pojazdu — pod barwienie strony
    "track":   (0.62, 0.63, 0.64),   # ogniwa gąsienicy — ciemniejsze po stronie
}

NAMES = {"uniform": "mundur piechoty", "armor": "pancerz pojazdu", "track": "gąsienica"}


def process(key, raw_path, out_dir):
    target = pipeline.target_rgb(UNITS[key])
    image = pipeline.from_raw(raw_path, SIZE, target)
    path = out_dir / f"{key}.png"
    image.save(path, "PNG", optimize=True)
    got = tuple(round(v) for v in pipeline.mean_rgb(image))
    print(f"{key:8s} {NAMES[key]:17s} cel={target} wynik={got} {path.stat().st_size // 1024:4d} kB")


def main():
    parser = argparse.ArgumentParser(description="Przetwarza surowe tekstury sprzętu na materiały jednostek.")
    parser.add_argument("--raw", required=True, help="katalog z surowymi obrazami <klucz>.png")
    parser.add_argument("--out", default=str(DEFAULT_OUT), help="katalog docelowy")
    args = parser.parse_args()

    raw_dir = pathlib.Path(args.raw)
    out_dir = pathlib.Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)

    done, missing = [], []
    for key in UNITS:
        raw = raw_dir / f"{key}.png"
        if raw.exists():
            process(key, raw, out_dir)
            done.append(key)
        else:
            missing.append(key)
    print(f"\ngotowe: {len(done)}/{len(UNITS)}")
    if missing:
        print("brakuje surowych plików: " + ", ".join(missing))


if __name__ == "__main__":
    main()
