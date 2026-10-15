# Ikony interfejsu (grafika AI)

Znaczniki rysowane na mapie kampanii (`scripts/campaign_view.gd`).

## Pliki

```
assets/textures/icons/<klucz>.png   128×128, RGBA z przezroczystym tłem
```

| klucz | ikona | trafia na |
| --- | --- | --- |
| `player` | zielona strzałka | pole gracza |
| `enemy` | czerwony romb z X | oddziały wroga widziane przez zwiad |
| `objective` | złota chorągiewka | cele kampanii (zdobyty — wygaszona) |
| `city` | budynki z oknami | miasta |
| `boat` | łódka z kilwaterem | łodzie przy brzegu |
| `scout` | lornetka | własny zwiadowca |

Klucze są zgodne z `GameTextures.ICON_KEYS` w `scripts/logic/game_textures.gd`
i z `tools/art/process_icons.py`. Gdy którejś ikony brakuje, widok rysuje
zapasowy kształt (`draw_arc`, `draw_rect`, trójkąt gracza) — gra działa dalej.

## Skala

Widok rysuje ikony w rozmiarach 14–24 px, czyli w skali mapy (pole ma 16 px).
Dlatego ikony są projektowane jako **prosty kształt z grubym czarnym obrysem**:
w takim rozmiarze liczy się tylko sylwetka i kontrast. Podgląd w skali mapy jest
w `arkusz_ikon.png` (`tools/art/preview_textures.py`).

## Wycinanie tła

Ikony powstają na jednolitym magentowym tle (`#FF00FF`), bo tego koloru nie ma
w palecie gry. `tools/art/process_icons.py`:

1. liczy „magentowość” piksela (`min(r, b) − g`),
2. robi z niej kanał alfa z miękkim przejściem (28 → w pełni widoczny,
   78 → w pełni przezroczysty),
3. usuwa różową obwódkę (podnosi zielony do średniej z czerwonego i niebieskiego),
4. przycina do treści, dodaje 6 % marginesu i skaluje do 128×128, żeby wszystkie
   ikony miały podobny ciężar optyczny.

## Prompty

Wspólny szablon:

> Game UI icon of \<opis\> for a 1970s Cold War staff map: \<kształt\>, flat
> simple shape, slight brush texture, single centred symbol, isolated on a solid
> flat pure magenta #FF00FF background, no text, no letters, no numbers, no frame,
> nothing else in the image.

| klucz | opis |
| --- | --- |
| `player` | a friendly unit marker: a bold green arrow pointing east |
| `enemy` | a hostile unit marker: a bold red diamond with a thick black X drawn across it |
| `objective` | an objective marker: a golden-yellow flag on a short dark pole, waving slightly |
| `city` | a city marker: a small pale group of three simple buildings with dark square windows and one chimney |
| `boat` | a river boat marker: a small pale blue-grey motor launch seen from above with a white bow wake behind it |
| `scout` | a reconnaissance marker: a bold white pair of binoculars |

Odtworzenie:

```bash
python3 tools/art/process_icons.py --raw /tmp/art/raw_icons
python3 tools/art/preview_textures.py --out /tmp/art/out
```
