# Renderer jednostek (bez okna graficznego)

Środowisko robocze nie ma serwera graficznego, więc Godot uruchamiany w trybie
`--headless` **nie renderuje obrazu** — nie da się zrobić zwykłego zrzutu ekranu
z gry. Ten katalog obchodzi ograniczenie: geometria pochodzi z gry, a obraz
składa własny renderer w Pythonie.

## Jak to działa

```
godot --headless --path . -s res://tools/godot/dump_meshes.gd -- /tmp/art/units.json
python3 tools/art/render_units.py --meshes /tmp/art/units.json --out /tmp/art/out
```

1. `dump_meshes.gd` woła **te same funkcje, które budują świat bitwy**
   (`_tank_parts`, `_mech_parts`, `_build_infantry` z `battle_view.gd`) i zapisuje
   każdą bryłę: typ siatki, rozmiar, pozycję, obrót, `albedo_color`, `uv1_scale`
   i klucz tekstury. W pliku ląduje więc dokładnie ta geometria, którą widzi
   gracz — 256 brył czołgu, 128 wozu bojowego, 10 piechura, dla każdej strony
   osobno (wariant NATO albo ZSRR).
2. `render_units.py` rasteryzuje te bryły (numpy + Pillow): rzut perspektywiczny,
   bufor głębokości, oświetlenie per ściana, rzut cienia na grunt, tekstury
   próbkowane z odtworzonymi UV i `uv1_scale`.

## Co jest wierne, a co przybliżone

| element | wierność |
| --- | --- |
| bryły, rozmiary, pozycje, obroty | 1:1 z gry (zrzut z `battle_view.gd`) |
| kolory stron (`albedo_color`) | 1:1 z gry (mnożone przez teksturę) |
| tekstury | te same pliki z `assets/textures/units/` |
| kierunek słońca | ten sam obrót co w `battle_view.gd` (−55°, 35°) |
| jasność sceny | **przybliżenie** — Godot tonuje obraz, renderer mnoży światło wprost |
| mapowanie UV | **przybliżenie** — odtworzone z typów siatek; kolejność ścian może się różnić od oryginału |
| cienie | **przybliżenie** — rzut na grunt wzdłuż kierunku słońca, bez map cienia z Godota |

Innymi słowy: kształt, proporcje, materiały i barwy są prawdziwe, a oświetlenie
i rzut są moją interpretacją. Renderer nie udaje Godota — pokazuje, co gra
buduje.

## Wyniki

* `render_czolg.png` — czołg w czterech ujęciach (3/4 jak kamera gracza, z boku,
  z przodu, z góry),
* `render_czolg_barwy.png` — ta sama geometria w trzech barwach stron,
* `render_jednostki.png` — czołg, wóz bojowy i piechur w jednej skali.

Wymaga: `numpy`, `Pillow` (`pip install numpy pillow`).
