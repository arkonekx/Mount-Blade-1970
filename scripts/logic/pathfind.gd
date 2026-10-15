extends RefCounted
## Wyszukiwanie trasy po mapie kampanii (A*, 8 kierunków).

const Terrain = preload("res://scripts/logic/terrain.gd")

const DIRS: Array = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]

const DIAGONAL := 1.4142135


static func in_bounds(m: Dictionary, p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < int(m["w"]) and p.y < int(m["h"])


static func terrain_at(m: Dictionary, p: Vector2i) -> int:
	if not in_bounds(m, p):
		return Terrain.Kind.MOUNTAIN
	var tiles: PackedByteArray = m["tiles"]
	return tiles[p.y * int(m["w"]) + p.x]


## Miasto stojące na polu albo pusty słownik.
static func city_at(m: Dictionary, p: Vector2i) -> Dictionary:
	var cities: Array = m["cities"]
	for c in cities:
		if int(c["x"]) == p.x and int(c["y"]) == p.y:
			return c
	return {}


static func city_pos(city: Dictionary) -> Vector2i:
	return Vector2i(int(city["x"]), int(city["y"]))


## Trasa z `from` do `to`: tablica kroków (bez pola startowego, z celem), albo null.
## `blocked_callable(p)` zwraca true dla pól, które w tej trasie są zabronione.
static func find_path(m: Dictionary, from: Vector2i, to: Vector2i, blocked_callable: Callable = Callable()) -> Variant:
	if not in_bounds(m, from) or not in_bounds(m, to):
		return null
	if from == to:
		return []
	if not Terrain.is_passable(terrain_at(m, to)):
		return null
	if blocked_callable.is_valid() and bool(blocked_callable.call(to)):
		return null

	var open: Array = [from]
	var came_from: Dictionary = {}
	var g_score: Dictionary = {from: 0.0}
	var f_score: Dictionary = {from: _heuristic(from, to)}

	while not open.is_empty():
		# Wybór pola o najmniejszym f (mapa jest mała, więc liniowe szukanie wystarcza).
		var best_idx: int = 0
		var best_f: float = float(f_score.get(open[0], 1e30))
		for i in range(1, open.size()):
			var value: float = float(f_score.get(open[i], 1e30))
			if value < best_f:
				best_f = value
				best_idx = i
		var current: Vector2i = open[best_idx]
		open.remove_at(best_idx)

		if current == to:
			return _rebuild(came_from, current)

		for dir in DIRS:
			var next: Vector2i = current + dir
			if not in_bounds(m, next):
				continue
			var kind: int = terrain_at(m, next)
			if not Terrain.is_passable(kind):
				continue
			if blocked_callable.is_valid() and bool(blocked_callable.call(next)):
				continue
			var step_cost: float = Terrain.cost(kind)
			if dir.x != 0 and dir.y != 0:
				step_cost *= DIAGONAL
			var tentative: float = float(g_score.get(current, 1e30)) + step_cost
			if tentative < float(g_score.get(next, 1e30)):
				came_from[next] = current
				g_score[next] = tentative
				f_score[next] = tentative + _heuristic(next, to)
				if not open.has(next):
					open.append(next)
	return null


## Sumaryczny koszt przejścia trasy (w godzinach marszu, bez modyfikatorów).
static func path_cost(m: Dictionary, steps: Array) -> float:
	var total: float = 0.0
	for i in range(steps.size()):
		var p: Vector2i = steps[i]
		var step_cost: float = Terrain.cost(terrain_at(m, p))
		if i > 0:
			var prev: Vector2i = steps[i - 1]
			if prev.x != p.x and prev.y != p.y:
				step_cost *= DIAGONAL
		total += step_cost
	return total


static func _heuristic(a: Vector2i, b: Vector2i) -> float:
	var dx: int = absi(a.x - b.x)
	var dy: int = absi(a.y - b.y)
	var diagonal: int = mini(dx, dy)
	var straight: int = maxi(dx, dy) - diagonal
	return float(straight) * Terrain.cost(Terrain.Kind.ROAD) + float(diagonal) * Terrain.cost(Terrain.Kind.ROAD) * DIAGONAL


static func _rebuild(came_from: Dictionary, current: Vector2i) -> Array:
	var steps: Array = [current]
	var node: Vector2i = current
	while came_from.has(node):
		node = came_from[node]
		steps.append(node)
	steps.reverse()
	if steps.size() > 0:
		steps.remove_at(0)  # pole startowe nie jest krokiem
	return steps
