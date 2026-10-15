# Tekstury otoczenia bitwy (grafika AI)

Powierzchnie obiektów, które `scripts/battle/battle_view.gd` buduje z brył:
drzewa (las), skały (wzgórza), bloki miejskie (miasto). Teren bitwy ma własne
tekstury w `assets/textures/terrain/`.

## Pliki

```
assets/textures/props/<klucz>.png   256×256 — albedo materiału bryły 3D
```

| klucz | powierzchnia | użycie w bitwie | paleta (hex) |
| --- | --- | --- | --- |
| `tree_bark` | kora pnia | walec pnia drzewa | `#574533` |
| `tree_canopy` | igliwie korony | kula korony drzewa | `#264024` |
| `rock` | zwietrzały granit | kule skał i głazów | `#7A7873` |
| `wall` | ściana bloku | prostopadłościany bloków | `#94918A` |
| `roof` | płaski dach | płaski dach na bloku | `#616163` |

Klucze są zgodne z `GameTextures.PROP_KEYS` w `scripts/logic/game_textures.gd`
i z kolejnością w `tools/art/process_props.py`.

## Dopasowanie koloru

Ten sam rdzeń co dla terenu (`tools/art/pipeline.py`): korekta średniej koloru
do palety → przemalowanie w palecie → mieszanka 55/45 → kontrast 1,08,
nasycenie 1,05 → ostatnia korekta średniej. Kolory docelowe są stonowane, żeby
drzewa i budynki nie „wyskakiwały” z palety terenu.

## Odtworzenie i podgląd

```bash
pip install pillow

python3 tools/art/process_props.py --raw /tmp/art/raw_props      # surowe → materiały
python3 tools/art/preview_textures.py --out /tmp/art/out         # wszystkie podglądy
```

`preview_textures.py` tworzy cztery obrazy: `arkusz_tekstur.png` (13 tekstur
terenu), `mapa_seed<seed>.png` (makieta mapy z prawdziwych danych),
`arkusz_otoczenia.png` (te 5 tekstur) i `makieta_otoczenia.png` (tekstury na
bryłach z `battle_view.gd`).

Surowe obrazy (~2 MB każdy) nie są w repozytorium — odtwarza się je z promptów.

## Prompty

Wspólny koniec każdego promptu:

> Hand-painted matte style, soft painterly brushwork, muted desaturated
> palette, even diffuse lighting, no text, no letters, no numbers, no border,
> no frame, fills the whole square edge to edge.

| klucz | treść promptu |
| --- | --- |
| `tree_bark` | Seamless tileable surface texture of pine bark for a stylized 1970s Cold War game: weathered grey-brown bark with deep vertical fissures, moss in the crevices |
| `tree_canopy` | Seamless tileable surface texture of dense coniferous foliage for a stylized 1970s Cold War game: layered dark green pine needles and small twig clusters, a few lighter sunlit tips |
| `rock` | Seamless tileable surface texture of weathered granite for a stylized 1970s Cold War game: grey stone with cracks, lichen patches and small chips, slightly rough |
| `wall` | Seamless tileable facade texture for a stylized 1970s Cold War game: Eastern Bloc prefab concrete apartment slab wall, grey panels joined by visible seams, two rows of small identical square windows with dark glass, faint weathering streaks under the sills. Straight-on elevation view |
| `roof` | Seamless tileable texture of a flat rooftop seen from directly above, for a stylized 1970s Cold War game: weathered grey bitumen sheets with seams, patched repairs, a few small vents and gravel patches. Orthographic top-down view |

Tekstury terenu opisane są w `assets/textures/terrain/README.md`
(13 kafli, inny zestaw promptów).
