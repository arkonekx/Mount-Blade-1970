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
- [x] `run_tests.sh` — pięć testów + sceny, wynik `RESULT: PASS/FAIL`
- [x] **Uruchomione na prawdziwym Godocie 4.7.2: `RESULT: PASS`** (2026-10-15)

### Etap 6 — bitwa FPS
- [x] `scripts/battle/battle_sim.gd` — 4 rodzaje broni, wybór broni, osłona terenu,
      noc, miny, dowódcy, organizacja, AI, wsiadanie do pojazdu, odwrót, wyniki
- [x] `scripts/battle/battle_view.gd` — świat 3D (grunt, drzewa, skały, budynki),
      kamera pierwszej osoby, HUD, pauza, powrót do kampanii
- [x] `tests/test_battle.gd`

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
2. **Tekstury i ikony (AI)** — obecnie wyłącznie prymitywy i kolory. Grafika ma
   być generowana AI w stylu stylizowanym; czeka na zgodę użytkownika.
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
  pięć testów logiki = PASS, sceny `campaign` i `battle` startują bez błędów
  skryptów (`--quit-after 300`).
- Analiza statyczna całego projektu (`@gdscript-analyzer/core` 0.6.1):
  **0 błędów, 0 ostrzeżeń** (pole `seed` w `campaign.gd` zmienione na
  `world_seed`, żeby nie przesłaniało globalnej funkcji `seed()`; klucz w pliku
  zapisu pozostał `"seed"`).
- `tests/ref_map.json` jest wzorcem **wygenerowanym przez obecną implementację**
  (wersja TS z danymi referencyjnymi nie jest dostępna w tym workspace), więc
  test mapy pilnuje determinizmu i braku przypadkowych zmian generatora.
