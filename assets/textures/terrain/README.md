# Tekstury terenu (grafika AI)

Kafle terenu dla mapy kampanii i materiały dla gruntu w bitwie 3D.
Wszystkie obrazy powstały w tej samej stylistyce: **stylizowana, malowana
mapa sztabowa z lotu ptaka** — bez tekstu, bez ramek, bez cieni obiektów.

## Pliki

```
assets/textures/terrain/<klucz>.png        512×512  — materiały 3D (bitwa)
assets/textures/terrain/tiles/<klucz>.png   64×64   — kafle mapy (kampania, 16 px na ekranie)
```

Klucze i ich kolejność odpowiadają `Terrain.Kind` z `scripts/logic/terrain.gd`.

| klucz | teren | paleta (hex) | stan |
| --- | --- | --- | --- |
| `plains` | równina | `#6B8C4F` | ✓ |
| `forest` | las | `#2E5C33` | ✓ |
| `hills` | wzgórza | `#857352` | ✓ |
| `mountain` | góry | `#6B6661` | ✓ |
| `marsh` | bagno | `#4C6657` | ✓ |
| `river` | rzeka | `#33619E` | ✓ |
| `ford` | bród | `#6699C7` | ✓ |
| `lake` | jezioro | `#294780` | ✓ |
| `road` | droga | `#9E8F6B` | ✓ |
| `city` | miasto | `#B8A88C` | do wygenerowania |
| `bridge` | most | `#B39461` | do wygenerowania |
| `sand` | piasek | `#CCBD85` | do wygenerowania |
| `snow` | śnieg | `#EBF0F7` | do wygenerowania |

## Jak dopasowujemy kolor

Każda surowa tekstura przechodzi przez `tools/art/process_terrain.py`:

1. kadrowanie do kwadratu i skalowanie do 512 px,
2. **korekta średniej koloru** do palety z `campaign_view.gd` (zachowuje detal),
3. **przemalowanie** — struktura brana z jasności, kolor wprost z palety,
4. mieszanka obu wersji (55 % korekty / 45 % przemalowania), kontrast 1,08,
   nasycenie 1,05 i ponowna korekta średniej,
5. kafle 64 px z wyostrzeniem (mapa rysuje je w rozmiarze 16 px).

Dzięki temu trzynaście obrazów z różnych generowań czyta się na mapie jak jeden
obraz, a teren jest rozpoznawalny bez legendy. Średnie koloru po przetworzeniu
trafiają w paletę z dokładnością do 1–2 jednostek na kanał.

## Odtworzenie i podgląd

```bash
pip install pillow

# 1. surowe obrazy z generatora → kafle gry (surowe trzymamy poza repo, ~21 MB)
python3 tools/art/process_terrain.py --raw /tmp/art/raw

# 2. podglądy bez uruchamiania Godota
python3 tools/art/preview_terrain.py --out /tmp/art/out            # arkusz + mapa seed 1
python3 tools/art/preview_terrain.py --out /tmp/art/out --seed 42  # inny seed
```

Surowe obrazy (2–3 MB każdy) **nie są** w repozytorium — odtwarza się je
z promptów poniżej, a pipeline i tak sprowadza je do jednej palety.

## Prompty

Wspólny przedrostek każdego promptu:

> Seamless tileable texture for a stylized 1970s Cold War strategy game map: …
> Orthographic top-down aerial view, hand-painted matte style, soft painterly
> brushwork, muted desaturated palette, even diffuse lighting, no text, no
> letters, no numbers, no border, no frame, fills the whole square edge to edge.

| klucz | treść promptu |
| --- | --- |
| `plains` | flat farmland seen from directly above, mixed green grass fields with faint mown stripes, small patches of dry grass, a few tiny wildflowers |
| `forest` | dense forest canopy seen from directly above, dark green pine and birch crowns packed tightly together with narrow gaps of shadow between them |
| `hills` | rolling hills of dry ochre grass with scattered pale stones and faint erosion lines |
| `mountain` | barren grey rocky mountain ridge seen from directly above, cracked stone slabs, scree, thin snow in crevices |
| `marsh` | murky wetland bog seen from directly above, dark olive water pools, reeds, soggy grass tussocks and muddy patches |
| `river` | dark blue-green river water seen from directly above, gentle current streaks and small ripples, faint silt swirls |
| `ford` | shallow river crossing seen from directly above, pale sandy shoal under clear shallow water, light ripples, a few smooth wet stones |
| `lake` | deep lake water seen from directly above, dark teal-blue with subtle wavelets and faint reflections, calm and cold |
| `road` | worn gravel and packed dirt country road surface, faint wheel ruts, small stones, dry dust, no markings |
| `city` | dense city block seen from directly above, grey concrete and brick rooftops, narrow inner courtyards, thin streets and alleys between buildings, tiny chimneys and vents |
| `bridge` | military pontoon bridge deck seen from directly above, weathered timber planks with riveted steel beams and side rails, small water gaps between sections |
| `sand` | pale sandbar seen from directly above, fine wind ripples, a few pebbles and dry cracked patches |
| `snow` | tundra snowfield seen from directly above, wind-blown drifts, faint old tank track impressions and sparse dark grass tips poking through |

## Uwaga o podglądach

Środowisko robocze nie ma okna graficznego, więc widoków z gry nie da się
zrzucić ekranem — `preview_terrain.py` składa mapę z prawdziwych danych
(`tests/ref_map.json`) i tych samych kafli, których używa gra, więc podgląd
odpowiada temu, co rysuje `campaign_view.gd`.
