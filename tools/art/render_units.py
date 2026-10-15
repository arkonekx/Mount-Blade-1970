#!/usr/bin/env python3
"""Renderer jednostek: rysuje bryły Z GRY bez okna graficznego.

Skąd co pochodzi:

* **Geometria, kolory i tekstury** — z `tools/godot/dump_meshes.gd`, czyli
  dokładnie z tych funkcji, które budują świat bitwy (`_build_armor`,
  `_build_mech`, `_build_infantry` w `scripts/battle/battle_view.gd`).
  Rozmiary, pozycje, obroty, `albedo_color` i `uv1_scale` są 1:1 z gry.
* **Światło i rzut** — moje przybliżenie. W grze scenę oświetla kierunkowe
  słońce (obrót −55°, 35°) o energii 1,1 i światło otoczenia 0,9; tutaj liczę
  płaskie cieniowanie per ściana (`lambert`), więc wynik jest podobny, ale nie
  identyczny z tym, co robi Godot w trybie `gl_compatibility`.
* **Mapowanie UV** — odtworzone z typów siatek (BoxMesh, CylinderMesh,
  CapsuleMesh) i przemnożone przez `uv1_scale` jak w Godotcie. Kolejność
  ścian może się różnić od oryginału, więc to przybliżenie, nie kopia.

Użycie:
    python3 tools/art/render_units.py --meshes /tmp/art/units.json --out /tmp/art/out
"""

import argparse
import json
import math
import pathlib

import numpy as np
from PIL import Image, ImageDraw, ImageFont

PROJECT_ROOT = pathlib.Path(__file__).resolve().parents[2]
UNIT_TEXTURES = PROJECT_ROOT / "assets" / "textures" / "units"
TERRAIN_TEXTURES = PROJECT_ROOT / "assets" / "textures" / "terrain"

FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
FONT_BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"

# Oświetlenie wzorowane na battle_view.gd (dzień: słońce 1,1 + otoczenie 0,9),
# ale przeskalowane do sumy ≤ 1, bo Godot dodatkowo tonuje obraz, a mój renderer
# mnoży światło wprost. Kierunek słońca zostaje ten sam: obrót (-55°, 35°).
SUN_COLOR = np.array([1.0, 0.96, 0.88])
SUN_ROT_DEG = (-55.0, 35.0, 0.0)
AMBIENT_COLOR = np.array([0.70, 0.72, 0.78])
AMBIENT_LEVEL = 0.46      # udział światła otoczenia (w grze scena jest płaska i jasna)
SUN_LEVEL = 0.48          # udział słońca przy pełnym oświetleniu ściany
FILL_LEVEL = 0.30         # doświetlenie ścian odwróconych od słońca
SHADOW_STRENGTH = 0.42    # jak mocno cień przygasza grunt


# --- geometria ---------------------------------------------------------------


def euler_matrix(rx, ry, rz):
    """Macierz obrotu jak w Godotcie (kolejność YXZ)."""
    cx, sx = math.cos(rx), math.sin(rx)
    cy, sy = math.cos(ry), math.sin(ry)
    cz, sz = math.cos(rz), math.sin(rz)
    mx = np.array([[1, 0, 0], [0, cx, -sx], [0, sx, cx]])
    my = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]])
    mz = np.array([[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]])
    return my @ mx @ mz


def _quad(v0, v1, v2, v3, uv0, uv1, uv2, uv3):
    return [((v0, v1, v2), (uv0, uv1, uv2)), ((v0, v2, v3), (uv0, uv2, uv3))]


def box_triangles(size, uv_scale):
    """BoxMesh: 6 ścian; UV każdej ściany 0..1 × uv1_scale (jak w Godotcie)."""
    hx, hy, hz = size[0] * 0.5, size[1] * 0.5, size[2] * 0.5
    su, sv = uv_scale[0], uv_scale[1]
    tris = []
    # (oś normalna, znak) → dwie osie powierzchni (u, v)
    faces = [
        ((0, +1), (2, 1)),  # +X: u = z, v = y
        ((0, -1), (2, 1)),
        ((1, +1), (0, 2)),  # +Y: u = x, v = z
        ((1, -1), (0, 2)),
        ((2, +1), (0, 1)),  # +Z: u = x, v = y
        ((2, -1), (0, 1)),
    ]
    for (axis, sign), (ua, va) in faces:
        corners = []
        for uu, vv in ((0, 0), (1, 0), (1, 1), (0, 1)):
            p = [0.0, 0.0, 0.0]
            p[axis] = (hy if axis == 1 else (hz if axis == 2 else hx)) * sign
            ext_u = (hz if ua == 2 else (hy if ua == 1 else hx))
            ext_v = (hz if va == 2 else (hy if va == 1 else hx))
            p[ua] = (uu * 2.0 - 1.0) * ext_u
            p[va] = (vv * 2.0 - 1.0) * ext_v
            corners.append((np.array(p, dtype=float), np.array([uu * su, vv * sv])))
        verts = [c[0] for c in corners]
        uvs = [c[1] for c in corners]
        tris += _quad(verts[0], verts[3], verts[2], verts[1], uvs[0], uvs[3], uvs[2], uvs[1])
    return tris


def cylinder_triangles(top_r, bottom_r, height, segments, uv_scale):
    """CylinderMesh: płaszcz + dwa denka, oś w Y."""
    segments = max(3, int(segments))
    su, sv = uv_scale[0], uv_scale[1]
    tris = []
    hy = height * 0.5
    for i in range(segments):
        a0 = 2.0 * math.pi * i / segments
        a1 = 2.0 * math.pi * (i + 1) / segments
        x0, z0 = math.cos(a0), math.sin(a0)
        x1, z1 = math.cos(a1), math.sin(a1)
        b0 = np.array([x0 * bottom_r, -hy, z0 * bottom_r])
        b1 = np.array([x1 * bottom_r, -hy, z1 * bottom_r])
        t0 = np.array([x0 * top_r, hy, z0 * top_r])
        t1 = np.array([x1 * top_r, hy, z1 * top_r])
        u0, u1 = su * i / segments, su * (i + 1) / segments
        tris += _quad(b0, b1, t1, t0,
                      np.array([u0, 0.0]), np.array([u1, 0.0]),
                      np.array([u1, sv]), np.array([u0, sv]))
        # denka
        center_top = np.array([0.0, hy, 0.0])
        center_bottom = np.array([0.0, -hy, 0.0])
        uv_t0 = np.array([(x0 * 0.5 + 0.5) * su, (z0 * 0.5 + 0.5) * sv])
        uv_t1 = np.array([(x1 * 0.5 + 0.5) * su, (z1 * 0.5 + 0.5) * sv])
        uv_c = np.array([0.5 * su, 0.5 * sv])
        tris.append(((center_top, t1, t0), (uv_c, uv_t1, uv_t0)))
        tris.append(((center_bottom, b0, b1), (uv_c, uv_t0, uv_t1)))
    return tris


def capsule_triangles(radius, height, segments, rings, uv_scale):
    """CapsuleMesh: walec z półkulami, oś w Y (wysokość całkowita)."""
    segments = max(6, int(segments))
    rings = max(2, int(rings // 2))
    su, sv = uv_scale[0], uv_scale[1]
    half_cyl = max(0.0, height * 0.5 - radius)
    profile = []
    for i in range(rings + 1):                      # dolna półkula
        a = math.pi * 0.5 * i / rings
        profile.append((math.sin(a) * radius, -half_cyl - math.cos(a) * radius))
    for i in range(1, rings):                       # walec
        profile.append((radius, -half_cyl + 2.0 * half_cyl * i / float(rings)))
    for i in range(rings + 1):                      # górna półkula
        a = math.pi * 0.5 * i / rings
        profile.append((math.cos(a) * radius, half_cyl + math.sin(a) * radius))
    tris = []
    for i in range(len(profile) - 1):
        r0, y0 = profile[i]
        r1, y1 = profile[i + 1]
        v0 = sv * i / (len(profile) - 1)
        v1 = sv * (i + 1) / (len(profile) - 1)
        for s in range(segments):
            a0 = 2.0 * math.pi * s / segments
            a1 = 2.0 * math.pi * (s + 1) / segments
            u0, u1 = su * s / segments, su * (s + 1) / segments
            p00 = np.array([math.cos(a0) * r0, y0, math.sin(a0) * r0])
            p10 = np.array([math.cos(a1) * r0, y0, math.sin(a1) * r0])
            p11 = np.array([math.cos(a1) * r1, y1, math.sin(a1) * r1])
            p01 = np.array([math.cos(a0) * r1, y1, math.sin(a0) * r1])
            tris += _quad(p00, p10, p11, p01,
                          np.array([u0, v0]), np.array([u1, v0]),
                          np.array([u1, v1]), np.array([u0, v1]))
    return tris


def sphere_triangles(radius, segments, rings, uv_scale):
    segments = max(6, int(segments))
    rings = max(3, int(rings))
    su, sv = uv_scale[0], uv_scale[1]
    tris = []
    for i in range(rings):
        phi0 = math.pi * i / rings
        phi1 = math.pi * (i + 1) / rings
        for s in range(segments):
            t0 = 2.0 * math.pi * s / segments
            t1 = 2.0 * math.pi * (s + 1) / segments
            def point(phi, theta):
                return np.array([math.sin(phi) * math.cos(theta) * radius,
                                 math.cos(phi) * radius,
                                 math.sin(phi) * math.sin(theta) * radius])
            p00, p10 = point(phi0, t0), point(phi0, t1)
            p11, p01 = point(phi1, t1), point(phi1, t0)
            uv00 = np.array([su * s / segments, sv * i / rings])
            uv10 = np.array([su * (s + 1) / segments, sv * i / rings])
            uv11 = np.array([su * (s + 1) / segments, sv * (i + 1) / rings])
            uv01 = np.array([su * s / segments, sv * (i + 1) / rings])
            tris += _quad(p00, p10, p11, p01, uv00, uv10, uv11, uv01)
    return tris


def mesh_triangles(mesh):
    prim = mesh["prim"]
    uv_scale = mesh.get("uv_scale") or [1.0, 1.0, 1.0]
    if prim == "box":
        return box_triangles(mesh["size"], uv_scale)
    if prim == "cylinder":
        return cylinder_triangles(mesh["top_radius"], mesh["bottom_radius"],
                                  mesh["height"], mesh.get("radial_segments", 32), uv_scale)
    if prim == "capsule":
        return capsule_triangles(mesh["radius"], mesh["height"],
                                 mesh.get("radial_segments", 32), mesh.get("rings", 8), uv_scale)
    if prim == "sphere":
        return sphere_triangles(mesh["radius"], 32, 16, uv_scale)
    return []


def unit_triangles(unit):
    """Wszystkie trójkąty jednostki w układzie lokalnym + materiały."""
    out = []
    for mesh in unit["meshes"]:
        rot = euler_matrix(*mesh["rotation"])
        pos = np.array(mesh["position"], dtype=float)
        for verts, uvs in mesh_triangles(mesh):
            world = tuple(rot @ v + pos for v in verts)
            out.append((world, uvs, mesh.get("texture"), np.array(mesh.get("albedo", [1, 1, 1]), dtype=float)))
    return out


def ground_triangles(size=(120.0, 120.0), uv_scale=(40.0, 40.0)):
    w, h = size
    hw, hh = w * 0.5, h * 0.5
    verts = [np.array([-hw, 0.0, -hh]), np.array([hw, 0.0, -hh]),
             np.array([hw, 0.0, hh]), np.array([-hw, 0.0, hh])]
    uvs = [np.array([0, 0]), np.array([uv_scale[0], 0]),
           np.array([uv_scale[0], uv_scale[1]]), np.array([0, uv_scale[1]])]
    tris = _quad(verts[0], verts[1], verts[2], verts[3], uvs[0], uvs[1], uvs[2], uvs[3])
    return [(t[0], t[1], "plains", np.array([1.0, 1.0, 1.0])) for t in tris]


# --- kamera, światło, rasteryzacja ------------------------------------------


def look_at(eye, target, up=(0.0, 1.0, 0.0)):
    """Kamera: dla rzutu z góry trzeba podać inne „up” (inaczej baza się degeneruje)."""
    eye = np.array(eye, dtype=float)
    target = np.array(target, dtype=float)
    up = np.array(up, dtype=float)
    forward = target - eye
    forward /= np.linalg.norm(forward)
    right = np.cross(forward, up)
    right /= np.linalg.norm(right)
    true_up = np.cross(right, forward)
    return eye, np.stack([right, true_up, forward])


def project(points, cam, size, fov_deg):
    eye, basis = cam
    w, h = size
    tan_half = math.tan(math.radians(fov_deg) * 0.5)
    aspect = w / float(h)
    out = []
    for p in points:
        rel = p - eye
        x, y, z = basis @ rel
        if z <= 0.01:
            return None
        sx = (x / (z * tan_half * aspect)) * (w * 0.5) + w * 0.5
        sy = -(y / (z * tan_half)) * (h * 0.5) + h * 0.5
        out.append((sx, sy, z))
    return out


def sun_direction():
    rot = euler_matrix(*[math.radians(a) for a in SUN_ROT_DEG])
    forward = rot @ np.array([0.0, 0.0, -1.0])   # DirectionalLight3D świeci w -Z
    return -forward                               # kierunek DO światła


def render(triangles, cam, size, fov_deg, textures, ss=2, bg=(0.10, 0.12, 0.17), want_mask=False):
    w, h = size[0] * ss, size[1] * ss
    color = np.zeros((h, w, 3), dtype=np.float32)
    color[:] = np.array(bg, dtype=np.float32)
    depth = np.full((h, w), np.inf, dtype=np.float32)
    hit = np.zeros((h, w), dtype=bool)
    sun = sun_direction()
    ambient = AMBIENT_COLOR * AMBIENT_LEVEL

    for verts, uvs, tex_key, albedo in triangles:
        screen = project(verts, cam, (w, h), fov_deg)
        if screen is None:
            continue
        (x0, y0, z0), (x1, y1, z1), (x2, y2, z2) = screen
        area = (x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0)
        if abs(area) < 1e-9:
            continue
        bx0 = max(0, int(math.floor(min(x0, x1, x2))))
        bx1 = min(w - 1, int(math.ceil(max(x0, x1, x2))))
        by0 = max(0, int(math.floor(min(y0, y1, y2))))
        by1 = min(h - 1, int(math.ceil(max(y0, y1, y2))))
        if bx1 < bx0 or by1 < by0:
            continue
        ys, xs = np.mgrid[by0:by1 + 1, bx0:bx1 + 1]
        px = xs + 0.5
        py = ys + 0.5
        w0 = ((x1 - x0) * (py - y0) - (px - x0) * (y1 - y0)) / area
        w1 = ((px - x0) * (y2 - y0) - (x2 - x0) * (py - y0)) / area
        w2 = 1.0 - w0 - w1
        inside = (w0 >= -1e-6) & (w1 >= -1e-6) & (w2 >= -1e-6)
        if not inside.any():
            continue
        inv = np.stack([1.0 / z0, 1.0 / z1, 1.0 / z2])
        inv_z = w0 * inv[0] + w1 * inv[1] + w2 * inv[2]
        z = 1.0 / np.maximum(inv_z, 1e-9)
        u = (w0 * uvs[0][0] * inv[0] + w1 * uvs[1][0] * inv[1] + w2 * uvs[2][0] * inv[2]) / np.maximum(inv_z, 1e-9)
        v = (w0 * uvs[0][1] * inv[0] + w1 * uvs[1][1] * inv[1] + w2 * uvs[2][1] * inv[2]) / np.maximum(inv_z, 1e-9)

        normal = np.cross(verts[1] - verts[0], verts[2] - verts[0])
        norm = np.linalg.norm(normal)
        lambert = 0.0
        if norm > 1e-9:
            normal = normal / norm
            lambert = max(0.0, float(np.dot(normal, sun)))
        else:
            lambert = 1.0
        light = ambient + SUN_COLOR * (SUN_LEVEL * lambert + FILL_LEVEL * (1.0 - lambert))

        if tex_key is not None and tex_key in textures:
            tex = textures[tex_key]
            th, tw = tex.shape[0], tex.shape[1]
            tu = np.mod(u * tw, tw).astype(np.int32)
            tv = np.mod(v * th, th).astype(np.int32)
            # Tekstury trzymamy w 0..255 — musimy znormalizować do 0..1,
            # inaczej po pomnożeniu przez światło wszystko się przepala.
            sample = tex[tv, tu].astype(np.float32) / 255.0
        else:
            sample = np.ones((py.shape[0], py.shape[1], 3), dtype=np.float32)
        shaded = np.clip(sample * albedo * light, 0.0, 1.0)

        update = inside & (z < depth[by0:by1 + 1, bx0:bx1 + 1])
        if not update.any():
            continue
        depth[by0:by1 + 1, bx0:bx1 + 1][update] = z[update]
        color[by0:by1 + 1, bx0:bx1 + 1][update] = shaded[update]
        hit[by0:by1 + 1, bx0:bx1 + 1][update] = True

    image = Image.fromarray((np.clip(color, 0, 1) * 255).astype(np.uint8), "RGB")
    if ss > 1:
        image = image.resize((size[0], size[1]), Image.LANCZOS)
    if not want_mask:
        return image
    mask_image = Image.fromarray((hit * 255).astype(np.uint8), "L")
    if ss > 1:
        mask_image = mask_image.resize((size[0], size[1]), Image.BOX)
    return image, np.asarray(mask_image) > 96


## Rzut cienia: te same trójkąty, spłaszczone na grunt wzdłuż kierunku słońca.
def shadow_triangles(triangles, height=0.02):
    sun = sun_direction()
    flat = []
    for verts, uvs, _tex, _albedo in triangles:
        projected = []
        for v in verts:
            t = (v[1] - height) / max(sun[1], 1e-6)
            projected.append(v - sun * t)
        for (a, b, c), (ua, ub, uc) in [((projected[0], projected[1], projected[2]), (uvs[0], uvs[1], uvs[2]))]:
            flat.append(((a, b, c), (ua, ub, uc), None, np.array([0.0, 0.0, 0.0])))
    return flat


## Grunt + cień + jednostka. Zwraca gotowy obraz.
def render_unit_scene(unit_tris, cam, size, fov_deg, textures, ground, ss=2, bg=(0.10, 0.12, 0.17)):
    base = render(ground, cam, size, fov_deg, textures, ss=ss, bg=bg)
    shadow, shadow_mask = render(shadow_triangles(unit_tris), cam, size, fov_deg,
                                 textures, ss=ss, bg=(0.0, 0.0, 0.0), want_mask=True)
    base_arr = np.asarray(base).astype(np.float32) / 255.0
    base_arr[shadow_mask] *= (1.0 - SHADOW_STRENGTH)
    scene = Image.fromarray((np.clip(base_arr, 0, 1) * 255).astype(np.uint8), "RGB")

    unit_image, unit_mask = render(unit_tris, cam, size, fov_deg, textures, ss=ss,
                                   bg=(0.0, 0.0, 0.0), want_mask=True)
    scene.paste(unit_image, (0, 0), Image.fromarray((unit_mask * 255).astype(np.uint8), "L"))
    return scene


def load_textures():
    textures = {}
    for key in ("uniform", "armor", "track"):
        path = UNIT_TEXTURES / f"{key}.png"
        if path.exists():
            textures[key] = np.asarray(Image.open(path).convert("RGB"))
    ground = TERRAIN_TEXTURES / "plains.png"
    if ground.exists():
        textures["plains"] = np.asarray(Image.open(ground).convert("RGB"))
    return textures


# --- obrazy ------------------------------------------------------------------


def compose(views, title, subtitle, out_path, cell=(420, 320)):
    """Składa obraz z podpisanych widoków."""
    pad, head, label = 16, 96, 34
    cols = len(views)
    width = pad + cols * (cell[0] + pad)
    height = head + cell[1] + label + pad
    canvas = Image.new("RGB", (width, height), (18, 20, 24))
    draw = ImageDraw.Draw(canvas)
    draw.text((pad + 4, 20), title, font=ImageFont.truetype(FONT_BOLD, 30), fill=(232, 236, 240))
    draw.text((pad + 6, 60), subtitle, font=ImageFont.truetype(FONT, 16), fill=(150, 158, 168))
    for index, (image, caption) in enumerate(views):
        x = pad + index * (cell[0] + pad)
        canvas.paste(image.resize(cell, Image.LANCZOS), (x, head))
        draw.rectangle([x, head, x + cell[0] - 1, head + cell[1] - 1], outline=(70, 74, 80))
        draw.text((x + 2, head + cell[1] + 8), caption, font=ImageFont.truetype(FONT_BOLD, 17),
                  fill=(214, 220, 228))
    canvas.save(out_path, "PNG")
    print(f"{pathlib.Path(out_path).name}: {canvas.width}×{canvas.height}, "
          f"{pathlib.Path(out_path).stat().st_size // 1024} kB")


def main():
    parser = argparse.ArgumentParser(description="Renderuje bryły jednostek z gry (bez okna).")
    parser.add_argument("--meshes", default="/tmp/art/units.json")
    parser.add_argument("--out", default="/tmp/art/out")
    args = parser.parse_args()

    data = json.loads(pathlib.Path(args.meshes).read_text())
    out_dir = pathlib.Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    textures = load_textures()

    units = {(str(u["cls"]), str(u["side"])): u for u in data["units"]}
    tank = units[("armor", "gracz")]
    tank_tris = unit_triangles(tank)
    ground = ground_triangles()

    cell = (430, 330)
    views = []
    shots = [
        ("widok 3/4 (kamera gracza)", (10.5, 4.2, 8.6), (0.3, 1.0, 0.0), 42.0, (0.0, 1.0, 0.0)),
        ("widok z boku", (0.0, 2.6, 12.5), (0.0, 1.2, 0.0), 36.0, (0.0, 1.0, 0.0)),
        ("widok z przodu", (12.5, 2.4, 0.0), (0.0, 1.2, 0.0), 36.0, (0.0, 1.0, 0.0)),
        ("widok z góry", (0.0, 12.0, 0.0), (0.0, 0.8, 0.0), 40.0, (0.0, 0.0, -1.0)),
    ]
    for caption, eye, target, fov, up in shots:
        cam = look_at(eye, target, up)
        image = render_unit_scene(tank_tris, cam, cell, fov, textures, ground)
        views.append((image, caption))
    compose(views, "Czołg z gry — 16 brył, geometria i tekstury z battle_view.gd",
            "kadłub 7,0 × 2,0 × 3,2 m · dwie gąsienice 7,4 m · 5 kół na stronę · wieża Ø2,4 m · właz · lufa 3,6 m · "
            "cieniowanie i rzut: przybliżenie (brak okna graficznego)",
            out_dir / "render_czolg.png", cell)

    # Trzy barwy stron + wóz bojowy i piechur dla skali.
    views = []
    for side, caption in (("gracz", "barwa: gracz"), ("sojusznik", "barwa: sojusznik"), ("wróg", "barwa: wróg")):
        cam = look_at((9.5, 4.6, 8.0), (0.0, 1.1, 0.0))
        image = render_unit_scene(unit_triangles(units[("armor", side)]), cam, cell, 40.0, textures, ground)
        views.append((image, caption))
    compose(views, "Czołg w trzech barwach stron — ta sama tekstura, inny albedo_color",
            "w grze kolor strony jest mnożony przez teksturę sprzętu, więc detal zostaje, a przynależność widać od razu",
            out_dir / "render_czolg_barwy.png", cell)

    views = []
    for cls, caption in (("armor", "czołg — 16 brył"), ("mech", "wóz bojowy — 13 brył"), ("infantry", "piechur — 2 bryły")):
        cam = look_at((9.0, 4.4, 7.6), (0.0, 1.1, 0.0))
        image = render_unit_scene(unit_triangles(units[(cls, "gracz")]), cam, cell, 40.0, textures, ground)
        views.append((image, caption))
    compose(views, "Jednostki gracza w tej samej skali — tak zbuduje je bitwa",
            "te same funkcje (_build_armor / _build_mech / _build_infantry), ta sama ziemia i światło",
            out_dir / "render_jednostki.png", cell)


if __name__ == "__main__":
    main()
