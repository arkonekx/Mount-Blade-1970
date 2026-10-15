extends RefCounted
## Przeprawy przez wodę: łodzie przy brzegu i budowa mostu.

const Terrain = preload("res://scripts/logic/terrain.gd")

## Najdłuższa przeprawa łodzią (w polach).
const MAX_CROSSING := 6
## Kierunki, w których szukamy przęsła mostu.
const SPAN_DIRS: Array = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
## Łodzie nie są przenośne — zostają tam, gdzie je znaleziono.
const PORTABLE := false


## Miejsca, w których stoją łodzie: przechodni brzeg z drugim brzegiem w prostej linii.
## Zwraca tablicę słowników {pos: Vector2i, to: Vector2i, hours: float}.
static func find_spots(m: Dictionary, rng, count: int = 2) -> Array:
	var w: int = int(m["w"])
	var h: int = int(m["h"])
	var tiles: PackedByteArray = m["tiles"]
	var candidates: Array = []

	for y in range(h):
		for x in range(w):
			var p := Vector2i(x, y)
			var kind: int = tiles[y * w + x]
			if not Terrain.is_passable(kind):
				continue
			var far: Vector2i = _crossing_from(tiles, w, h, p)
			if far.x < 0:
				continue
			candidates.append({"pos": p, "to": far})

	rng.shuffle(candidates)
	var boats: Array = []
	for cand in candidates:
		if boats.size() >= count:
			break
		var ok: bool = true
		for b in boats:
			var bp: Vector2i = b["pos"]
			var cp: Vector2i = cand["pos"]
			if maxi(absi(bp.x - cp.x), absi(bp.y - cp.y)) < 12:
				ok = false
				break
		if not ok:
			continue
		var pos: Vector2i = cand["pos"]
		var to: Vector2i = cand["to"]
		var hours: float = 1.0 + float(maxi(absi(pos.x - to.x), absi(pos.y - to.y)))
		boats.append({"pos": pos, "to": to, "hours": hours})
	return boats


## Indeks łodzi stojącej na polu (albo -1).
static func boat_at(boats: Array, pos: Vector2i) -> int:
	for i in range(boats.size()):
		var b: Dictionary = boats[i]
		var bp: Vector2i = b["pos"]
		if bp == pos:
			return i
	return -1


## Przeprawa łodzią: dokąd i ile to zajmuje godzin.
static func cross(bt: Dictionary) -> Dictionary:
	return {"to": bt["to"], "hours": float(bt["hours"])}


## Szuka najkrótszego przęsła mostu wychodzącego z pola `from`.
## Funkcja jest czysta — nie zmienia mapy, więc można jej używać do podpowiedzi w UI.
## Zwraca listę pól wodnych do zabudowania (pusta, gdy nie ma drugiego brzegu).
static func find_span(m: Dictionary, from: Vector2i) -> Array:
	var w: int = int(m["w"])
	var h: int = int(m["h"])
	var tiles: PackedByteArray = m["tiles"]
	var best: Array = []

	for dir in SPAN_DIRS:
		var p: Vector2i = from
		var span: Array = []
		for step in range(MAX_CROSSING):
			p = p + dir
			if p.x < 0 or p.y < 0 or p.x >= w or p.y >= h:
				span.clear()
				break
			var kind: int = tiles[p.y * w + p.x]
			if Terrain.is_water(kind):
				span.append(p)
				continue
			if Terrain.is_passable(kind) and not span.is_empty():
				# znaleźliśmy drugi brzeg
				if best.is_empty() or span.size() < best.size():
					best = span.duplicate()
				span.clear()
				break
		if not best.is_empty() and best.size() == 1:
			break

	return best


## Czy z pola `from` da się przerzucić most? Nie zmienia mapy.
static func can_build_bridge(m: Dictionary, from: Vector2i) -> bool:
	return not find_span(m, from).is_empty()


## Buduje most przez wodę zaczynający się na polu `from`.
## UWAGA: zmienia `m["tiles"]` — przęsła stają się polami BRIDGE.
## Zwraca {ok, tiles} — zbudowane przęsła (pusta lista, gdy nie ma czego przerzucić).
static func build_bridge(m: Dictionary, from: Vector2i) -> Dictionary:
	var span: Array = find_span(m, from)
	if span.is_empty():
		return {"ok": false, "tiles": []}
	var w: int = int(m["w"])
	var tiles: PackedByteArray = m["tiles"]
	for p in span:
		tiles[p.y * w + p.x] = Terrain.Kind.BRIDGE
	return {"ok": true, "tiles": span.duplicate()}


## Najbliższy drugi brzeg w linii prostej (zwraca Vector2i(-1, -1), gdy brak).
static func _crossing_from(tiles: PackedByteArray, w: int, h: int, from: Vector2i) -> Vector2i:
	var best: Vector2i = Vector2i(-1, -1)
	var best_len: int = 1 << 30
	for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
		var p: Vector2i = from
		var water: int = 0
		var found: Vector2i = Vector2i(-1, -1)
		for step in range(MAX_CROSSING):
			p = p + dir
			if p.x < 0 or p.y < 0 or p.x >= w or p.y >= h:
				break
			var kind: int = tiles[p.y * w + p.x]
			if Terrain.is_water(kind):
				water += 1
				continue
			if water > 0 and Terrain.is_passable(kind):
				found = p
			break
		if found.x >= 0 and water < best_len:
			best_len = water
			best = found
	return best
