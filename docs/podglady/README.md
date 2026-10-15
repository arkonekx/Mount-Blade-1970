# Podglądy grafiki

Obrazki poglądowe generowane narzędziami z `tools/` — do oglądania bez
uruchamiania gry (środowisko robocze nie ma serwera graficznego, więc Godot
w `--headless` nie renderuje obrazu).

---

## Czołg z gry — 16 brył

Geometria i tekstury pochodzą **z gry**: zrzut robi skrypt, który woła te same
funkcje budujące świat bitwy co `battle_view.gd`. Cztery ujęcia, a pod nimi
wóz bojowy i piechur w tej samej skali oraz ta sama geometria w barwach stron.

![Czołg z gry w czterech ujęciach](czolg_z_gry.jpg)

## Ta sama tekstura, trzy barwy stron

W grze kolor strony jest mnożony przez teksturę sprzętu, więc detal (nity,
spoiny, ogniwa) zostaje, a przynależność widać od razu.

![Czołg w barwach gracza, sojusznika i wroga](czolg_barwy_stron.jpg)

## Jednostki w jednej skali

![Czołg, wóz bojowy i piechur w jednej skali](jednostki_skala.jpg)

---

## Tekstury terenu (13)

Sprowadzone programowo do jednej palety, więc mapa nie wygląda jak kolaż.

![Arkusz tekstur terenu](arkusz_tekstur_terenu.jpg)

## Tekstury otoczenia bitwy (5)

![Arkusz tekstur otoczenia](arkusz_otoczenia.jpg)

## Tekstury sprzętu (2)

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

Schemat brył pojazdów w skali 1:20:

![Makieta pojazdów](makieta_pojazdow.jpg)

---

## Co jest 1:1 z grą, a co przybliżeniem

| plik | wierność |
| --- | --- |
| arkusze tekstur, ikon i otoczenia | **1:1** — to wprost pliki z `assets/` |
| `mapa_kampanii_seed1` | **dane i kafle 1:1** — prawdziwy seed z `tests/ref_map.json`; wrogowie i zwiadowca to znaczniki przykładowe |
| `czolg_z_gry`, `czolg_barwy_stron`, `jednostki_skala` | **geometria, barwy i tekstury 1:1** z gry; oświetlenie i rzut to przybliżenie renderera (Godot inaczej tonuje obraz) — szczegóły w `tools/godot/README.md` |

## Odtworzenie

```bash
pip install numpy pillow

# tekstury i makiety
python3 tools/art/preview_textures.py --out /tmp/art/out
python3 tools/art/preview_textures.py --out /tmp/art/out --seed 42

# render jednostek z prawdziwej geometrii gry
godot --headless --path . -s res://tools/godot/dump_meshes.gd -- /tmp/art/units.json
python3 tools/art/render_units.py --meshes /tmp/art/units.json --out /tmp/art/out
```
