extends RefCounted
## Generator mapy kampanii: ten sam seed zawsze daje tę samą mapę.
##
## Wynik: słownik {w, h, tiles, start, cities}, gdzie
##   tiles  - PackedByteArray z rodzajami terenu (scripts/logic/terrain.gd),
##   start  - Vector2i pola startowego gracza (miasto numer 0),
##   cities - tablica słowników {x, y, name}.

const RNG = preload("res://scripts/logic/rng.gd")
const Terrain = preload("res://scripts/logic/terrain.gd")

const CITY_COUNT := 8
const MIN_CITY_DIST := 7
const RELAXED_CITY_DIST := 5
const FAR_CITY_DIST := 15

const CITY_NAMES: Array = [
	"Warszawa", "Kraków", "Gdańsk", "Poznań", "Wrocław",
	"Łódź", "Szczecin", "Lublin", "Katowice", "Bydgoszcz",
	"Rzeszów", "Olsztyn", "Kielce", "Toruń",
]


static func generate(seed_value: int, w: int = 60, h: int = 40) -> Dictionary:
	var rng = RNG.new(seed_value)
	var tiles := PackedByteArray()
	tiles.resize(w * h)
	for i in range(tiles.size()):
		tiles[i] = Terrain.Kind.PLAINS

	_carve_snow(tiles, w, rng)
	_carve_mountains(tiles, w, h, rng)
	_carve_lakes(tiles, w, h, rng)
	_carve_river(tiles, w, h, rng)
	_carve_forests(tiles, w, h, rng)
	_carve_hills(tiles, w, h, rng)
	_carve_shores(tiles, w, h, rng)

	var cities: Array = _place_cities(tiles, w, h, rng)
	_connect_roads(tiles, w, h, cities, rng)

	var start := Vector2i(int(cities[0]["x"]), int(cities[0]["y"]))
	return {"w": w, "h": h, "tiles": tiles, "start": start, "cities": cities}


# --- pomocnicze operacje na polach -------------------------------------------


static func _in_bounds(w: int, h: int, p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < w and p.y < h


static func _tile_at(tiles: PackedByteArray, w: int, p: Vector2i) -> int:
	return tiles[p.y * w + p.x]


static func _put_tile(tiles: PackedByteArray, w: int, p: Vector2i, kind: int) -> void:
	tiles[p.y * w + p.x] = kind


static func _is_land(kind: int) -> bool:
	return kind != Terrain.Kind.LAKE and kind != Terrain.Kind.RIVER and kind != Terrain.Kind.MOUNTAIN


static func _chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


# --- etapy generowania -------------------------------------------------------


static func _carve_snow(tiles: PackedByteArray, w: int, rng) -> void:
	for y in range(0, 3):
		for x in range(w):
			if rng.next() < 0.72 - float(y) * 0.22:
				_put_tile(tiles, w, Vector2i(x, y), Terrain.Kind.SNOW)


static func _carve_mountains(tiles: PackedByteArray, w: int, h: int, rng) -> void:
	var ridges: int = rng.int_range(2, 3)
	for r in range(ridges):
		var p := Vector2i(rng.int_range(6, w - 7), rng.int_range(5, h - 6))
		var steps: int = rng.int_range(16, 28)
		var dx: int = rng.pick([-1, 1])
		for s in range(steps):
			var blob: int = rng.int_range(1, 2)
			for oy in range(-blob, blob + 1):
				for ox in range(-blob, blob + 1):
					var q := Vector2i(p.x + ox, p.y + oy)
					if not _in_bounds(w, h, q):
						continue
					if rng.next() < 0.75:
						_put_tile(tiles, w, q, Terrain.Kind.MOUNTAIN)
			if rng.next() < 0.3:
				dx = -dx
			p = Vector2i(clampi(p.x + dx, 2, w - 3), clampi(p.y + rng.int_range(-1, 1), 2, h - 3))


static func _carve_lakes(tiles: PackedByteArray, w: int, h: int, rng) -> void:
	var lakes: int = rng.int_range(1, 2)
	for l in range(lakes):
		var center := Vector2i(rng.int_range(10, w - 11), rng.int_range(7, h - 8))
		var radius: float = float(rng.int_range(3, 5))
		var rx: float = radius * rng.float_range(0.9, 1.5)
		var ry: float = radius * rng.float_range(0.7, 1.1)
		var span: int = int(ceil(maxf(rx, ry))) + 1
		for oy in range(-span, span + 1):
			for ox in range(-span, span + 1):
				var q := Vector2i(center.x + ox, center.y + oy)
				if not _in_bounds(w, h, q):
					continue
				var nx: float = float(ox) / rx
				var ny: float = float(oy) / ry
				if nx * nx + ny * ny <= 1.0 + rng.float_range(-0.12, 0.12):
					_put_tile(tiles, w, q, Terrain.Kind.LAKE)


static func _carve_river(tiles: PackedByteArray, w: int, h: int, rng) -> void:
	var x: int = rng.int_range(5, w - 6)
	var river_tiles: Array = []
	for y in range(1, h - 1):
		if rng.next() < 0.45:
			x = clampi(x + rng.pick([-1, 1]), 4, w - 5)
		var p := Vector2i(x, y)
		if _tile_at(tiles, w, p) != Terrain.Kind.LAKE:
			_put_tile(tiles, w, p, Terrain.Kind.RIVER)
		river_tiles.append(p)
	# dwa brody w środkowej części rzeki
	var fords: int = rng.int_range(1, 2)
	for f in range(fords):
		if river_tiles.is_empty():
			break
		var margin: int = int(river_tiles.size() / 5.0)
		var idx: int = rng.int_range(margin, river_tiles.size() - margin - 1)
		var fp: Vector2i = river_tiles[clampi(idx, 0, river_tiles.size() - 1)]
		_put_tile(tiles, w, fp, Terrain.Kind.FORD)


static func _carve_forests(tiles: PackedByteArray, w: int, h: int, rng) -> void:
	var count: int = rng.int_range(8, 11)
	for i in range(count):
		var center := Vector2i(rng.int_range(3, w - 4), rng.int_range(4, h - 5))
		var radius: int = rng.int_range(2, 4)
		for oy in range(-radius, radius + 1):
			for ox in range(-radius, radius + 1):
				var q := Vector2i(center.x + ox, center.y + oy)
				if not _in_bounds(w, h, q):
					continue
				if absi(ox) + absi(oy) > radius + 1:
					continue
				if rng.next() < 0.2:
					continue
				var kind: int = _tile_at(tiles, w, q)
				if kind == Terrain.Kind.PLAINS or kind == Terrain.Kind.SAND or kind == Terrain.Kind.SNOW or kind == Terrain.Kind.HILLS:
					_put_tile(tiles, w, q, Terrain.Kind.FOREST)


static func _carve_hills(tiles: PackedByteArray, w: int, h: int, rng) -> void:
	var count: int = rng.int_range(5, 8)
	for i in range(count):
		var center := Vector2i(rng.int_range(3, w - 4), rng.int_range(4, h - 5))
		var radius: int = rng.int_range(1, 3)
		for oy in range(-radius, radius + 1):
			for ox in range(-radius, radius + 1):
				var q := Vector2i(center.x + ox, center.y + oy)
				if not _in_bounds(w, h, q):
					continue
				if absi(ox) + absi(oy) > radius:
					continue
				var kind: int = _tile_at(tiles, w, q)
				if kind == Terrain.Kind.PLAINS or kind == Terrain.Kind.FOREST or kind == Terrain.Kind.SAND:
					if rng.next() < 0.7:
						_put_tile(tiles, w, q, Terrain.Kind.HILLS)


static func _carve_shores(tiles: PackedByteArray, w: int, h: int, rng) -> void:
	for y in range(h):
		for x in range(w):
			var p := Vector2i(x, y)
			var kind: int = _tile_at(tiles, w, p)
			if not _is_land(kind) or kind == Terrain.Kind.MOUNTAIN:
				continue
			var near_water: bool = false
			for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = p + dir
				if not _in_bounds(w, h, q):
					continue
				if Terrain.is_water(_tile_at(tiles, w, q)):
					near_water = true
					break
			if not near_water:
				continue
			# Losujemy zawsze, żeby strumień RNG nie zależał od rodzaju pola —
			# dzięki temu zachowanie generatora dla danego seeda jest stabilne.
			var roll: float = rng.next()
			# Brody i mosty to celowe przeprawy — nie zamieniamy ich w piach ani bagno.
			if kind == Terrain.Kind.FORD or kind == Terrain.Kind.BRIDGE:
				continue
			if roll < 0.28:
				_put_tile(tiles, w, p, Terrain.Kind.SAND)
			elif roll < 0.45 and kind != Terrain.Kind.SAND:
				_put_tile(tiles, w, p, Terrain.Kind.MARSH)


# --- miasta ------------------------------------------------------------------


static func _is_city_spot(tiles: PackedByteArray, w: int, h: int, p: Vector2i) -> bool:
	var kind: int = _tile_at(tiles, w, p)
	if kind != Terrain.Kind.PLAINS and kind != Terrain.Kind.SAND and kind != Terrain.Kind.FOREST and kind != Terrain.Kind.SNOW and kind != Terrain.Kind.HILLS:
		return false
	# miasto potrzebuje przechodniego sąsiedztwa
	var open: int = 0
	for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var q: Vector2i = p + dir
		if _in_bounds(w, h, q) and Terrain.is_passable(_tile_at(tiles, w, q)):
			open += 1
	return open >= 3


static func _place_cities(tiles: PackedByteArray, w: int, h: int, rng) -> Array:
	var names: Array = CITY_NAMES.duplicate()
	rng.shuffle(names)
	var cities: Array = []
	var used_names: int = 0

	# Miasto startowe: lewa część mapy, żeby wróg nie stał graczowi na głowie.
	var candidates: Array = []
	for y in range(6, h - 6):
		for x in range(3, maxi(4, int(w / 3.0))):
			var p := Vector2i(x, y)
			if _is_city_spot(tiles, w, h, p):
				candidates.append(p)
	var start_pos: Vector2i = Vector2i(6, int(h / 2.0))
	if not candidates.is_empty():
		start_pos = rng.pick(candidates)
	cities.append({"x": start_pos.x, "y": start_pos.y, "name": names[used_names]})
	used_names += 1

	# Pozostałe miasta: rozrzucone, z minimalnym odstępem.
	var attempts: int = 0
	var min_dist: int = MIN_CITY_DIST
	while cities.size() < CITY_COUNT and attempts < 6000:
		attempts += 1
		if attempts == 2500:
			min_dist = RELAXED_CITY_DIST
		if attempts == 4500:
			min_dist = 4
		var p := Vector2i(rng.int_range(3, w - 4), rng.int_range(3, h - 4))
		if not _is_city_spot(tiles, w, h, p):
			continue
		var ok: bool = true
		for c in cities:
			if _chebyshev(p, Vector2i(int(c["x"]), int(c["y"]))) < min_dist:
				ok = false
				break
		if not ok:
			continue
		cities.append({"x": p.x, "y": p.y, "name": names[used_names % names.size()]})
		used_names += 1

	# Cele kampanii muszą leżeć daleko od startu: dokładamy miasta w dalszej części mapy.
	var attempts_far: int = 0
	while _far_city_count(cities, start_pos) < 3 and attempts_far < 3000:
		attempts_far += 1
		var x: int = rng.int_range(clampi(start_pos.x + FAR_CITY_DIST, 3, w - 4), w - 4)
		var y: int = rng.int_range(3, h - 4)
		var p := Vector2i(x, y)
		if not _is_city_spot(tiles, w, h, p):
			continue
		var ok: bool = true
		for c in cities:
			if _chebyshev(p, Vector2i(int(c["x"]), int(c["y"]))) < RELAXED_CITY_DIST:
				ok = false
				break
		if not ok:
			continue
		cities.append({"x": p.x, "y": p.y, "name": names[used_names % names.size()]})
		used_names += 1

	for c in cities:
		_put_tile(tiles, w, Vector2i(int(c["x"]), int(c["y"])), Terrain.Kind.CITY)
	return cities


static func _far_city_count(cities: Array, start_pos: Vector2i) -> int:
	var count: int = 0
	for i in range(1, cities.size()):
		var c: Dictionary = cities[i]
		if _chebyshev(Vector2i(int(c["x"]), int(c["y"])), start_pos) >= FAR_CITY_DIST:
			count += 1
	return count


# --- drogi -------------------------------------------------------------------


static func _connect_roads(tiles: PackedByteArray, w: int, h: int, cities: Array, rng) -> void:
	if cities.size() < 2:
		return
	var connected: Array = [0]
	while connected.size() < cities.size():
		var best_a: int = -1
		var best_b: int = -1
		var best_dist: int = 1 << 30
		for a in connected:
			var pa := Vector2i(int(cities[a]["x"]), int(cities[a]["y"]))
			for b in range(cities.size()):
				if connected.has(b):
					continue
				var pb := Vector2i(int(cities[b]["x"]), int(cities[b]["y"]))
				var dist: int = _chebyshev(pa, pb)
				if dist < best_dist:
					best_dist = dist
					best_a = a
					best_b = b
		if best_b < 0:
			break
		var from := Vector2i(int(cities[best_a]["x"]), int(cities[best_a]["y"]))
		var to := Vector2i(int(cities[best_b]["x"]), int(cities[best_b]["y"]))
		_carve_road(tiles, w, h, from, to, rng)
		connected.append(best_b)


static func _carve_road(tiles: PackedByteArray, w: int, h: int, from: Vector2i, to: Vector2i, rng) -> void:
	var p: Vector2i = from
	var guard: int = 0
	while p != to and guard < 3000:
		guard += 1
		var dx: int = signi(to.x - p.x)
		var dy: int = signi(to.y - p.y)
		var options: Array = []
		if absi(to.x - p.x) >= absi(to.y - p.y):
			if dx != 0:
				options.append(Vector2i(dx, 0))
			if dx != 0 and dy != 0:
				options.append(Vector2i(dx, dy))
			if dy != 0:
				options.append(Vector2i(0, dy))
		else:
			if dy != 0:
				options.append(Vector2i(0, dy))
			if dx != 0 and dy != 0:
				options.append(Vector2i(dx, dy))
			if dx != 0:
				options.append(Vector2i(dx, 0))
		if options.size() > 1 and rng.next() < 0.18:
			var tmp: Variant = options[0]
			options[0] = options[1]
			options[1] = tmp
		var moved: bool = false
		for opt in options:
			var next: Vector2i = p + opt
			if not _in_bounds(w, h, next):
				continue
			var kind: int = _tile_at(tiles, w, next)
			if kind == Terrain.Kind.MOUNTAIN or kind == Terrain.Kind.LAKE:
				continue
			p = next
			moved = true
			if kind == Terrain.Kind.RIVER:
				_put_tile(tiles, w, p, Terrain.Kind.BRIDGE)
			elif kind == Terrain.Kind.CITY or kind == Terrain.Kind.FORD:
				pass
			else:
				_put_tile(tiles, w, p, Terrain.Kind.ROAD)
			break
		if not moved:
			# Obejście przeszkody: zejdź w bok i próbuj dalej.
			var side: Vector2i = Vector2i.ZERO
			if absi(to.y - p.y) >= absi(to.x - p.x):
				side = Vector2i(1 if guard % 2 == 0 else -1, 0)
			else:
				side = Vector2i(0, 1 if guard % 2 == 0 else -1)
			var detour: Vector2i = p + side
			if not _in_bounds(w, h, detour):
				break
			var dkind: int = _tile_at(tiles, w, detour)
			if dkind == Terrain.Kind.MOUNTAIN or dkind == Terrain.Kind.LAKE:
				break
			p = detour
			if dkind == Terrain.Kind.RIVER:
				_put_tile(tiles, w, p, Terrain.Kind.BRIDGE)
			elif dkind != Terrain.Kind.CITY:
				_put_tile(tiles, w, p, Terrain.Kind.ROAD)
