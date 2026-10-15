#!/usr/bin/env python3
"""Podglądy tekstur terenu: arkusz kontaktowy i makieta mapy kampanii.

Użycie:
    python3 tools/art/preview_terrain.py [--out /tmp/art/out] [--seed 1]

Tworzy:
    arkusz_tekstur.png — wszystkie 13 tekstur z paletą i rozmiarami,
    mapa_seed<seed>.png — prawdziwą mapę 60×40 z tests/ref_map.json złożoną
      z nowych kafli, z miastami, polem startowym i legendą.

Dzięki temu widać efekt bez uruchamiania Godota (środowisko bez okna graficznego).
Wymaga Pillow.
"""

import argparse
import base64
import json
import pathlib
from PIL import Image, ImageDraw, ImageFont

PROJECT = pathlib.Path(__file__).resolve().parents[2]
TERRAIN = PROJECT / "assets" / "textures" / "terrain"
TILES = TERRAIN / "tiles"

FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
FONT_BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"

# Kolejność jak enum Terrain.Kind w scripts/logic/terrain.gd.
KINDS = [
    ("plains", "równina"), ("forest", "las"), ("hills", "wzgórza"),
    ("mountain", "góry"), ("marsh", "bagno"), ("river", "rzeka"),
    ("ford", "bród"), ("lake", "jezioro"), ("city", "miasto"),
    ("road", "droga"), ("bridge", "most"), ("sand", "piasek"),
    ("snow", "śnieg"),
]
PALETTE = {
    "plains": (107, 140, 79), "forest": (46, 92, 51), "hills": (133, 115, 82),
    "mountain": (107, 102, 97), "marsh": (76, 102, 87), "river": (51, 97, 158),
    "ford": (102, 153, 199), "lake": (41, 71, 128), "city": (184, 168, 140),
    "road": (158, 143, 107), "bridge": (179, 148, 97), "sand": (204, 189, 133),
    "snow": (235, 240, 247),
}

BG = (24, 26, 30)
FG = (232, 236, 240)
DIM = (150, 158, 168)
PLACEHOLDER = (210, 170, 90)


def has(key):
    return (TILES / f"{key}.png").exists()


def load(key, size=None):
    path = TERRAIN / f"{key}.png"
    if not path.exists():
        return None
    img = Image.open(path).convert("RGB")
    return img.resize((size, size), Image.LANCZOS) if size else img


def contact_sheet(out_dir):
    cell, pad, label_h, cols, head = 300, 18, 54, 3, 120
    rows = (len(KINDS) + cols - 1) // cols
    sheet = Image.new("RGB", (pad + cols * (cell + pad), head + pad + rows * (cell + label_h + pad)), BG)
    draw = ImageDraw.Draw(sheet)
    f_title = ImageFont.truetype(FONT_BOLD, 40)
    f_sub = ImageFont.truetype(FONT, 19)
    f_name = ImageFont.truetype(FONT_BOLD, 26)
    f_num = ImageFont.truetype(FONT, 19)

    draw.text((pad + 4, 26), "Zimna Wojna 1975 — tekstury terenu (AI)", font=f_title, fill=FG)
    draw.text((pad + 6, 78),
              "hand-painted map texture · 512×512 (materiały 3D) + 64×64 (kafle mapy) · "
              "paleta z campaign_view.gd", font=f_sub, fill=DIM)

    for index, (key, name) in enumerate(KINDS):
        x = pad + (index % cols) * (cell + pad)
        y = head + pad + (index // cols) * (cell + label_h + pad)
        texture = load(key, cell)
        if texture is None:
            draw.rectangle([x, y, x + cell, y + cell], fill=PALETTE[key])
            draw.text((x + 14, y + 14), "BRAK — do wygenerowania", font=f_num, fill=(30, 30, 30))
        else:
            sheet.paste(texture, (x, y))
        draw.rectangle([x, y, x + cell - 1, y + cell - 1], outline=(70, 74, 80))
        draw.text((x + 2, y + cell + 8), f"{name}  ·  {key}", font=f_name, fill=FG)
        rgb = PALETTE[key]
        draw.text((x + 2, y + cell + 34),
                  f"paleta #{rgb[0]:02X}{rgb[1]:02X}{rgb[2]:02X} · "
                  f"{'512+64 px' if has(key) else 'kolor zastępczy'}", font=f_num, fill=DIM)

    path = out_dir / "arkusz_tekstur.png"
    sheet.save(path, "PNG")
    print(f"arkusz: {path} ({path.stat().st_size // 1024} kB, {sheet.width}×{sheet.height})")


def campaign_map_preview(out_dir, seed):
    data = json.loads((PROJECT / "tests/ref_map.json").read_text())
    key_seed = str(seed)
    if key_seed not in data["seeds"]:
        raise SystemExit(f"ref_map.json nie ma seeda {key_seed} (są: {', '.join(data['seeds'])})")
    entry = data["seeds"][key_seed]
    tiles = base64.b64decode(entry["tiles"])
    w, h, scale = int(data["w"]), int(data["h"]), 16

    map_img = Image.new("RGB", (w * scale, h * scale), BG)
    cache = {}
    for key, _ in KINDS:
        img = load(key, scale)
        if img is not None:
            cache[key] = img
    draw = ImageDraw.Draw(map_img)
    for y in range(h):
        for x in range(w):
            kind = tiles[y * w + x]
            key = KINDS[kind][0] if kind < len(KINDS) else "plains"
            if key in cache:
                map_img.paste(cache[key], (x * scale, y * scale))
            else:
                draw.rectangle([x * scale, y * scale, x * scale + scale - 1, y * scale + scale - 1],
                               fill=PALETTE[key])

    f_small = ImageFont.truetype(FONT_BOLD, 11)
    f_mark = ImageFont.truetype(FONT_BOLD, 13)
    for city in entry["cities"]:
        cx, cy = int(city["x"]) * scale, int(city["y"]) * scale
        draw.rectangle([cx + 1, cy + 1, cx + scale - 2, cy + scale - 2], outline=(250, 245, 210), width=1)
        draw.text((cx + 2, cy - 12), city["name"], font=f_small, fill=(252, 250, 235),
                  stroke_width=2, stroke_fill=(20, 20, 20))
    sx, sy = int(entry["start"][0]), int(entry["start"][1])
    draw.ellipse([sx * scale - 4, sy * scale - 4, sx * scale + scale + 4, sy * scale + scale + 4],
                 outline=(90, 240, 120), width=3)
    draw.text((sx * scale + 2, sy * scale + scale + 4), "start", font=f_mark, fill=(140, 250, 160),
              stroke_width=2, stroke_fill=(15, 15, 15))

    legend_w, head = 330, 96
    canvas = Image.new("RGB", (map_img.width + legend_w, map_img.height + head), BG)
    canvas.paste(map_img, (0, head))
    draw = ImageDraw.Draw(canvas)
    draw.text((16, 18), f"Mapa kampanii 60×40 — seed {seed}, kafle {scale} px",
              font=ImageFont.truetype(FONT_BOLD, 30), fill=FG)
    draw.text((16, 56), "prawdziwe dane z tests/ref_map.json, złożone z nowych tekstur",
              font=ImageFont.truetype(FONT, 17), fill=DIM)

    x0, y = map_img.width + 22, head + 20
    for key, name in KINDS:
        thumb = load(key, 34)
        if thumb is not None:
            canvas.paste(thumb, (x0, y))
        else:
            draw.rectangle([x0, y, x0 + 33, y + 33], fill=PALETTE[key])
        draw.rectangle([x0, y, x0 + 33, y + 33], outline=(70, 74, 80))
        draw.text((x0 + 46, y + 6), f"{name} · {key}", font=ImageFont.truetype(FONT_BOLD, 20), fill=FG)
        draw.text((x0 + 46, y + 28), "tekstura AI" if has(key) else "kolor zastępczy",
                  font=ImageFont.truetype(FONT, 16), fill=DIM if has(key) else PLACEHOLDER)
        y += 46

    path = out_dir / f"mapa_seed{seed}.png"
    canvas.save(path, "PNG")
    print(f"mapa: {path} ({path.stat().st_size // 1024} kB, {canvas.width}×{canvas.height})")


def main():
    parser = argparse.ArgumentParser(description="Podglądy tekstur terenu (arkusz + mapa).")
    parser.add_argument("--out", default="/tmp/art/out")
    parser.add_argument("--seed", default="1")
    args = parser.parse_args()
    out_dir = pathlib.Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    contact_sheet(out_dir)
    campaign_map_preview(out_dir, args.seed)


if __name__ == "__main__":
    main()
