extends SceneTree
## Test 1: determinizm generatora mapy i zgodność z tests/ref_map.json.
##
## Uruchomienie:
##   godot --headless --path . -s res://tests/test_map.gd
##
## Plik referencyjny odtwarza się skryptem: godot --headless --path . -s res://tests/gen_ref_map.gd

const MapGen = preload("res://scripts/logic/map_gen.gd")
const Terrain = preload("res://scripts/logic/terrain.gd")
const RNG = preload("res://scripts/logic/rng.gd")
const Enemy = preload("res://scripts/logic/enemy.gd")

const SEEDS: Array = [1, 7, 19, 42, 123456]
const REF_PATH := "res://tests/ref_map.json"
const W := 60
const H := 40

var failures: Array = []


func _initialize() -> void:
	print("== test_map ==")
	_test_rng()
	_test_reference()
	_test_sanity()
	_report()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		print("  BŁĄD: %s" % message)


func _test_rng() -> void:
	var first := RNG.new(42)
	var second := RNG.new(42)
	var same: bool = true
	for i in range(1000):
		if first.next() != second.next():
			same = false
			break
	_check(same, "RNG: ten sam seed daje różne liczby")
	_check(RNG.new(42).next() != RNG.new(43).next(), "RNG: różne seedy dają tę samą liczbę")
	var value: float = RNG.new(123456).next()
	_check(value >= 0.0 and value < 1.0, "RNG: next() poza zakresem [0, 1)")
	var ranged := RNG.new(7)
	for i in range(300):
		var v: int = ranged.int_range(3, 9)
		if v < 3 or v > 9:
			_check(false, "RNG: int_range poza zakresem")
			break


func _test_reference() -> void:
	var file := FileAccess.open(REF_PATH, FileAccess.READ)
	if file == null:
		_check(false, "Brak pliku %s (uruchom gen_ref_map.gd)" % REF_PATH)
		return
	var text: String = file.get_as_text()
	file.close()
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		_check(false, "Nie można odczytać %s" % REF_PATH)
		return
	var seeds: Dictionary = data["seeds"]

	for seed_value in SEEDS:
		var key: String = str(int(seed_value))
		if not seeds.has(key):
			_check(false, "Brak seedu %s w ref_map.json" % key)
			continue
		var expected: Dictionary = seeds[key]
		var generated: Dictionary = MapGen.generate(int(seed_value), W, H)
		var tiles: PackedByteArray = generated["tiles"]
		_check(Marshalls.raw_to_base64(tiles) == str(expected["tiles"]), "Seed %s: mapa różni się od wzorca" % key)

		# JSON zwraca tablice zmiennoprzecinkowe, więc porównujemy wartości liczbowe.
		var start: Vector2i = generated["start"]
		var want_start: Array = expected["start"]
		_check(start.x == int(want_start[0]) and start.y == int(want_start[1]), "Seed %s: inne pole startowe" % key)

		var cities: Array = generated["cities"]
		var expected_cities: Array = expected["cities"]
		_check(cities.size() == expected_cities.size(), "Seed %s: inna liczba miast" % key)
		for i in range(mini(cities.size(), expected_cities.size())):
			var got: Dictionary = cities[i]
			var want: Dictionary = expected_cities[i]
			var same: bool = int(got["x"]) == int(want["x"]) and int(got["y"]) == int(want["y"]) and str(got["name"]) == str(want["name"])
			if not same:
				_check(false, "Seed %s: miasto %d różni się od wzorca" % [key, i])

		# Powtórne losowanie musi dać identyczną mapę (brak stanu globalnego).
		var again: Dictionary = MapGen.generate(int(seed_value), W, H)
		var again_tiles: PackedByteArray = again["tiles"]
		_check(again_tiles == tiles, "Seed %s: generator nie jest deterministyczny" % key)


func _test_sanity() -> void:
	for seed_value in SEEDS:
		var m: Dictionary = MapGen.generate(int(seed_value), W, H)
		var tiles: PackedByteArray = m["tiles"]
		var start: Vector2i = m["start"]
		var cities: Array = m["cities"]
		var key: String = str(int(seed_value))

		_check(tiles.size() == W * H, "Seed %s: zły rozmiar mapy" % key)
		_check(Terrain.is_passable(tiles[start.y * W + start.x]), "Seed %s: start jest nieprzechodni" % key)
		_check(cities.size() >= 6, "Seed %s: za mało miast (%d)" % [key, cities.size()])
		_check(start == Vector2i(int(cities[0]["x"]), int(cities[0]["y"])), "Seed %s: start poza miastem numer 0" % key)

		var far_cities: int = 0
		for i in range(1, cities.size()):
			var c: Dictionary = cities[i]
			var p := Vector2i(int(c["x"]), int(c["y"]))
			_check(tiles[p.y * W + p.x] == Terrain.Kind.CITY, "Seed %s: miasto %s nie ma kafelka miasta" % [key, str(c["name"])])
			var dist: int = Enemy.chebyshev(p, start)
			if dist >= 15:
				far_cities += 1
		_check(far_cities >= 3, "Seed %s: mniej niż 3 miasta w odległości 15 pól (jest %d)" % [key, far_cities])

		var water: int = 0
		var fords: int = 0
		var roads: int = 0
		var bridges: int = 0
		for i in range(tiles.size()):
			var kind: int = tiles[i]
			if Terrain.is_water(kind):
				water += 1
			elif kind == Terrain.Kind.FORD:
				fords += 1
			elif kind == Terrain.Kind.ROAD:
				roads += 1
			elif kind == Terrain.Kind.BRIDGE:
				bridges += 1
		_check(water > 40, "Seed %s: za mało wody (%d pól)" % [key, water])
		_check(fords >= 1, "Seed %s: brak brodu" % key)
		_check(roads > 60, "Seed %s: za mało dróg (%d pól)" % [key, roads])


func _report() -> void:
	if failures.is_empty():
		print("Wszystkie sprawdzenia mapy przeszły.")
		print("RESULT: PASS")
		quit(0)
		return
	print("Niepowodzenia: %d" % failures.size())
	print("RESULT: FAIL")
	quit(1)
