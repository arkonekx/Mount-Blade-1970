#!/usr/bin/env python3
"""Wspólny rdzeń pipeline'u tekstur AI dla „Zimnej Wojny 1975”.

Zamienia surowy obraz z generatora w teksturę o zadanej średniej koloru.
Kolejność działań:

1. kadrowanie do kwadratu (środek) i skalowanie,
2. **korekta średniej koloru** — kanały skalowane tak, by średnia trafiła
   w kolor docelowy; detal zostaje,
3. **przemalowanie** — struktura brana z jasności, kolor wprost z palety,
4. mieszanka obu wersji (domyślnie 55 % korekty / 45 % przemalowania),
5. kontrast i nasycenie w ryzach oraz ostatnia korekta średniej.

Dzięki temu obrazy z osobnych generowań trzymają jeden ton i paletę, więc gra
nie wygląda jak kolaż. Wymaga Pillow.
"""

from PIL import Image, ImageEnhance, ImageStat

CONTRAST = 1.08
SATURATION = 1.05
BLEND = 0.55          # udział wersji „korekta średniej”
FACTOR_MIN = 0.35     # granice korekty kanału, żeby nie przepalić obrazu
FACTOR_MAX = 2.8


def target_rgb(color):
    """Kolor 0..1 (jak w GDScript) → krotka 0..255."""
    return tuple(round(c * 255) for c in color)


def mean_rgb(image):
    return tuple(ImageStat.Stat(image).mean[:3])


def scale_to_target(image, target):
    """Skaluje kanały tak, by średnia koloru trafiła w paletę (zachowuje detal)."""
    got = mean_rgb(image)
    out = []
    for ch, got_ch, want in zip(image.split(), got, target):
        factor = min(max(want / max(got_ch, 1.0), FACTOR_MIN), FACTOR_MAX)
        out.append(ch.point(lambda v, f=factor: min(255, int(v * f))))
    return Image.merge("RGB", out)


def relight(image, target):
    """Wersja „przemalowana”: struktura z jasności, kolor z palety."""
    grey = image.convert("L")
    mean_lum = max(ImageStat.Stat(grey).mean[0], 1.0)
    target_lum = sum(target) / 3.0
    grey = grey.point(lambda v: min(255, int(v * (target_lum / mean_lum))))
    scale = target_lum / 255.0 if target_lum else 1.0
    tint = Image.new("RGB", image.size)
    tint.putdata([(
        min(255, int(v * target[0] / 255.0 / scale)),
        min(255, int(v * target[1] / 255.0 / scale)),
        min(255, int(v * target[2] / 255.0 / scale)),
    ) for v in grey.get_flattened_data()])
    return tint


def from_raw(raw_path, size, target):
    """Surowy obraz → tekstura o zadanej średniej koloru i rozmiarze."""
    image = Image.open(raw_path).convert("RGB")
    w, h = image.size
    side = min(w, h)
    left, top = (w - side) // 2, (h - side) // 2
    image = image.crop((left, top, left + side, top + side))
    image = image.resize((size, size), Image.LANCZOS)

    blended = Image.blend(scale_to_target(image, target), relight(image, target), 1.0 - BLEND)
    blended = ImageEnhance.Contrast(blended).enhance(CONTRAST)
    blended = ImageEnhance.Color(blended).enhance(SATURATION)
    return scale_to_target(blended, target)
