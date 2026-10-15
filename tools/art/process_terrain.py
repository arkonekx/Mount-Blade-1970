#!/usr/bin/env python3
"""Pipeline tekstur terenu: surowy obraz AI → kafel gry.

Użycie:
    python3 tools/art/process_terrain.py --raw /tmp/art/raw

Wejście:  <raw>/<klucz>.png — surowy obraz z generatora (dowolny rozmiar).
Wyjście:  assets/textures/terrain/<klucz>.png       512×512 — materiały 3D bitwy
          assets/textures/terrain/tiles/<klucz>.png  64×64  — kafle mapy 2D

Każda tekstura jest programowo dopasowana do palety z `campaign_view.gd`,
więc mapa złożona z trzynastu różnych obrazów czyta się jak jeden obraz.
Klucze (i kolejność) odpowiadają `Terrain.Kind` z `scripts/logic/terrain.gd`.

Wymaga Pillow (`pip install pillow`).
"""

import argparse
import pathlib
from PIL import Image, ImageEnhance, ImageStat

# Domyślne ścieżki liczone względem korzenia repozytorium (katalog z project.godot).
PROJECT_ROOT = pathlib.Path(__file__).resolve().parents[2]
DEFAULT_OUT = PROJECT_ROOT / "assets" / "textures" / "terrain"

MASTER_SIZE = 512
# Mapa kampanii rysuje jedno pole w rozmiarze 16 px, więc kafel ma dokładnie
# tyle pikseli — dzięki temu Godot nie skaluje go i nic się nie rozmywa.
TILE_SIZE = 16
MASTER_BLEND = 0.55  # 0 = tylko przemalowanie w palecie, 1 = tylko korekta średniej

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


def target_rgb(key):
    r, g, b = PALETTE[key]
    return (round(r * 255), round(g * 255), round(b * 255))


def mean_rgb(image):
    return tuple(ImageStat.Stat(image).mean[:3])


def scale_to_target(image, target):
    """Skaluje kanały tak, by średnia koloru trafiła w paletę (zachowuje detal)."""
    got = mean_rgb(image)
    out = []
    for ch, got_ch, want in zip(image.split(), got, target):
        factor = min(max(want / max(got_ch, 1.0), 0.35), 2.8)
        out.append(ch.point(lambda v, f=factor: min(255, int(v * f))))
    return Image.merge("RGB", out)


def relight(image, target):
    """Wersja „przemalowana”: struktura z jasności, kolor z palety."""
    grey = image.convert("L")
    mean_lum = max(ImageStat.Stat(grey).mean[0], 1.0)
    target_lum = sum(target) / 3.0

    def remap(v):
        return min(255, int(v * (target_lum / mean_lum)))

    grey = grey.point(remap)
    tint = Image.new("RGB", image.size)
    scale = target_lum / 255.0 if target_lum else 1.0
    tint.putdata([(
        min(255, int(v * target[0] / 255.0 / scale)),
        min(255, int(v * target[1] / 255.0 / scale)),
        min(255, int(v * target[2] / 255.0 / scale)),
    ) for v in grey.get_flattened_data()])
    return tint


def process(key, raw_path, out_dir):
    image = Image.open(raw_path).convert("RGB")
    w, h = image.size
    side = min(w, h)
    left, top = (w - side) // 2, (h - side) // 2
    image = image.crop((left, top, left + side, top + side))
    image = image.resize((MASTER_SIZE, MASTER_SIZE), Image.LANCZOS)

    target = target_rgb(key)
    blended = Image.blend(scale_to_target(image, target), relight(image, target), 1.0 - MASTER_BLEND)
    blended = ImageEnhance.Contrast(blended).enhance(1.08)
    blended = ImageEnhance.Color(blended).enhance(1.05)
    blended = scale_to_target(blended, target)

    master = out_dir / f"{key}.png"
    blended.save(master, "PNG", optimize=True)

    tile = blended.resize((TILE_SIZE, TILE_SIZE), Image.LANCZOS)
    tile = ImageEnhance.Sharpness(tile).enhance(1.15)
    tile.save(out_dir / "tiles" / f"{key}.png", "PNG", optimize=True)

    got = tuple(round(v) for v in mean_rgb(blended))
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
