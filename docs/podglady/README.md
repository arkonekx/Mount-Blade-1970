# Podglądy grafiki

Obrazki poglądowe generowane narzędziami z `tools/` — do oglądania bez
uruchamiania gry (środowisko robocze nie ma serwera graficznego, więc Godot
w `--headless` nie renderuje obrazu).

Wszystkie rendery poniżej powstają z **prawdziwej geometrii gry**: skrypt
`tools/godot/dump_meshes.gd` woła te same funkcje budujące świat bitwy, których
używa `battle_view.gd`, i zapisuje bryły do JSON-a. Renderer tylko je oświetla.

---

## Czołgi 1975 — cały park sprzętu w jednej skali

M60A1/M48A5 (długa lufa 105 mm z przedmuchiwaczem, wysoka wieża odlewana z
koszem, 6 kół jezdnych, 3 rolki), M551 Sheridan (niski, lekki, 5 dużych kół,
napęd z przodu), T-55/T-62 (kopuła odlewana, 5 dużych kół, beczki paliwa na
błotniku), T-72 Ural (najniższy, 125 mm z rurą snorkla). Każdy wóz ma
dokładnie 256 brył, ale inne proporcje:

![Park czołgów 1975 w jednej skali](render_porownanie.jpg)

## Wozy bojowe — kołowy, gąsienicowy, każdy inny

M113 (pudełko z falochronem i rampą, napęd z przodu), BTR-60PB (osiem kół,
cztery osie na stronę — jedyny wóz kołowy w grze), BMP-1 (niski klin z
działem 73 mm i wyrzutnią 9M14), MT-LB (najniższy ciągnik). Każdy ma 128 brył:

![Wozy bojowe w jednej skali](render_wozy.jpg)

## M60A1 — 256 brył, cztery ujęcia

Ten sam wóz z kamery gracza, z boku, z przodu i z góry. Na dachu wieży jest
płaska gwiazda — tak jak w rzeczywistości malowano oznaczenia do identyfikacji
z powietrza; z boku widać gwiazdy na burtach kadłuba i wieży:

![Czołg M60A1 w czterech ujęciach](render_czolg.jpg)

## Barwy fabryczne — stronę poznaje się po sylwetce i oznaczeniu

olive drab (USA) kontra zieleń 4BO (ZSRR), gwiazda państwowa na burtach;
w bitwie przynależność jednostki pokazuje dodatkowo pierścień na ziemi:

![Barwy fabryczne: M60A1, T-55, M113, BTR-60PB](render_warianty.jpg)

## Jednostki gracza w jednej skali

Czołg (256 brył), wóz bojowy (128) i piechur (10) — te same funkcje
budujące, ta sama ziemia i światło. Piechur jest tu dla skali:

![Czołg, wóz bojowy i piechur w jednej skali](render_jednostki.jpg)

---

## Tekstury terenu (13)

Sprowadzone programowo do jednej palety, więc mapa nie wygląda jak kolaż.

![Arkusz tekstur terenu](arkusz_tekstur_terenu.jpg)

## Tekstury otoczenia bitwy (5)

![Arkusz tekstur otoczenia](arkusz_otoczenia.jpg)

## Tekstury sprzętu (3)

![Arkusz tekstur sprzętu](arkusz_jednostek.jpg)

## Ikony mapy (6)

![Arkusz ikon](arkusz_ikon.jpg)

---

## Makiety

Mapa kampanii 60×40 z prawdziwego `tests/ref_map.json`, złożona z kafli gry,
z ikonami (wrogowie i zwiadowca to znaczniki przykładowe — rozgrywka jest losowa):

![Makieta mapy kampanii](mapa_kampanii_seed1.jpg)

Tekstury otoczenia na bryłach, które buduje `battle_view.gd`:

![Makieta otoczenia](makieta_otoczenia.jpg)

Rzut z boku **prawdziwych brył** pojazdów z podziałką metrową. Widać każde
ogniwo gąsienicy, każde koło i każdą płytę pancerza osobno, a gwiazdy to
płytki oznaczeń (białe USA, czerwone ZSRR):

![Makieta pojazdów — rzut brył z boku](makieta_pojazdow.jpg)

---

## Co jest 1:1 z grą, a co przybliżeniem

| plik | wierność |
| --- | --- |
| arkusze tekstur, ikon i otoczenia | **1:1** — to wprost pliki z `assets/` |
| `mapa_kampanii_seed1` | **dane i kafle 1:1** — prawdziwy seed z `tests/ref_map.json`; wrogowie i zwiadowca to znaczniki przykładowe |
| `render_porownanie`, `render_wozy`, `render_czolg`, `render_warianty`, `render_jednostki` | **geometria, proporcje, barwy i tekstury 1:1** z gry; oświetlenie i rzut to przybliżenie renderera (Godot inaczej tonuje obraz) — szczegóły w `tools/godot/README.md` |
| `makieta_pojazdow` | **bryły i wymiary 1:1** (rzut ortograficzny z prawdziwej geometrii); wygląd powierzchni uproszczony do płaskich barw stron |

## Odtworzenie

```bash
pip install --break-system-packages numpy pillow

# tekstury i makiety
python3 tools/art/preview_textures.py --out /tmp/art/out
python3 tools/art/preview_textures.py --out /tmp/art/out --seed 42 --meshes /tmp/art/units.json

# render jednostek z prawdziwej geometrii gry
godot --headless --path . -s res://tools/godot/dump_meshes.gd -- /tmp/art/units.json
python3 tools/art/render_units.py --meshes /tmp/art/units.json --out /tmp/art/out
```
