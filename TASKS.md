# TASKS — Zimna Wojna 1975 (Godot 4.7)

Stan na **2026-10-15**. Wersja TypeScript projektu (`/home/user/cold-war-1975/`)
pozostaje nietknięta i nie jest częścią tego repozytorium.

## Zrobione

### Etap 0 — fundament
- [x] `project.godot` (Godot 4.7, scena główna `res://scenes/campaign.tscn`, 1280×720)
- [x] `scenes/campaign.tscn` (Node2D) i `scenes/battle.tscn` (Node3D)
- [x] `scripts/game_state.gd` — stan między scenami, `ensure_demo()`, zapis/odczyt slotu
- [x] `scripts/logic/rng.gd` — mulberry32; ten sam seed daje tę samą mapę

### Etap 1 — mapa i poruszanie się
- [x] `scripts/logic/terrain.gd` — 13 rodzajów terenu, koszty, przechodniość
- [x] `scripts/logic/map_gen.gd` — generator 60×40: góry, jeziora, rzeka z brodami,
      lasy, wzgórza, bagna, piasek, śnieg, 8 miast, drogi i mosty
- [x] `scripts/logic/fog.gd` — mgła wojny (nieznane / zbadane / widoczne)
- [x] `scripts/logic/pathfind.gd` — A* po 8 kierunkach, `path_cost`

### Etap 2 — armia
- [x] `scripts/logic/units_data.gd` — jednostki USA i ZSRR z 1975 r. + prototypy
      (`us_proto_xm803`, `su_proto_775`), limity 30 / 2 / 5
- [x] `scripts/logic/army.gd` — losowe składy, `validate`, siła oddziału
- [x] `scripts/logic/difficulty.gd` — trudność rosnąca z dniami (sufit 2,5)
- [x] `scripts/logic/daynight.gd` — doba, widoczność, przygaszenie nocą

### Etap 3 — kampania
- [x] `scripts/logic/ferry.gd` — łodzie przy brzegu, przeprawa, budowa mostu
- [x] `scripts/logic/enemy.gd` — osobowości, cele, planowanie i ruch wroga
- [x] `scripts/logic/campaign.gd` — czas, żywność, fundusze, morale, cele (3 miasta
      × 12 h), zwiad, kontakty, rozliczenie bitwy, zapis wersji 1

### Etap 4 — widok kampanii
- [x] `scripts/campaign_view.gd` — mapa z mgłą, cele, łodzie, znaczniki zwiadu,
      HUD (stan, dziennik z 6 wpisami, pomoc), wszystkie klawisze z README

### Etap 5 — testy
- [x] `tests/test_map.gd` (+ `tests/ref_map.json`, `tests/gen_ref_map.gd`)
- [x] `tests/test_campaign.gd`
- [x] `tests/test_save.gd`
- [x] `tests/test_playthrough.gd` — cała rozgrywka bez okna: bot maszeruje do celów,
      rozgrywa bitwy symulatorem, robi zapis/odczyt w trakcie kampanii
- [x] `run_tests.sh` — siedem testów + sceny, wynik `RESULT: PASS/FAIL`
- [x] **Uruchomione na prawdziwym Godocie 4.7.2: `RESULT: PASS`** (2026-10-15)

### Etap 6 — bitwa FPS
- [x] `scripts/battle/battle_sim.gd` — 4 rodzaje broni, wybór broni, osłona terenu,
      noc, miny, dowódcy, organizacja, AI, wsiadanie do pojazdu, odwrót, wyniki
- [x] `scripts/battle/battle_view.gd` — świat 3D (grunt, drzewa, skały, budynki),
      kamera pierwszej osoby, HUD, pauza, powrót do kampanii
- [x] `tests/test_battle.gd`

### Etap 7 — grafika AI (teren)
- [x] 13 tekstur terenu (stylizowana mapa sztabowa z lotu ptaka) w dwóch rozmiarach:
      512×512 na materiały 3D i 16×16 na kafle mapy — `assets/textures/terrain/`
- [x] kolor każdej tekstury sprowadzony programowo do palety z `campaign_view.gd`
      (korekta średniej + przemalowanie w palecie), więc 13 osobnych obrazów
      czyta się jak jedna mapa
- [x] `scripts/logic/terrain_textures.gd` — loader bez importu zasobów
      (`Image.load_from_file`), z powrotem do kolorów, gdy pliku brak
- [x] kafle wpięte w mapę kampanii (mgła przygasza je tak samo jak kolory),
      tekstura gruntu wpięta w bitwę 3D (1000×400 m, powtarzana co ~50 m)
- [x] `tools/art/process_terrain.py` i `tools/art/preview_terrain.py` +
      `assets/textures/terrain/README.md` (paleta, prompty, odtwarzanie)
- [x] `tests/test_terrain_textures.gd` — 13 kafli 16×16 i 13 materiałów 512×512
- [x] 5 tekstur otoczenia bitwy (256×256): kora pnia, korona drzewa, skała,
      ściana bloku i dach — drzewa, skały i budynki w bitwie mają materiały
      z teksturami (a nie płaskie kolory), z powrotem do kolorów przy braku pliku
- [x] wspólny rdzeń pipeline'u `tools/art/pipeline.py` (teren i otoczenie robią
      identyczne dopasowanie kolorystyki); refaktor sprawdzony bajt w bajt —
      skrót wszystkich plików terenu identyczny przed i po
- [x] `scripts/logic/game_textures.gd` obsługuje teren i otoczenie,
      `tests/test_textures.gd` pilnuje obu zestawów
- [x] 2 tekstury sprzętu (256×256): mundur piechoty i pancerz pojazdu — jasne
      i neutralne, bo materiał mnoży je przez kolor strony, więc gracz/sojusznik/wróg
      zostają rozróżnialni, a detal pochodzi z tekstury
- [x] 6 ikon mapy (128×128, RGBA): gracz, wróg, cel, miasto, łódź, zwiadowca —
      wycięte z magentowego tła (`tools/art/process_icons.py`) z usunięciem
      różowej obwódki, przycięte do treści i przeskalowane pod skalę mapy
- [x] `campaign_view.gd` rysuje ikony, a przy braku pliku wraca do dawnych
      kształtów (trójkąt gracza, kwadrat wroga, kółko łodzi itd.)
- [x] `battle_view.gd` daje piechurom mundur, a pojazdom pancerz (materiał:
      tekstura × kolor strony); `tests/test_textures.gd` pilnuje obu zestawów,
      w tym przezroczystości ikon
- [x] sylwetki pojazdów z 256/128 brył, wzorowane na prawdziwych wozach 1975:
      czołg 256 brył (pochyła płyta pancerza, błotniki z fartuchami, gąsienice
      z ogniwami, 5 kół jezdnych + rolki powrotne na stronę, wieża z jarzmem,
      lufa z wylotem, włazy, anteny, reflektory, narzędzia, beczki/zasobniki),
      wóz bojowy 128 brył, piechur 10 brył (ciało, hełm, plecak, kończyny, broń)
- [x] dwa warianty sylwetki: NATO (wieża skrzynkowa — M48A5/M60A1) i ZSRR
      (kopuła odlewana — T-55/T-62), wybierane po stronie jednostki
- [x] wspólne materiały brył (`_material_cache` w `battle_view.gd`) — bitwa
      z tysiącem brył tworzy ~30 materiałów zamiast ~2300
- [x] tekstura ogniw gąsienicy (3. tekstura sprzętu, `track`)
- [x] `tests/test_views.gd` — składa obie sceny jak gra i sprawdza dokładną
      liczbę brył sylwetek (piechur 10, wóz 128, czołg 256), różnice między
      wariantami NATO/ZSRR, to że materiały naprawdę mają tekstury AI i że są
      dzielone (≤ 64 unikalnych materiałów w scenie bitwy)
- [x] podgląd brył bez okna graficznego: `tools/godot/dump_meshes.gd` zrzuca
      geometrię z `battle_view.gd` (256/128/10 brył), a `tools/art/render_units.py`
      renderuje ją w Pythonie (numpy + Pillow) — kształt, barwy i tekstury 1:1
      z gry, oświetlenie i rzut są przybliżeniem
- [x] `makieta_pojazdow.png` to rzut techniczny **prawdziwych brył** z tego
      zrzutu (rysowany w `preview_textures.py`), więc nie może się rozjechać
      z kodem
- [x] **osobna geometria dla każdego wozu** (nie dwa warianty stron): osiem
      funkcji budujących — `_patton_parts` (M48A5: okrągły nos odlewu / M60A1:
      klinowy nos + reflektor AN/VSS-1), `_sheridan_parts` (M551: niski, pięć
      kół, napęd z przodu), `_t54_parts` (T-55: 100 mm / T-62: 115 mm),
      `_t72_parts` (125 mm, snorkiel, najniższa kopuła), `_m113_parts` (M113
      i wozówka M577), `_btr60_parts` (cztery osie na stronę), `_bmp1_parts`
      (działo 73 mm + 9M14), `_mtlb_parts` (mała wieżyczka, most MTU-20)
- [x] **barwy fabryczne zamiast koloru strony**: olive drab USA i zieleń 4BO
      ZSRR (kolory rozjaśnione, bo poprzednie rendery wychodziły niemal czarne);
      przynależność w bitwie pokazuje pierścień na ziemi
- [x] **oznaczenia państwowe na pancerzu**: `assets/textures/markings/`
      (`star_us.png`, `star_su.png`, 128×128 RGBA, generator
      `tools/art/make_markings.py`), w `game_textures.gd` klucz `marking`,
      w `battle_view.gd` `_star_plate()` — płaska gwiazda na dachu (identyfikacja
      z powietrza, jak w rzeczywistości) plus gwiazdy na burtach wieży i kadłuba;
      `_part_marking()` przyjmuje rozmiar, pozycję, obrót i klucz tekstury
- [x] gwiazdy powstają **przed** gąsienicami w każdej funkcji budującej —
      `_fit_parts()` dopełnia i ucina od końca listy, więc dokładane na końcu
      oznaczenia były po cichu ucinane (czołgi miały 0 gwiazd)
- [x] zrzut rozszerzony do 13 wozów (`dump_meshes.gd`, 2 196 brył), render
      `render_units.py` daje pięć obrazów: park czołgów, wozy bojowe, cztery
      ujęcia M60A1 (z gwiazdą na dachu widoczną z góry), barwy fabryczne
      i jednostki w jednej skali; `preview_textures.py` rysuje gwiazdy
      w makiecie (białe USA, czerwone ZSRR) i wybiera wozy po `def_id`
- [ ] modele siatkowe pojazdów (dziś kanciaste bryły) i ikony samego HUD

## Naprawione po pierwszym uruchomieniu testów (2026-10-15)

- `map_gen.gd`: `static func _get/_set` kolidowały z wirtualnymi metodami `Object`
  (błąd parsowania) — zmienione na `_tile_at` / `_put_tile`.
- `map_gen.gd`: brzegi i drogi zamieniały **brody** w piach/bagno/asfalt, więc
  dwa z pięciu seedów nie miały żadnej przeprawy przez rzekę; brody i mosty są
  teraz chronione (strumień RNG celowo się nie zmienił, więc mapa z danego
  seeda pozostaje ta sama poza odzyskanymi brodami).
- `ferry.gd`: rozdzielono czyste `find_span()` / `can_build_bridge()` od
  `build_bridge()` (który jawnie zmienia mapę). `campaign.can_build_bridge()`
  pyta teraz o to samo, co naprawdę da się zbudować — wcześniej sprawdzał wodę
  tylko w 4 kierunkach, a most stawiano w 8, więc podpowiedź bywała nieprawdziwa.
- `tests/test_map.gd`: Godot 4.7 zwraca z JSON tablice `Array[float]`, więc
  porównanie `[x, y] == tablica_z_pliku` zawsze kończyło się porażką — test
  porównuje teraz wartości liczbowe.
- `tests/test_campaign.gd`: szukanie brzegu budowało most na prawdziwej mapie
  (efekt uboczny), a test marszu przerywał się, gdy w trakcie drogi pojawił się
  nowy oddział wroga — oba testy poprawione.

## Do zrobienia (wymaga decyzji albo kolejnej sesji)

1. **Do potwierdzenia przez użytkownika**
   - Dowódca to osobny piechur, nie gracz — tak jest zaimplementowane.
   - Śmierć gracza kończy bitwę porażką, nawet gdy sojusznicy żyją — tak jest zaimplementowane.
2. **Grafika (AI)** — teren, otoczenie, sprzęt, sylwetki pojazdów i ikony mapy
   gotowe (etap 7); zostają modele siatkowe pojazdów i ikony samego HUD.
3. **Dźwięk** — do przeniesienia z wersji TypeScript (nie ma go w tym repo).
4. **Eksport web** — potrzebne szablony eksportu Godota 4.7.2 (nie pobrane).
5. **Balans** — wartości broni i ekonomii są startowe; wymagają partii testowych.
6. **Przegląd wizualny** — widoki 2D i 3D sprawdzone tylko bez okna (`--headless`).
7. **Rozmiar workspace** — binarka Godota (192 MB) leży poza projektem,
   spakowana do 74 MB w `/home/user/tools/godot/Godot_v4.7.2-stable_linux.x86_64.gz`.
   Do repo nie trafia; przed użyciem: `gunzip -k` (patrz README).

## Uwagi o tej sesji (2026-10-15)

- Workspace był **pusty**: nie istniały ani `/home/user/cold-war-godot/`,
  ani `/home/user/cold-war-1975/` (wersja TS), ani `/home/user/tools/godot/`,
  ani kopia zapasowa. Wszystkie pliki projektu odtworzono w tej sesji zgodnie
  ze specyfikacją i API testów.
- Binarka Godota 4.7.2 została zbudowana ze źródeł pobranych z GitHuba
  (wydanie oficjalne 4.7.2-stable, `scons platform=linuxbsd target=editor`,
  ~2800 jednostek kompilacji) — bo wydania GitHub nie dają się w tym środowisku
  pobrać. Wynik: `4.7.2.stable.custom_build`, działa bez okna.
- Wszystkie testy i obie sceny zostały faktycznie uruchomione na tej binarke:
  siedem testów = PASS, sceny `campaign` i `battle` startują bez błędów
  skryptów (`--quit-after 300`).
- Liczba testów wzrosła do siedmiu: `test_textures` pilnuje kompletu tekstur,
  a `test_views` składa obie sceny i sprawdza sylwetki jednostek (dokładne
  liczby brył, unikalne proporcje wozów, brak gąsienic w BTR-60PB) oraz HUD.
  Stan na koniec etapu grafiki: 9 jednostek, `{piechur 10, wóz 128, czołg 256}`
  brył, 513 brył z teksturą AI, 33 unikalne materiały (limit 64).
- Analiza statyczna całego projektu (`@gdscript-analyzer/core` 0.6.1):
  **0 błędów, 0 ostrzeżeń** (pole `seed` w `campaign.gd` zmienione na
  `world_seed`, żeby nie przesłaniało globalnej funkcji `seed()`; klucz w pliku
  zapisu pozostał `"seed"`).
- `tests/ref_map.json` jest wzorcem **wygenerowanym przez obecną implementację**
  (wersja TS z danymi referencyjnymi nie jest dostępna w tym workspace), więc
  test mapy pilnuje determinizmu i braku przypadkowych zmian generatora.
