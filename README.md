# Zimna Wojna 1975

Gra strategiczna 2D w Godot 4.7: kampania USA vs ZSRR w 1975 roku, inspirowana
Mount & Blade. Po mapie kampanii porusza się oddział gracza (mgła wojny,
zaopatrzenie, morale, miasta do zdobycia). Gdy na mapie dojdzie do kontaktu
z wrogiem, gra przełącza się na **bitwę FPS w 3D** — gracz walczy w pierwszej
osobie, pieszo albo z pokładu pojazdu.

## Wymagania

* Godot **4.7.x** (projekt tworzony i przetestowany na 4.7.2) — dowolna binarka
  z tej linii. **Binarka testowa jest w repo**: spakowana
  `tools/godot/bin/Godot_v4.7.2-stable_linux.x86_64.gz` (35 MB, po rozpakowaniu
  136 MB; szczegóły i suma kontrolna w `tools/godot/bin/README.md`). To
  kompilacja headless — bez X11, Waylanda i dźwięku: wystarcza do testów
  i scen w `--headless`, ale **nie do gry z okienkiem**; do grania weź oficjalne
  wydanie z godotengine.org.

  ```bash
  gunzip -k tools/godot/bin/Godot_v4.7.2-stable_linux.x86_64.gz
  export GODOT="$PWD/tools/godot/bin/Godot_v4.7.2-stable_linux.x86_64"
  ./run_tests.sh        # 7 testów + 2 sceny
  ```
* Nic więcej — cała grafika to prymitywy 3D i kolory, dźwięk nie jest jeszcze
  podłączony.

## Uruchomienie

```bash
# z katalogu projektu
godot --path .                       # kampania (scena główna)
godot --path . res://scenes/battle.tscn   # sama bitwa (tworzy kampanię demo)
```

W edytorze Godota: otwórz `project.godot` i uruchom projekt (F5).

## Kampania — sterowanie

| Klawisz / przycisk | Działanie |
| --- | --- |
| LPM na mapie | marsz do wskazanego pola |
| PPM na mapie | wyślij zwiadowcę (zabiera jednego piechura) |
| T | czekaj 1 godzinę (czas płynie dalej) |
| S | zatrzymaj marsz |
| J | kup żywność (50 za 20 funduszy) |
| K | rekrutuj piechotę (80 funduszy, tylko w mieście) |
| R | odpoczynek (tylko w mieście, +5 morale) |
| F | przeprawa łodzią (gdy stoisz przy łodzi) |
| B | zbuduj most (wymaga pojazdu inżynieryjnego przy wodzie) |
| F5 / F9 | zapis / odczyt stanu kampanii |
| N | nowa kampania |

## Bitwa FPS — sterowanie

| Klawisz / przycisk | Działanie |
| --- | --- |
| WSAD / strzałki | ruch i obrót (w pojeździe — jazda) |
| mysz | obrót głowy / wieżyczki |
| LPM lub Spacja | strzał |
| E | wsiadanie i wysiadanie z pojazdu własnej strony |
| R | odwrót (działa na zachodnim skraju pola, x < 40 m) |
| Esc | pauza (i zwolnienie kursora) |
| Enter | powrót do kampanii (liczony jako odwrót) |

## Zasady kampanii

* Start: 400 żywności, 300 funduszy, 80 morale, dzień 1, godzina 8:00.
* Żywność: 1 na jednostkę dziennie (zwiadowca też je). Brak żywności to −8 morale.
* Dochód: +20 funduszy dziennie.
* **Cel zwycięstwa:** zdobyć 3 miasta (odległe od startu o co najmniej 15 pól)
  i utrzymać każde przez 12 godzin bez wroga w promieniu 3 pól. Brak limitu czasu.
* Wrogowie: do 6 oddziałów na mapie (ich liczba rośnie z dniami), garnizony
  w miastach i zwiadowcy wysyłani co 3 dni. Wróg goni gracza, gdy ma przewagę.
* Limity oddziału: **30 jednostek, 2 pancerne, 5 zmechanizowanych**.
* Woda jest nieprzechodnia: pomoże bród, most (pojazd inżynieryjny: M728 CEV
  albo MTU-20) lub łódź przy brzegu.
* Zwiadowca wraca po `2 × koszt trasy` godzinach; jego raport pokazuje wrogów
  z **dniem wykrycia** (znaczniki `dN` na mapie), a nie na żywo. Szansa, że
  zwiadowca zginie w pobliżu wroga, wynosi 35%.
* Zapis trafia do jednego slotu: `user://zimna_wojna_slot1.json` (wersja 1).

## Zasady bitwy

* Pole 1000 × 400 m. Nasi startują na zachodzie (gracz na polu 60, 200),
  wróg na wschodzie (x ≈ 900-970 m).
* Broń: karabin (300 m, celność 0,06), km (600 m, 0,10), wyrzutnia ppanc
  (450 m, 0,45), armata czołgowa (900 m, 0,40). Piechota z karabinem **nie**
  razi pojazdów — potrzebna wyrzutnia albo armata.
* Wybór broni jest automatyczny: gotowa broń, która może razić cel i sięga
  dystansu; przy zgodnej kontrze celność liczona ×3.
* Trafienie eliminuje cel od razu. Osłona terenu: las 0,8, wzgórza i miasto 0,9,
  równina 1,0. Nocą zasięg spada do 350 m, a szansa trafienia ×0,85.
* Śmierć dowódcy (pierwszy piechur strony, u gracza — pierwszy piechur poza
  graczem) łamie organizację strony do 40. To nie kończy bitwy.
* Miny niszczą pojazd w promieniu 3 m razem z załogą (jeśli w nim byłeś — giniesz).
* Bitwa kończy się po 600 sekundach (bez rozstrzygnięcia) albo wcześniej:
  śmierć gracza = porażka, wybicie wszystkich wrogów = zwycięstwo, odwrót = `retreat`.

## Grafika

Materiały są generowane AI (stylizowana, malowana mapa sztabowa z lotu ptaka)
i sprowadzane do jednej palety programowo, więc mapa nie wygląda jak kolaż.

```
assets/textures/terrain/<klucz>.png        512×512  — teren: materiały 3D bitwy
assets/textures/terrain/tiles/<klucz>.png   16×16   — teren: kafle mapy kampanii
assets/textures/props/<klucz>.png          256×256  — otoczenie: pnie, korony,
                                                       skały, ściany i dachy
assets/textures/units/<klucz>.png          256×256  — sprzęt: mundur, pancerz,
                                                       ogniwa gąsienicy
assets/textures/icons/<klucz>.png          128×128  — ikony mapy (RGBA)
assets/textures/markings/<klucz>.png       128×128  — oznaczenia państwa
                                                       (gwiazdy, RGBA)
scripts/logic/game_textures.gd      loader tekstur (z zapasem na płaskie kolory)
tools/art/pipeline.py               rdzeń: dopasowanie kolorystyki obrazu
tools/art/process_terrain.py        surowe obrazy → kafle i materiały terenu
tools/art/process_props.py          surowe obrazy → materiały otoczenia
tools/art/process_units.py          surowe obrazy → materiały sprzętu
tools/art/process_icons.py          surowe ikony → PNG z przezroczystością
tools/art/preview_textures.py       arkusze kontaktowe + makiety
tools/art/render_units.py           renderer brył z gry (bez okna graficznego)
tools/art/make_markings.py          gwiazdy państwowe na pancerz (RGBA)
tools/godot/dump_meshes.gd          zrzut geometrii jednostek z battle_view.gd
assets/textures/*/README.md         palety, prompty, instrukcja odtworzenia
```

Zestaw: 13 rodzajów terenu (kafle mapy i materiały gruntu bitwy), 5 tekstur
otoczenia bitwy (kora i korona drzew, skała, ściana bloku, dach), 3 tekstury
sprzętu (mundur, pancerz, ogniwa gąsienicy), 6 ikon mapy (gracz, wróg, cel,
miasto, łódź, zwiadowca), 2 oznaczenia państwa (biała gwiazda USA, czerwona
gwiazda ZSRR) i 7 ikon HUD bitwy (karabin, km, wyrzutnia ppanc, armata oraz
piechota, wóz bojowy, czołg).

Sylwetki pojazdów są składane z **1024 brył** każdy (piechur: 10), a **każdy
wóz ma własną funkcję budującą**, wzorowaną na prawdziwym pierwowzorze z 1975
roku (wzorcem były publiczne modele 3D na Sketchfabie i dane wymiarowe): pochyłe
płyty pancerza, fartuchy błotników, pełne bieżnie z pojedynczych ogniw, koła
jezdne z piastami i śrubami, rolki, koła napędowe z zębami, wieże z jarzmem,
lufami, włazami, antenami, reflektorami i wyposażeniem zewnętrznym. Różnice
widać po sylwetce, nie po kolorze:

* **M60A1** — klinowy nos, działo 105 mm, reflektor AN/VSS-1 nad lufą, sześć
  kół jezdnych i wysoka wieża odlewana z koszem; wariant inżynieryjny M728 CEV
  dokłada lemiesz i żuraw,
* **M551 Sheridan** — niski, lekki, pięć dużych kół, napęd z przodu, grube
  działo 152 mm z przedmuchiwaczem,
* **MBT-70** (prototyp USA/RFN) — ogromna płaska wieża szersza od kadłuba,
  działo 152 mm, zdalne działko 20 mm w kopułce, siedem kół,
* **T-62 Obr. 1972** — kopuła odlewana, pięć kół rozstawionych równo (po tym
  odróżnia się od T-55), działo 115 mm bez hamulca wylotowego, rura do
  brodzenia OPVT, beczki paliwa na błotniku,
* **T-72 Ural** — niski, sześć kół, działo 125 mm z koszulką termiczną i rura
  snorkla na tyle wieży,
* **Obiekt 775** (prototyp ZSRR) — czołg rakietowy na podwoziu T-64: płaska
  wieża-dysk szersza od kadłuba, cienkie działo 125 mm, lemiesz, najniższy
  z parku (1,9 m),
* **M113** (pudełko z falochronem i rampą; wariant TOW dokłada wyrzutnię),
  **BTR-60PB** (jedyny wóz kołowy — cztery osie na stronę), **BMP-1** (niski
  klin z działkiem 73 mm i wyrzutnią 9M14), **MT-LB** (najniższy ciągnik, mała
  wieżyczka z km-em; wariant mostowy dokłada most MTU-20).

Barwy są **fabryczne**: olive drab dla USA, zieleń 4BO dla ZSRR. Stronę rozpoznaje
się po sylwetce i po gwieździe państwowej (`assets/textures/markings/`) — biała
gwiazda USA na dachu wieży i burtach kadłuba, czerwona gwiazda ZSRR. Dopiero
w bitwie przynależność jednostki pokazuje pierścień na ziemi (`COLOR_PLAYER`,
`COLOR_FRIEND`, `COLOR_ENEMY`). Bryły dzielą wspólne materiały
(`_material_cache`), więc mimo dziesiątek tysięcy brył w bitwie powstaje
kilkadziesiąt materiałów, a nie tysiące.

Tekstury sprzętu są jasne i neutralne, bo materiał mnoży je przez barwę wozu
(`albedo_color`): detal (nity, spoiny, ogniwa) daje tekstura, a kolor to
fabryczna olive drab albo zieleń 4BO. Ikony mają wycięte tło (alfa) i są
projektowane pod skalę mapy — gruby obrys i prosta sylwetka. Przy braku
któregokolwiek pliku gra wraca do płaskich kolorów i kształtów, więc nic się
nie wywala.

Tekstury są wczytywane przez `Image.load_from_file` (a nie `load("res://…")`),
bo projekt bywa uruchamiany bez otwartego edytora (`--headless` w testach),
a wtedy Godot nie ma jeszcze zaimportowanych zasobów. Gdyby jakiejś tekstury
brakowało, mapa wraca do płaskich kolorów z `COLORS` — gra się nie wywala.
Przy eksporcie dodaj `assets/textures/terrain/*.png` do filtra plików
niezasobowych w presecie eksportu.

## Podglądy

Obrazki poglądowe (czołg z gry, arkusze tekstur, makieta mapy) leżą w
`docs/podglady/` — spis i informacja, co jest 1:1 z grą, a co przybliżeniem:
`docs/podglady/README.md`.

## Podgląd bez okna graficznego

Środowisko bez serwera graficznego nie pozwala zrobić zrzutu ekranu z gry
(Godot w `--headless` nie renderuje). Zamiast tego geometria jest zrzucana
z gry, a obraz składa renderer w Pythonie:

```bash
godot --headless --path . -s res://tools/godot/dump_meshes.gd -- /tmp/art/units.json
python3 tools/art/render_units.py --meshes /tmp/art/units.json --out /tmp/art/out
```

Bryły, rozmiary, pozycje, barwy i tekstury są 1:1 z gry; oświetlenie i rzut to
przybliżenie (szczegóły w `tools/godot/README.md`). To samo narzędzie daje
podglądy tekstur i makiety: `tools/art/preview_textures.py`.

## Testy

```bash
chmod +x run_tests.sh
GODOT=/ścieżka/do/godot ./run_tests.sh
```

Skrypt uruchamia siedem testów (`tests/test_map.gd`, `tests/test_campaign.gd`,
`tests/test_battle.gd`, `tests/test_save.gd`, `tests/test_playthrough.gd`,
`tests/test_textures.gd`, `tests/test_views.gd`) i obie sceny, a na końcu
wypisuje `RESULT: PASS` albo `RESULT: FAIL`.

* `test_map` — determinizm generatora i zgodność z `tests/ref_map.json`.
* `test_campaign` — ekonomia, marsz, zwiad, przeprawy, rozliczenie bitwy, zwycięstwo.
* `test_battle` — broń, osłona, miny, organizacja, wyniki bitwy.
* `test_save` — zapis i odczyt stanu kampanii.
* `test_playthrough` — cała rozgrywka bez okna: bot maszeruje do celów, rozgrywa
  bitwy prawdziwym symulatorem, rozlicza je i w trakcie kampanii robi zapis/odczyt.
* `test_textures` — wszystkie kafle i materiały mają właściwy rozmiar
  (16×16 kafle mapy, 512×512 teren, 256×256 otoczenie i sprzęt, 128×128 ikony),
  nic nie wypadło z palety ani z nazw plików.
* `test_views` — składa obie sceny jak gra i sprawdza, że sylwetki pojazdów
  mają komplet brył, a materiały naprawdę niosą tekstury AI.

Pojedynczy test:

```bash
timeout 180 $GODOT --headless --path . -s res://tests/test_battle.gd
```

Plik `tests/ref_map.json` to wzorzec map dla seedów 1, 7, 19, 42 i 123456 —
odtwarza się go skryptem `godot --headless --path . -s res://tests/gen_ref_map.gd`.

## Struktura projektu

```
project.godot              ustawienia (scena główna: scenes/campaign.tscn, 1280×720)
scenes/campaign.tscn       mapa kampanii (Node2D + scripts/campaign_view.gd)
scenes/battle.tscn         bitwa FPS (Node3D + scripts/battle/battle_view.gd)
scripts/game_state.gd      stan między scenami, zapis/odczyt slotu
scripts/campaign_view.gd   rysowanie mapy, HUD, dziennik, sterowanie
scripts/battle/battle_sim.gd   logika bitwy (broń, AI, miny, wyniki)
scripts/battle/battle_view.gd  świat 3D bitwy, kamera, HUD
scripts/logic/rng.gd       mulberry32 (ten sam seed = ta sama mapa)
scripts/logic/terrain.gd   rodzaje terenu, koszty, przechodniość
scripts/logic/map_gen.gd   generator mapy 60×40
scripts/logic/fog.gd       mgła wojny
scripts/logic/pathfind.gd  trasy (A*, 8 kierunków)
scripts/logic/units_data.gd    jednostki USA i ZSRR, limity oddziału
scripts/logic/army.gd      skład armii, walidacja, siła oddziału
scripts/logic/difficulty.gd    trudność rosnąca z dniami
scripts/logic/daynight.gd  doba, widoczność i przygaszenie nocą
scripts/logic/ferry.gd     łodzie przy brzegu i budowa mostu
scripts/logic/enemy.gd     oddziały wroga: cele, trasy, ruch
scripts/logic/campaign.gd  kampania: czas, ekonomia, cele, zwiad, zapis
scripts/logic/game_textures.gd     ładowanie tekstur terenu i otoczenia (bez importu)
assets/textures/terrain/   tekstury terenu 512×512 + kafle mapy 16×16 (grafika AI)
assets/textures/props/     tekstury otoczenia bitwy 256×256 (grafika AI)
tools/art/                 pipeline tekstur: przetwarzanie i podglądy
tests/                     testy logiki + wzorzec map
tests/test_playthrough.gd  pełna rozgrywka bez okna (bot + bitwy + zapis)
tests/test_textures.gd     kompletność i rozmiary tekstur (teren, otoczenie, sprzęt, ikony)
tests/test_views.gd        składanie scen: sylwetki jednostek i etykiety HUD
```

## Czego jeszcze nie ma

* Modeli pojazdów (siatki z gąsienicami, kołami i lufą) — dziś sylwetki składają
  się z brył z teksturami AI, więc są kanciaste.
* Ikon samego HUD (pasek stanu, wskaźnik broni) — na razie tylko tekst.
* Dźwięku (do przeniesienia z wersji TypeScript projektu).
* Eksportu web (wymaga szablonów eksportu Godota 4.7).
* Strojenia balansu — wartości startowe nie były jeszcze grane „na żywo”.
