# Podglądy grafiki

Obrazki poglądowe generowane narzędziami z `tools/` — do oglądania bez
uruchamiania gry (środowisko robocze nie ma serwera graficznego, więc Godot
w `--headless` nie renderuje obrazu).

| plik | co pokazuje | jak powstał |
| --- | --- | --- |
| `czolg_z_gry.jpg` | czołg z gry w czterech ujęciach (3/4, z boku, z przodu, z góry), wóz bojowy i piechur w skali, oraz ta sama geometria w trzech barwach stron | `tools/godot/dump_meshes.gd` + `tools/art/render_units.py` |
| `czolg_barwy_stron.jpg` | czołg w barwach gracza, sojusznika i wroga — ta sama tekstura, inny `albedo_color` | `tools/art/render_units.py` |
| `jednostki_skala.jpg` | czołg (16 brył), wóz bojowy (13) i piechur (2) w jednej skali | `tools/art/render_units.py` |
| `arkusz_tekstur_terenu.jpg` | 13 tekstur terenu z paletą: równina, las, wzgórza, góry, bagno, rzeka, bród, jezioro, miasto, droga, most, piasek, śnieg | `tools/art/preview_textures.py` |
| `arkusz_otoczenia.jpg` | 5 tekstur otoczenia bitwy: kora, korona, skała, ściana bloku, dach | `tools/art/preview_textures.py` |
| `arkusz_jednostek.jpg` | tekstury sprzętu bez barwy i w trzech barwach stron | `tools/art/preview_textures.py` |
| `arkusz_ikon.jpg` | 6 ikon mapy w rozmiarze docelowym i w skali mapy (24 i 16 px) | `tools/art/preview_textures.py` |
| `mapa_kampanii_seed1.jpg` | makieta mapy 60×40 z prawdziwego `tests/ref_map.json`, złożona z kafli gry, z ikonami | `tools/art/preview_textures.py` |
| `makieta_otoczenia.jpg` | tekstury otoczenia na bryłach, które buduje `battle_view.gd` | `tools/art/preview_textures.py` |
| `makieta_pojazdow.jpg` | schemat brył pojazdów w skali 1:20 z podziałem na części | `tools/art/preview_textures.py` |

## Wierność

* **Arkusz tekstur, ikon i otoczenia** — to wprost pliki z `assets/`, więc 1:1 z grą.
* **Makieta mapy** — prawdziwe dane mapy (`tests/ref_map.json`) i prawdziwe kafle;
  wrogowie i zwiadowca to znaczniki przykładowe (rozgrywka jest losowa).
* **Rendery jednostek** — bryły, rozmiary, pozycje, barwy i tekstury 1:1 z gry;
  oświetlenie i rzut są przybliżeniem mojego renderera (Godot inaczej tonuje
  obraz). Szczegóły: `tools/godot/README.md`.

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
