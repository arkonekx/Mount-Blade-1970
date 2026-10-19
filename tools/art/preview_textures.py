#!/usr/bin/env python3
"""Podglądy tekstur gry: arkusze kontaktowe i makiety.

Użycie:
    python3 tools/art/preview_textures.py [--out /tmp/art/out] [--seed 1]

Tworzy:
    arkusz_tekstur.png     — 13 tekstur terenu z paletą i rozmiarami,
    mapa_seed<seed>.png    — prawdziwą mapę 60×40 z tests/ref_map.json złożoną
                             z kafli gry, z miastami, polem startowym i legendą,
    arkusz_otoczenia.png   — 5 tekstur otoczenia bitwy,
    makieta_otoczenia.png  — makieta brył (drzewo, skała, blok) z tymi teksturami,
                             żeby było widać, jak siadają na obiektach 3D,
    makieta_pojazdow.png   — rzut z boku prawdziwych brył pojazdów z gry
                             (dane z tools/godot/dump_meshes.gd).

Dzięki temu widać efekt bez uruchamiania Godota (środowisko bez okna graficznego).
Wymaga Pillow.
"""

import argparse
import base64
import json
import pathlib
from PIL import Image, ImageDraw, ImageFont

# oznaczenia na pancerzu: bryły z tymi teksturami rysujemy jako gwiazdę,
# nie jako prostokąt (makieta nie próbkuje tekstur)
STAR_TEX = {"star_us": (246, 247, 242), "star_su": (198, 44, 38)}


def _star_points(cx, cy, r, inner=0.42):
    """Wierzchołki pięcioramiennej gwiazdy (10 punktów, na przemian R i r)."""
    import math
    pts = []
    for i in range(10):
        ang = -math.pi / 2 + i * math.pi / 5
        rad = r if i % 2 == 0 else r * inner
        pts.append((cx + rad * math.cos(ang), cy + rad * math.sin(ang)))
    return pts

PROJECT = pathlib.Path(__file__).resolve().parents[2]
TERRAIN = PROJECT / "assets" / "textures" / "terrain"
TILES = TERRAIN / "tiles"
PROPS = PROJECT / "assets" / "textures" / "props"
UNITS = PROJECT / "assets" / "textures" / "units"
ICONS = PROJECT / "assets" / "textures" / "icons"

# Kolory stron z battle_view.gd — tekstury sprzętu są mnożone przez ten kolor.
SIDE_COLORS = [("gracz", (0.25, 0.90, 0.35)), ("sojusznik", (0.25, 0.45, 0.90)), ("wróg", (0.85, 0.20, 0.20))]
UNIT_KINDS = [("uniform", "mundur piechoty"), ("armor", "pancerz pojazdu")]
ICON_KINDS = [
    ("player", "gracz"), ("enemy", "wróg"), ("objective", "cel"),
    ("city", "miasto"), ("boat", "łódź"), ("scout", "zwiadowca"),
]

# Klucze i kolory otoczenia — jak w tools/art/process_props.py i game_textures.gd.
PROP_KINDS = [
    ("tree_bark", "kora pnia", "pnie drzew"),
    ("tree_canopy", "korona drzewa", "korony drzew"),
    ("rock", "skała", "skały i głazy"),
    ("wall", "ściana bloku", "bloki miejskie"),
    ("roof", "dach", "dachy bloków"),
]
PROP_PALETTE = {
    "tree_bark": (87, 69, 51), "tree_canopy": (38, 64, 36), "rock": (122, 120, 115),
    "wall": (148, 145, 138), "roof": (97, 97, 99),
}

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


def load_prop(key, size=None):
    path = PROPS / f"{key}.png"
    if not path.exists():
        return None
    img = Image.open(path).convert("RGB")
    return img.resize((size, size), Image.LANCZOS) if size else img


def props_sheet(out_dir):
    """Arkusz kontaktowy tekstur otoczenia bitwy (256×256)."""
    cell, pad, label_h, cols, head = 300, 18, 54, 3, 120
    rows = (len(PROP_KINDS) + cols - 1) // cols
    sheet = Image.new("RGB", (pad + cols * (cell + pad), head + pad + rows * (cell + label_h + pad)), BG)
    draw = ImageDraw.Draw(sheet)
    draw.text((pad + 4, 26), "Zimna Wojna 1975 — otoczenie bitwy (AI)", font=ImageFont.truetype(FONT_BOLD, 36), fill=FG)
    draw.text((pad + 6, 78), "hand-painted surface texture · 256×256 · materiały brył 3D "
                             "(drzewa, skały, budynki)", font=ImageFont.truetype(FONT, 19), fill=DIM)

    for index, (key, name, usage) in enumerate(PROP_KINDS):
        x = pad + (index % cols) * (cell + pad)
        y = head + pad + (index // cols) * (cell + label_h + pad)
        texture = load_prop(key, cell)
        if texture is None:
            draw.rectangle([x, y, x + cell, y + cell], fill=PROP_PALETTE[key])
            draw.text((x + 14, y + 14), "BRAK — do wygenerowania", font=ImageFont.truetype(FONT, 19), fill=(30, 30, 30))
        else:
            sheet.paste(texture, (x, y))
        draw.rectangle([x, y, x + cell - 1, y + cell - 1], outline=(70, 74, 80))
        draw.text((x + 2, y + cell + 8), f"{name}  ·  {key}", font=ImageFont.truetype(FONT_BOLD, 25), fill=FG)
        rgb = PROP_PALETTE[key]
        draw.text((x + 2, y + cell + 34),
                  f"#{rgb[0]:02X}{rgb[1]:02X}{rgb[2]:02X} · {usage} · "
                  f"{'256 px' if texture else 'brak'}", font=ImageFont.truetype(FONT, 18), fill=DIM)

    path = out_dir / "arkusz_otoczenia.png"
    sheet.save(path, "PNG")
    print(f"arkusz otoczenia: {path} ({path.stat().st_size // 1024} kB, {sheet.width}×{sheet.height})")


def _textured_ellipse(canvas, box, texture, size_hint=120):
    mask = Image.new("L", (box[2] - box[0], box[3] - box[1]), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, mask.width - 1, mask.height - 1], fill=255)
    canvas.paste(load_prop(texture, size_hint).resize((mask.width, mask.height), Image.LANCZOS),
                 (box[0], box[1]), mask)


def _textured_rect(canvas, box, texture, rounded=True):
    mask = Image.new("L", (box[2] - box[0], box[3] - box[1]), 0)
    pen = ImageDraw.Draw(mask)
    if rounded:
        pen.rounded_rectangle([0, 0, mask.width - 1, mask.height - 1], radius=min(6, mask.height // 4), fill=255)
    else:
        pen.rectangle([0, 0, mask.width - 1, mask.height - 1], fill=255)
    canvas.paste(load_prop(texture, 160).resize((mask.width, mask.height), Image.LANCZOS),
                 (box[0], box[1]), mask)


def props_mock(out_dir):
    """Makieta: te same tekstury na bryłach, które buduje battle_view.gd."""
    w, h, head = 1000, 520, 110
    canvas = Image.new("RGB", (w, h), BG)
    draw = ImageDraw.Draw(canvas)
    draw.text((22, 22), "Makieta otoczenia bitwy — tekstury na bryłach z battle_view.gd",
              font=ImageFont.truetype(FONT_BOLD, 30), fill=FG)
    draw.text((24, 64), "drzewo: walec (kora) + kula (korona) · skała: kula (skała) · "
                        "blok: prostopadłościan (ściana) + płaski dach",
              font=ImageFont.truetype(FONT, 18), fill=DIM)

    scene_y = head + 30
    ground = load("plains", 64)
    if ground is not None:
        for gy in range(scene_y, h, 64):
            for gx in range(0, w, 64):
                canvas.paste(ground, (gx, gy))

    # drzewa: pień + korona
    for tx, scale in ((120, 1.0), (330, 0.8), (250, 1.25)):
        trunk_h = int(150 * scale)
        trunk_w = int(18 * scale)
        _textured_rect(canvas, (tx, scene_y + 200 - trunk_h, tx + trunk_w, scene_y + 210), "tree_bark")
        _textured_ellipse(canvas, (tx - int(52 * scale), scene_y + 200 - trunk_h - int(46 * scale),
                                   tx + trunk_w + int(52 * scale), scene_y + 200 - trunk_h + int(52 * scale)),
                          "tree_canopy")

    # skała i głaz
    _textured_ellipse(canvas, (560, scene_y + 130, 720, scene_y + 230), "rock")
    _textured_ellipse(canvas, (700, scene_y + 170, 790, scene_y + 232), "rock", 90)

    # blok miejski: ściana + dach
    _textured_rect(canvas, (812, scene_y + 30, 960, scene_y + 210), "wall", rounded=False)
    _textured_rect(canvas, (806, scene_y + 18, 966, scene_y + 34), "roof", rounded=False)

    draw.rectangle([0, scene_y - 1, w - 1, scene_y], fill=(60, 64, 70))
    for cx, label in ((60, "drzewo (las)"), (560, "skały (wzgórza)"), (806, "blok (miasto)"),
                      (0, "")):
        if label:
            draw.text((cx, h - 34), label, font=ImageFont.truetype(FONT_BOLD, 20), fill=FG)

    path = out_dir / "makieta_otoczenia.png"
    canvas.save(path, "PNG")
    print(f"makieta otoczenia: {path} ({path.stat().st_size // 1024} kB, {canvas.width}×{canvas.height})")


def load_unit(key, size=None):
    path = UNITS / f"{key}.png"
    if not path.exists():
        return None
    img = Image.open(path).convert("RGB")
    return img.resize((size, size), Image.LANCZOS) if size else img


def load_icon(key, size=None):
    path = ICONS / f"{key}.png"
    if not path.exists():
        return None
    img = Image.open(path).convert("RGBA")
    return img.resize((size, size), Image.LANCZOS) if size else img


def units_sheet(out_dir):
    """Tekstury sprzętu: sam detal i ten sam detal w barwach trzech stron."""
    cell, pad, label_h, head = 260, 16, 46, 190
    tiles = 1 + len(SIDE_COLORS)
    width = pad + tiles * (cell + pad)
    height = head + 2 * (cell + label_h + pad)
    sheet = Image.new("RGB", (width, height), BG)
    draw = ImageDraw.Draw(sheet)
    draw.text((pad + 4, 22), "Zimna Wojna 1975 — jednostki i pojazdy (AI)",
              font=ImageFont.truetype(FONT_BOLD, 34), fill=FG)
    draw.text((pad + 6, 68), "256×256 · jasna, neutralna tekstura × kolor strony "
                             "(Godot mnoży albedo_color przez teksturę)",
              font=ImageFont.truetype(FONT, 18), fill=DIM)
    for i, (label, rgb) in enumerate(SIDE_COLORS):
        x = pad + (i + 1) * (cell + pad)
        draw.rectangle([x, 104, x + 22, 126], fill=tuple(round(c * 255) for c in rgb))
        draw.text((x + 30, 104), f"barwa: {label}", font=ImageFont.truetype(FONT_BOLD, 19), fill=FG)

    for row, (key, name) in enumerate(UNIT_KINDS):
        texture = load_unit(key, cell)
        y = head + row * (cell + label_h + pad)
        if texture is not None:
            sheet.paste(texture, (pad, y))
            draw.rectangle([pad, y, pad + cell - 1, y + cell - 1], outline=(70, 74, 80))
            draw.text((pad + 2, y + cell + 8), f"{name} · {key} (bez barwy)",
                      font=ImageFont.truetype(FONT_BOLD, 20), fill=FG)
        for i, (label, rgb) in enumerate(SIDE_COLORS):
            x = pad + (i + 1) * (cell + pad)
            if texture is None:
                draw.rectangle([x, y, x + cell, y + cell], fill=tuple(round(c * 200) for c in rgb))
                continue
            tint = Image.new("RGB", texture.size, tuple(round(c * 255) for c in rgb))
            from PIL import ImageChops
            tinted = ImageChops.multiply(texture, tint)
            sheet.paste(tinted, (x, y))
            draw.rectangle([x, y, x + cell - 1, y + cell - 1], outline=(70, 74, 80))
            draw.text((x + 2, y + cell + 8), f"{name} · {label}", font=ImageFont.truetype(FONT, 19), fill=DIM)

    path = out_dir / "arkusz_jednostek.png"
    sheet.save(path, "PNG")
    print(f"arkusz jednostek: {path} ({path.stat().st_size // 1024} kB, {sheet.width}×{sheet.height})")


def icons_sheet(out_dir):
    """Ikony: w rozmiarze docelowym i tak, jak trafiają na mapę (24 i 16 px)."""
    big, small_a, small_b = 128, 24, 16
    pad, head = 18, 150
    cell_w = big + 30
    cell_h = big + 104
    cols = 3
    rows = (len(ICON_KINDS) + cols - 1) // cols
    sheet = Image.new("RGB", (pad + cols * (cell_w + pad), head + rows * (cell_h + pad)), BG)
    draw = ImageDraw.Draw(sheet)
    draw.text((pad + 4, 22), "Zimna Wojna 1975 — ikony interfejsu (AI)",
              font=ImageFont.truetype(FONT_BOLD, 34), fill=FG)
    draw.text((pad + 6, 66), "128×128 z przezroczystością · wycięte z magentowego tła · "
                             "poniżej podgląd w skali mapy (24 i 16 px na tle terenu)",
              font=ImageFont.truetype(FONT, 18), fill=DIM)

    # pasek tła terenu, żeby ocenić kontrast ikon w skali mapy
    strip = load("plains", 32)
    if strip is not None:
        for sx in range(pad, sheet.width - pad, 32):
            sheet.paste(strip, (sx, 104))

    for index, (key, name) in enumerate(ICON_KINDS):
        col = index % cols
        row = index // cols
        x = pad + col * (cell_w + pad)
        y = head + row * (cell_h + pad)
        icon = load_icon(key, big)
        draw.rectangle([x, y, x + big - 1, y + big - 1], fill=(16, 18, 22))
        if icon is not None:
            sheet.paste(icon, (x, y), icon)
        else:
            draw.text((x + 10, y + 10), "BRAK", font=ImageFont.truetype(FONT, 20), fill=(210, 170, 90))
        draw.text((x + 2, y + big + 6), f"{name} · {key}", font=ImageFont.truetype(FONT_BOLD, 24), fill=FG)
        for i, size in enumerate((small_a, small_b)):
            thumb = load_icon(key, size)
            if thumb is not None:
                sheet.paste(thumb, (x + 2 + i * 46, y + big + 44), thumb)
        draw.text((x + 104, y + big + 50), "24 px · 16 px (skala mapy)",
                  font=ImageFont.truetype(FONT, 17), fill=DIM)

    path = out_dir / "arkusz_ikon.png"
    sheet.save(path, "PNG")
    print(f"arkusz ikon: {path} ({path.stat().st_size // 1024} kB, {sheet.width}×{sheet.height})")


def _tinted(texture, color):
    """Tekstura przemnożona przez kolor strony (jak albedo_color w Godocie)."""
    from PIL import ImageChops
    tint = Image.new("RGB", texture.size, tuple(round(c * 255) for c in color))
    return ImageChops.multiply(texture.convert("RGB"), tint)


def _draw_textured(canvas, shape, texture, points, color=(1.0, 1.0, 1.0), outline=(20, 22, 26), width=2):
    """Rysuje bryłę: kształt wycięty z maski wypełniony teksturą w danym kolorze.

    points: dla „rect” i „ellipse” dwa narożniki, dla „poly” lista wierzchołków.
    """
    if shape == "poly":
        xs = [pt[0] for pt in points]
        ys = [pt[1] for pt in points]
        x0, y0 = int(min(xs)), int(min(ys))
        x1, y1 = int(max(xs)) + 1, int(max(ys)) + 1
    else:
        # Kolejność narożników nie ma znaczenia — sortujemy.
        xs = sorted((points[0][0], points[1][0]))
        ys = sorted((points[0][1], points[1][1]))
        x0, y0 = int(round(xs[0])), int(round(ys[0]))
        x1, y1 = int(round(xs[1])), int(round(ys[1]))
    mask = Image.new("L", (max(1, x1 - x0), max(1, y1 - y0)), 0)
    pen = ImageDraw.Draw(mask)
    if shape == "rect":
        pen.rectangle([0, 0, mask.width - 1, mask.height - 1], fill=255)
    elif shape == "ellipse":
        pen.ellipse([0, 0, mask.width - 1, mask.height - 1], fill=255)
    else:
        pen.polygon([(pt[0] - x0, pt[1] - y0) for pt in points], fill=255)

    tile = _tinted(texture, color).resize((mask.width, mask.height), Image.LANCZOS)
    canvas.paste(tile, (x0, y0), mask)

    draw = ImageDraw.Draw(canvas)
    if shape == "rect":
        draw.rectangle([x0, y0, x1 - 1, y1 - 1], outline=outline, width=width)
    elif shape == "ellipse":
        draw.ellipse([x0, y0, x1 - 1, y1 - 1], outline=outline, width=width)
    else:
        loop = points + [points[0]]
        draw.line([tuple(pt) for pt in loop], fill=outline, width=width)


def _load_units_json(meshes_path):
    """Geometria jednostek zrzucona z gry (tools/godot/dump_meshes.gd)."""
    path = pathlib.Path(meshes_path)
    if not path.exists():
        return None
    data = json.loads(path.read_text())
    units = {}
    for u in data["units"]:
        # klucz podstawowy: identyfikator jednostki z units_data.gd,
        # zapasowy: para (klasa, strona) — na wypadek starszego dumpu
        units[str(u.get("def_id") or u.get("name") or "")] = u
        units.setdefault((str(u["cls"]), str(u["side"])), u)
    return units


def _unit_extents(unit):
    """Wymiary brył jednostki: długość, wysokość całkowita i wysokość kadłuba.

    „Wysokość do wieży” to wysokość bez cienkich elementów (anteny, pręty):
    bryła liczy się tylko wtedy, gdy jej najmniejszy wymiar ma co najmniej
    0,4 m — czyli gdy to naprawdę korpus, wieża albo koło, a nie maszt anteny.
    """
    def size_of(mesh):
        prim = mesh["prim"]
        if prim == "box":
            return mesh["size"]
        if prim in ("cylinder", "capsule"):
            return [mesh["bottom_radius"] * 2, mesh["height"], mesh["bottom_radius"] * 2]
        if prim == "sphere":
            return [mesh["radius"] * 2] * 3
        return [0.0, 0.0, 0.0]

    x_min, x_max = 0.0, 0.0
    height = 0.0
    hull = 0.0
    for mesh in unit["meshes"]:
        size = size_of(mesh)
        pos = mesh["position"]
        x_min = min(x_min, pos[0] - size[0] * 0.5)
        x_max = max(x_max, pos[0] + size[0] * 0.5)
        top = pos[1] + size[1] * 0.5
        height = max(height, top)
        if min(size) >= 0.4:
            hull = max(hull, top)
    return x_max - x_min, height, hull


def vehicles_mock(out_dir, meshes_path="/tmp/art/units.json"):
    """Rzut techniczny brył pojazdów — prosto z geometrii, którą buduje gra.

    Rysujemy prawdziwe bryły z `dump_meshes.gd` (rzut ortograficzny z boku),
    więc schemat nie może się rozjechać z kodem: każda nowa bryła w
    `battle_view.gd` pojawia się tu sama.
    """
    units = _load_units_json(meshes_path)
    if units is None:
        print(f"makieta pojazdów: brak {meshes_path} (uruchom najpierw dump_meshes.gd — pominięto)")
        return

    import sys
    sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
    import render_units as RU

    ppm = 46.0                      # pikseli na metr
    w, h = 1480, 750
    BG2 = (18, 20, 24)
    FG2 = (232, 236, 240)
    DIM2 = (150, 158, 168)
    GROUND = (52, 56, 64)

    canvas = Image.new("RGB", (w, h), BG2)
    draw = ImageDraw.Draw(canvas)
    draw.text((22, 18), "Makieta pojazdów — bryły z battle_view.gd, rzut z boku",
              font=ImageFont.truetype(FONT_BOLD, 30), fill=FG2)
    draw.text((24, 56), "prawdziwa geometria z gry (tools/godot/dump_meshes.gd) · wspólna skala · "
                        "obrys = pojedyncza bryła · gwiazda = oznaczenie na pancerzu",
              font=ImageFont.truetype(FONT, 17), fill=DIM2)

    def draw_unit(unit, center_x, base_y):
        """Rysuje jednostkę wyśrodkowaną w kolumnie; zwraca liczniki brył."""
        tris = RU.unit_triangles(unit)
        xs = [float(v[0]) for t in tris for v in t[0]]
        zs = [float(v[2]) for t in tris for v in t[0]]
        cx = (max(xs) + min(xs)) * 0.5
        z_mid = (max(zs) + min(zs)) * 0.5
        z_half = max(1e-4, (max(zs) - min(zs)) * 0.5)

        def px(x):
            return center_x + (x - cx) * ppm

        def py(y):
            return base_y - y * ppm

        # od najdalszych brył do najbliższych, żeby bliższy bok zasłaniał dalszy
        for verts, _uvs, tex, albedo in sorted(tris, key=lambda t: sum(v[2] for v in t[0])):
            if tex in STAR_TEX:
                continue               # oznaczenia rysujemy jako gwiazdę, patrz niżej
            depth = sum(v[2] for v in verts) / 3.0
            shade = 0.74 + 0.26 * (depth - (z_mid - z_half)) / (2 * z_half)
            color = tuple(int(max(0, min(255, c * 255 * shade))) for c in albedo[:3])
            edge = tuple(int(c * 0.42) for c in color)
            draw.polygon([(px(float(v[0])), py(float(v[1]))) for v in verts], fill=color, outline=edge)
        # Jedna gwiazda na płytkę oznaczenia. W rzucie z boku widać tylko
        # gwiazdy na burtach — płyty na dachu i na tyle są tu krawędzią.
        for mesh in unit["meshes"]:
            tex = mesh.get("texture")
            if tex not in STAR_TEX or abs(float(mesh["position"][2])) < 0.5:
                continue
            size = [float(v) for v in mesh["size"]]
            r = max(4.5, min(15.0, 0.45 * max(size[0], size[1]) * ppm))
            draw.polygon(_star_points(px(float(mesh["position"][0])),
                                      py(float(mesh["position"][1])), r),
                         fill=STAR_TEX[tex], outline=(24, 24, 24))
        belts = sum(1 for m in unit["meshes"] if m.get("texture") == "track")
        return belts

    def fill(text, x, y, font, color, anchor="ma"):
        draw.text((x, y), text, font=ImageFont.truetype(font, 15 if font == FONT else 19),
                  fill=color, anchor=anchor)

    def ruler(x0, y):
        """Podziałka: kreska co 1 m."""
        for step in range(4):
            x = x0 + step * ppm
            draw.line([(x, y - 4), (x, y + 4)], fill=GROUND, width=2)
        draw.line([(x0, y), (x0 + 3 * ppm, y)], fill=GROUND, width=2)
        draw.text((x0, y + 8), "0", font=ImageFont.truetype(FONT, 14), fill=DIM2)
        draw.text((x0 + 3 * ppm, y + 8), "3 m", font=ImageFont.truetype(FONT, 14), fill=DIM2, anchor="ma")

    rows = [
        (380, [(330, "us_arm_m60a1", "czołg NATO — M60A1 (1024 bryły)"),
               (1000, "su_arm_t62", "czołg ZSRR — T-62 Obr. 1972 (1024 bryły)")]),
        (665, [(330, "us_mech_m113", "wóz bojowy NATO — M113 (1024 bryły)"),
               (1000, "su_mech_bmp1", "wóz bojowy ZSRR — BMP-1 (1024 bryły)")]),
    ]
    for base_y, entries in rows:
        draw.line([(20, base_y), (w - 20, base_y)], fill=GROUND, width=2)
        for center_x, def_id, caption in entries:
            unit = units.get(def_id)
            if unit is None:
                continue
            belts = draw_unit(unit, center_x, base_y)
            length, height, hull = _unit_extents(unit)
            draw.text((center_x, base_y + 16), caption,
                      font=ImageFont.truetype(FONT_BOLD, 19), fill=FG2, anchor="ma")
            draw.text((center_x, base_y + 44),
                      f"dł. {length:.1f} m · wys. do wieży {hull:.1f} m · z antenami {height:.1f} m · "
                      f"{belts} ogniw i kół",
                      font=ImageFont.truetype(FONT, 15), fill=DIM2, anchor="ma")
        ruler(60, base_y - 150)

    infantry = units.get("us_inf_m16")
    if infantry is not None:
        base_y = 665
        draw_unit(infantry, 1390, base_y)
        for line, font, dy in ((f"piechur · {len(infantry['meshes'])} brył", FONT_BOLD, 16),
                               ("dla skali: kapsuła, hełm,", FONT, 44),
                               ("plecak, kończyny, karabin", FONT, 62)):
            draw.text((1462, base_y + dy), line,
                      font=ImageFont.truetype(font, 15 if font == FONT else 19),
                      fill=FG2 if font == FONT_BOLD else DIM2, anchor="ra")

    path = out_dir / "makieta_pojazdow.png"
    canvas.save(path, "PNG")
    print(f"makieta pojazdów: {path} ({path.stat().st_size // 1024} kB, {canvas.width}×{canvas.height})")


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
              "hand-painted map texture · 512×512 (materiały 3D) + 16×16 (kafle mapy) · "
              "paleta i kolor wymuszony programowo", font=f_sub, fill=DIM)

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
                  f"{'512 + 16 px' if has(key) else 'kolor zastępczy'}", font=f_num, fill=DIM)

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
        tile_path = TILES / f"{key}.png"
        if tile_path.exists():
            cache[key] = Image.open(tile_path).convert("RGB")  # dokładnie plik z gry
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

    # Ikony AI nanoszone tak, jak robi to campaign_view.gd (miasta, gracz, wrogowie).
    def paste_icon(key, cell_x, cell_y, size):
        icon = load_icon(key, size)
        if icon is None:
            return False
        x = cell_x * scale + (scale - size) // 2
        y = cell_y * scale + (scale - size) // 2
        map_img.paste(icon, (x, y), icon)
        return True

    for city in entry["cities"]:
        cx, cy = int(city["x"]) * scale, int(city["y"]) * scale
        paste_icon("city", int(city["x"]), int(city["y"]), scale + 6)
        draw.text((cx + 2, cy - 12), city["name"], font=f_small, fill=(252, 250, 235),
                  stroke_width=2, stroke_fill=(20, 20, 20))

    # przykładowe znaczniki: wrogowie i zwiadowca (żeby pokazać zestaw ikon)
    demo_marks = [("enemy", 34, 12), ("enemy", 47, 33), ("scout", 26, 30)]
    for key, gx, gy in demo_marks:
        paste_icon(key, gx, gy, scale + 4)

    sx, sy = int(entry["start"][0]), int(entry["start"][1])
    draw.ellipse([sx * scale - 4, sy * scale - 4, sx * scale + scale + 4, sy * scale + scale + 4],
                 outline=(90, 240, 120), width=2)
    paste_icon("player", sx, sy, scale + 8)
    draw.text((sx * scale + 2, sy * scale + scale + 4), "start", font=f_mark, fill=(140, 250, 160),
              stroke_width=2, stroke_fill=(15, 15, 15))

    legend_w, head = 330, 96
    canvas = Image.new("RGB", (map_img.width + legend_w, map_img.height + head), BG)
    canvas.paste(map_img, (0, head))
    draw = ImageDraw.Draw(canvas)
    draw.text((16, 18), f"Mapa kampanii 60×40 — seed {seed}, kafle {scale} px",
              font=ImageFont.truetype(FONT_BOLD, 30), fill=FG)
    draw.text((16, 56), "prawdziwe dane z tests/ref_map.json + tekstury i ikony AI "
                        "(wrogowie i zwiadowca to znaczniki przykładowe)",
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
    parser.add_argument("--meshes", default="/tmp/art/units.json",
                        help="geometria z tools/godot/dump_meshes.gd")
    args = parser.parse_args()
    out_dir = pathlib.Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    contact_sheet(out_dir)
    campaign_map_preview(out_dir, args.seed)
    props_sheet(out_dir)
    props_mock(out_dir)
    units_sheet(out_dir)
    icons_sheet(out_dir)
    vehicles_mock(out_dir, args.meshes)


if __name__ == "__main__":
    main()
