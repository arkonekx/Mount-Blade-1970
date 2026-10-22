#!/usr/bin/env python3
"""Ikony HUD bitwy: surowy obraz AI na magentowym tle → PNG z przezroczystością.

Użycie:
    python3 tools/art/process_hud.py --raw /tmp/art/raw_hud

Wyjście: `assets/textures/hud/<klucz>.png` (128×128, RGBA).

To ten sam warsztat co `process_icons.py` (ikony mapy kampanii), ale osobny
katalog i osobne klucze: HUD rysuje je w innym rozmiarze i w innym miejscu
ekranu, a `test_textures.gd` pilnuje obu kompletów niezależnie.

Ikony są jasne (prawie białe), bo HUD podbarwia je przez `modulate` —
kolor zależy od stanu (amunicja, zdrowie), a nie od pliku.
"""

import argparse
import pathlib
from PIL import Image

PROJECT_ROOT = pathlib.Path(__file__).resolve().parents[2]
DEFAULT_OUT = PROJECT_ROOT / "assets" / "textures" / "hud"

SIZE = 128
PAD_RATIO = 0.06       # margines wokół treści
KEY_SOFT = 28.0        # poniżej tej „magentowości” piksel jest w pełni nieprzezroczysty
KEY_HARD = 78.0        # powyżej — w pełni przezroczysty

# Klucze jak w scripts/logic/game_textures.gd (HUD_KEYS).
HUD = {
    "weapon_rifle": "karabin",
    "weapon_hmg": "karabin maszynowy",
    "weapon_at": "wyrzutnia ppanc",
    "weapon_gun": "armata czołgowa",
    "target_infantry": "cel: piechota",
    "target_mech": "cel: wóz bojowy",
    "target_armor": "cel: czołg",
}


def magentanness(px):
    """Jak bardzo piksel jest magentowy: im wyżej, tym pewniej tło."""
    r, g, b = px
    return min(r, b) - g


def cut_background(image):
    rgba = image.convert("RGBA")
    pixels = list(rgba.getdata())
    out = []
    for (r, g, b, _a) in pixels:
        m = min(r, b) - g
        if m <= KEY_SOFT:
            alpha = 255
        elif m >= KEY_HARD:
            alpha = 0
        else:
            alpha = int(255 * (1.0 - (m - KEY_SOFT) / (KEY_HARD - KEY_SOFT)))
        if alpha > 0:
            # Usunięcie różowej obwódki: zielony nie może być niższy niż reszta.
            floor_g = int((r + b) * 0.5)
            if g < floor_g:
                g = min(255, floor_g)
        out.append((r, g, b, alpha))
    rgba.putdata(out)
    return rgba


def trim_and_scale(rgba):
    bbox = rgba.getbbox()
    if bbox is None:
        return rgba
    content = rgba.crop(bbox)
    side = max(content.width, content.height)
    padded = int(round(side * (1.0 + 2.0 * PAD_RATIO)))
    canvas = Image.new("RGBA", (padded, padded), (0, 0, 0, 0))
    canvas.paste(content, ((padded - content.width) // 2, (padded - content.height) // 2))
    return canvas.resize((SIZE, SIZE), Image.LANCZOS)


def process(key, raw_path, out_dir):
    image = Image.open(raw_path)
    rgba = trim_and_scale(cut_background(image))
    path = out_dir / f"{key}.png"
    rgba.save(path, "PNG", optimize=True)

    # Ile pikseli zostaje po wycięciu tła — sanity check, czy klucz zadziałał.
    alpha = rgba.getchannel("A")
    opaque = sum(1 for v in alpha.getdata() if v > 128)
    share = 100.0 * opaque / (SIZE * SIZE)
    print(f"{key:16s} {HUD[key]:18s} treść {share:5.1f}% kadru  "
          f"{path.stat().st_size // 1024:3d} kB")


def main():
    parser = argparse.ArgumentParser(description="Wycina tło ikon HUD i zapisuje je jako RGBA PNG.")
    parser.add_argument("--raw", required=True, help="katalog z surowymi obrazami <klucz>.png")
    parser.add_argument("--out", default=str(DEFAULT_OUT), help="katalog docelowy")
    args = parser.parse_args()

    raw_dir = pathlib.Path(args.raw)
    out_dir = pathlib.Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)

    done, missing = [], []
    for key in HUD:
        raw = raw_dir / f"{key}.png"
        if raw.exists():
            process(key, raw, out_dir)
            done.append(key)
        else:
            missing.append(key)
    print(f"\ngotowe: {len(done)}/{len(HUD)}")
    if missing:
        print("brakuje surowych plików: " + ", ".join(missing))


if __name__ == "__main__":
    main()
