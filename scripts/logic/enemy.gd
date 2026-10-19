extends RefCounted
## Oddziały wroga: tworzenie, cele, planowanie trasy, ruch.

const RNG = preload("res://scripts/logic/rng.gd")
const Army = preload("res://scripts/logic/army.gd")
const UnitsData = preload("res://scripts/logic/units_data.gd")
const Pathfind = preload("res://scripts/logic/pathfind.gd")
const Terrain = preload("res://scripts/logic/terrain.gd")
const Difficulty = preload("res://scripts/logic/difficulty.gd")

## Osobowości dowódców wroga.
const PERSONALITIES: Array = ["aggressive", "cautious", "defender", "opportunist"]
## Zasięg, z jakiego wróg dostrzega gracza (w polach).
const VISION := 10
## Zasięg "patrolu" wokół domu.
const PATROL := 8


static func create(id: int, side: String, rng, size: int, diff: float, home: Vector2i, garrison: bool) -> Dictionary:
	var units: Array = Army.random_army_sized(side, rng, size, id * 100)
	var personality: String = str(rng.pick(PERSONALITIES))
	if garrison:
		personality = "defender"
	return {
		"id": id,
		"side": side,
		"units": units,
		"pos": home,
		"home": home,
		"organization": 100,
		"skill": rng.int_range(1, 5),
		"personality": personality,
		"garrison": garrison,
		"role": "garrison" if garrison else "raider",
		"goal": {},
		"path": [],
		"next_think": 0,
		"alive": true,
		"name": "Oddział %d" % id,
		"strength_hint": float(diff),
	}


## Co oddział zamierza zrobić: pościg, rajd, powrót do garnizonu, zwiad.
static func choose_goal(enemy: Dictionary, player: Dictionary, cities: Array, rng, m: Dictionary) -> Dictionary:
	var pos: Vector2i = enemy["pos"]
	var home: Vector2i = enemy["home"]
	if bool(enemy["garrison"]):
		return {"type": "garrison", "pos": home}

	var player_pos: Vector2i = player["pos"]
	var player_strength: float = float(player.get("strength", 0.0))
	var distance: int = chebyshev(pos, player_pos)
	var own: float = effective_strength(enemy)
	var personality: String = str(enemy["personality"])
	var role: String = str(enemy.get("role", "raider"))

	if role == "scout":
		return {"type": "scout", "pos": _random_point(m, rng)}

	if distance <= VISION and own >= player_strength * 0.9:
		return {"type": "hunt", "pos": player_pos}

	match personality:
		"aggressive":
			if distance <= 2 * VISION:
				return {"type": "hunt", "pos": player_pos}
			return {"type": "raid", "pos": _nearest_city(cities, pos)}
		"opportunist":
			if rng.chance(0.5):
				return {"type": "raid", "pos": _nearest_city(cities, pos)}
			return {"type": "scout", "pos": _random_point(m, rng)}
		"defender":
			if chebyshev(pos, home) <= PATROL:
				return {"type": "garrison", "pos": home}
			return {"type": "return", "pos": home}
		_:
			# cautious: trzyma się okolicy domu, czasem zwiad
			if rng.chance(0.35):
				return {"type": "scout", "pos": _random_point(m, rng)}
			return {"type": "garrison", "pos": home}


## Wyznacza trasę do celu; zwraca tablicę kroków (może być pusta).
static func plan(enemy: Dictionary, m: Dictionary, goal: Dictionary) -> Array:
	var target: Vector2i = goal["pos"]
	var blocked := func(p: Vector2i) -> bool:
		return not Terrain.is_passable(Pathfind.terrain_at(m, p))
	var result: Variant = Pathfind.find_path(m, enemy["pos"], target, blocked)
	if result == null:
		enemy["path"] = []
		enemy["goal"] = {"type": "wait", "pos": enemy["pos"]}
		return []
	var steps: Array = result
	enemy["path"] = steps
	enemy["goal"] = goal
	return steps


## Jeden krok marszu; zwraca nową pozycję.
static func move(enemy: Dictionary) -> Vector2i:
	var path: Array = enemy["path"]
	if path.is_empty():
		return enemy["pos"]
	var next: Vector2i = path[0]
	path.remove_at(0)
	enemy["pos"] = next
	return next


## Siła oddziału z uwzględnieniem organizacji: ×(0,6 + 0,4 · organizacja/100).
static func effective_strength(enemy: Dictionary) -> float:
	var base: float = Army.strength(enemy["units"])
	var org: float = float(enemy.get("organization", 100))
	return base * (0.6 + 0.4 * org / 100.0)


static func chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


## Losowe przechodnie pole mapy (opcjonalnie spełniające dodatkowy warunek).
static func random_point(m: Dictionary, rng, condition: Callable = Callable()) -> Vector2i:
	var w: int = int(m["w"])
	var h: int = int(m["h"])
	var tiles: PackedByteArray = m["tiles"]
	for attempt in range(300):
		var p := Vector2i(rng.int_range(1, w - 2), rng.int_range(1, h - 2))
		if not Terrain.is_passable(tiles[p.y * w + p.x]):
			continue
		if condition.is_valid() and not bool(condition.call(p)):
			continue
		return p
	# Awaryjnie: pierwsze przechodnie pole mapy.
	for y in range(h):
		for x in range(w):
			var p := Vector2i(x, y)
			if Terrain.is_passable(tiles[y * w + x]):
				if condition.is_valid() and not bool(condition.call(p)):
					continue
				return p
	return Vector2i(0, 0)


static func _random_point(m: Dictionary, rng) -> Vector2i:
	return random_point(m, rng, Callable())


static func _nearest_city(cities: Array, pos: Vector2i) -> Vector2i:
	var best: Vector2i = pos
	var best_dist: int = 1 << 30
	for c in cities:
		var p := Vector2i(int(c["x"]), int(c["y"]))
		var dist: int = chebyshev(pos, p)
		if dist < best_dist:
			best_dist = dist
			best = p
	return best


## Klucz czasu: co ile godzin dowódca myśli (umiejętność 1-5 → co 9-5 godzin).
static func think_interval(enemy: Dictionary) -> int:
	return Difficulty.think_interval(int(enemy.get("skill", 3)))
