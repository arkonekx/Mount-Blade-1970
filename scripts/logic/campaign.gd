extends RefCounted
## Kampania: mapa, mgła wojny, armia, wrogowie, czas, cele i zwycięstwo.
##
## Czas płynie godzinami. `world_hour()` przesuwa świat o godzinę (ruch wrogów,
## zwiad, jedzenie, dochód), a `player_step()` wykonuje jeden krok marszu gracza.

const RNG = preload("res://scripts/logic/rng.gd")
const MapGen = preload("res://scripts/logic/map_gen.gd")
const Terrain = preload("res://scripts/logic/terrain.gd")
const Fog = preload("res://scripts/logic/fog.gd")
const Pathfind = preload("res://scripts/logic/pathfind.gd")
const Army = preload("res://scripts/logic/army.gd")
const UnitsData = preload("res://scripts/logic/units_data.gd")
const Difficulty = preload("res://scripts/logic/difficulty.gd")
const DayNight = preload("res://scripts/logic/daynight.gd")
const Ferry = preload("res://scripts/logic/ferry.gd")
const Enemy = preload("res://scripts/logic/enemy.gd")

const SAVE_VERSION := 1

# --- wartości startowe ---
const START_FOOD := 400
const START_FUNDS := 300
const START_MORALE := 80
const START_HOUR := 8
const START_DAY := 1
const START_ARMY_SIZE := 5

# --- ekonomia i morale ---
const FOOD_PER_UNIT_PER_DAY := 1
const INCOME_PER_DAY := 20
const FOOD_PACK := 50
const FOOD_PACK_COST := 20
const RECRUIT_COST := 80
const STARVATION_MORALE_LOSS := 8
const COMMANDER_MORALE_LOSS := 10
const MAX_LOSS_MORALE := 30
const LOSS_MORALE_PER_UNIT := 5
const WIN_MORALE_GAIN := 5

# --- cele i zwycięstwo ---
const OBJECTIVE_COUNT := 3
const OBJECTIVE_MIN_DIST := 15
const OBJECTIVE_HOLD_HOURS := 12.0
const OBJECTIVE_CLEAR_RADIUS := 3
const CAPTURE_RADIUS := 1

# --- wrogowie ---
const MAX_ENEMIES := 6
const ENEMY_MIN_DIST := 12
const ENEMY_SPAWN_DAYS := 3
const GARRISON_MAX := 2
const CONTACT_COOLDOWN_HOURS := 8
const CONTACT_RADIUS := 1

# --- zwiad i przeprawy ---
const SCOUT_DEATH_CHANCE := 0.35
const SCOUT_DETECT_RADIUS := 2
const SCOUT_HOURS_FACTOR := 2
const SCOUT_REVEAL_RADIUS := 4
const BRIDGE_HOURS := 6.0
const REST_HOURS := 4
const REST_MORALE_GAIN := 5
const BASE_SIGHT := 3.0

var side: String = "us"
var world_seed: int = 0
var rng
var map: Dictionary = {}
var fog
var army: Array = []
var enemies: Array = []
## Zwiadowca w drodze albo null.
var scout: Variant = null
var boats: Array = []
var position: Vector2i = Vector2i.ZERO
var path: Array = []
var move_target: Dictionary = {}
var hours: int = START_HOUR
var day: int = START_DAY
var food: int = START_FOOD
var funds: int = START_FUNDS
var morale: int = START_MORALE
var relief: float = 1.0
var objectives: Array = []
var captured: Array = []
var news: Array = []
## Miejsca, w których widziano wroga, z dniem wykrycia (nie dane na żywo).
var marks: Array = []
var pending_battle: Variant = null
var contact_cooldown: int = 0
var over: bool = false
var victory: bool = false
var next_enemy_id: int = 1
var next_unit_id: int = 31


func _init(p_side: String = "us", p_seed: int = 0) -> void:
	side = p_side
	world_seed = p_seed
	_setup()


# --- konfiguracja startowa ---------------------------------------------------


func _setup() -> void:
	map = MapGen.generate(world_seed, 60, 40)
	rng = RNG.new(world_seed * 7919 + 13)
	fog = Fog.new(int(map["w"]), int(map["h"]))
	position = map["start"]
	hours = START_HOUR
	day = START_DAY
	food = START_FOOD
	funds = START_FUNDS
	morale = START_MORALE
	relief = 1.0
	army = Army.random_army_sized(side, rng, START_ARMY_SIZE, 1)
	next_unit_id = 31
	boats = Ferry.find_spots(map, rng, 2)
	_setup_objectives()
	fog.reveal(position.x, position.y, BASE_SIGHT)
	_push_news("Kampania rozpoczęta: %d jednostek, %d żywności." % [army.size(), food])
	_spawn_initial_enemies()


func _setup_objectives() -> void:
	objectives = []
	var cities: Array = map["cities"]
	var entries: Array = []
	for i in range(1, cities.size()):
		var c: Dictionary = cities[i]
		var p := Vector2i(int(c["x"]), int(c["y"]))
		var dist: int = Enemy.chebyshev(p, position)
		if dist < OBJECTIVE_MIN_DIST:
			continue
		entries.append({"city": c, "dist": dist, "order": i})
	# Najdalsze miasta; przy równych odległościach decyduje kolejność na mapie.
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["dist"]) != int(b["dist"]):
			return int(a["dist"]) > int(b["dist"])
		return int(a["order"]) < int(b["order"]))
	for i in range(mini(OBJECTIVE_COUNT, entries.size())):
		var c: Dictionary = entries[i]["city"]
		objectives.append({
			"x": int(c["x"]),
			"y": int(c["y"]),
			"name": str(c["name"]),
			"hold": 0.0,
			"owned": false,
		})


func _spawn_initial_enemies() -> void:
	# Jeden oddział w polu + garnizony w miastach (przynajmniej jeden).
	_spawn_roaming()
	var garrisons: int = 1 if day < 4 else GARRISON_MAX
	_spawn_garrisons(garrisons)


func enemy_side() -> String:
	return "su" if side == "us" else "us"


func _sight_radius() -> float:
	return DayNight.sight_at(BASE_SIGHT, hours)


# --- upływ czasu -------------------------------------------------------------


## Przesuwa świat o godzinę. Zwraca true, gdy doszło do kontaktu z wrogiem.
func world_hour() -> bool:
	if over:
		return false
	hours += 1
	if hours % 24 == 0:
		day += 1
		_daily_tick()
	_update_scout()
	_update_enemies()
	_update_objectives()
	if contact_cooldown > 0:
		contact_cooldown -= 1
	fog.refresh(position.x, position.y, _sight_radius())
	return _check_contact()


func _daily_tick() -> void:
	var needed: int = army.size() * FOOD_PER_UNIT_PER_DAY + (1 if scout != null else 0)
	food -= needed
	if food < 0:
		food = 0
		morale = maxi(0, morale - STARVATION_MORALE_LOSS)
		_push_news("Brak żywności! Morale -%d." % STARVATION_MORALE_LOSS)
	funds += INCOME_PER_DAY
	_push_news("Dzień %d. Żywność %d, fundusze %d." % [day, food, funds])
	_maybe_spawn()


func _maybe_spawn() -> void:
	var target: int = clampi(1 + int(day / 6.0), 1, MAX_ENEMIES)
	var roaming: int = 0
	for e in enemies:
		if not bool(e["garrison"]):
			roaming += 1
	while roaming < target and enemies.size() < MAX_ENEMIES:
		_spawn_roaming()
		roaming += 1
	if day % ENEMY_SPAWN_DAYS == 0 and enemies.size() < MAX_ENEMIES:
		_spawn_enemy_scout()


func _random_enemy_spot(far_from: Vector2i, min_dist: int) -> Vector2i:
	var w: int = int(map["w"])
	var h: int = int(map["h"])
	var tiles: PackedByteArray = map["tiles"]
	var fallback := Vector2i(-1, -1)
	var fallback_dist: int = -1
	for attempt in range(600):
		var p := Vector2i(rng.int_range(1, w - 2), rng.int_range(1, h - 2))
		if not Terrain.is_passable(tiles[p.y * w + p.x]):
			continue
		var dist: int = Enemy.chebyshev(p, far_from)
		if dist > fallback_dist:
			fallback_dist = dist
			fallback = p
		if dist >= min_dist:
			return p
	if fallback.x >= 0:
		return fallback
	return far_from


func _spawn_roaming() -> Dictionary:
	var diff: float = Difficulty.effective_difficulty(day, relief)
	var size: int = Difficulty.enemy_army_size(diff)
	var spot: Vector2i = _random_enemy_spot(position, ENEMY_MIN_DIST)
	var enemy: Dictionary = Enemy.create(next_enemy_id, enemy_side(), rng, size, diff, spot, false)
	next_enemy_id += 1
	enemies.append(enemy)
	_push_news("Pojawił się nowy oddział wroga (%d jednostek)." % size)
	return enemy


func _spawn_enemy_scout() -> Dictionary:
	var diff: float = Difficulty.effective_difficulty(day, relief)
	var size: int = maxi(2, int(Difficulty.enemy_army_size(diff) / 2.0))
	var spot: Vector2i = _random_enemy_spot(position, ENEMY_MIN_DIST)
	var enemy: Dictionary = Enemy.create(next_enemy_id, enemy_side(), rng, size, diff, spot, false)
	enemy["role"] = "scout"
	enemy["skill"] = 3
	next_enemy_id += 1
	enemies.append(enemy)
	_push_news("Wróg wysłał zwiadowcę (%d jednostek)." % size)
	return enemy


func _spawn_garrisons(count: int) -> void:
	var cities: Array = map["cities"]
	var added: int = 0
	var diff: float = Difficulty.effective_difficulty(day, relief)
	var size: int = Difficulty.enemy_army_size(diff)
	for i in range(1, cities.size()):
		if added >= count or enemies.size() >= MAX_ENEMIES:
			break
		var c: Dictionary = cities[i]
		var p := Vector2i(int(c["x"]), int(c["y"]))
		if Enemy.chebyshev(p, position) < 6:
			continue
		var enemy: Dictionary = Enemy.create(next_enemy_id, enemy_side(), rng, size, diff, p, true)
		enemy["name"] = "Garnizon %s" % str(c["name"])
		next_enemy_id += 1
		enemies.append(enemy)
		added += 1
	if added > 0:
		_push_news("Wróg obsadził %d miast garnizonem." % added)


func _update_enemies() -> void:
	var player_info: Dictionary = {"pos": position, "strength": Army.strength(army)}
	for enemy in enemies:
		if bool(enemy["garrison"]):
			continue
		if hours >= int(enemy["next_think"]):
			var goal: Dictionary = Enemy.choose_goal(enemy, player_info, map["cities"], rng, map)
			Enemy.plan(enemy, map, goal)
			enemy["next_think"] = hours + Enemy.think_interval(enemy)
		Enemy.move(enemy)


func _update_objectives() -> void:
	for obj in objectives:
		if bool(obj["owned"]):
			continue
		var obj_pos := Vector2i(int(obj["x"]), int(obj["y"]))
		var hold: float = float(obj["hold"])
		if Enemy.chebyshev(position, obj_pos) <= CAPTURE_RADIUS and not _enemy_near(obj_pos, OBJECTIVE_CLEAR_RADIUS):
			hold += 1.0
			if hold >= OBJECTIVE_HOLD_HOURS:
				obj["owned"] = true
				obj["hold"] = OBJECTIVE_HOLD_HOURS
				captured.append(str(obj["name"]))
				_push_news("Miasto %s utrzymane! Cel zdobyty." % str(obj["name"]))
				continue
		elif _enemy_near(obj_pos, OBJECTIVE_CLEAR_RADIUS):
			hold = 0.0
		obj["hold"] = hold
	# Zwycięstwo: wszystkie cele zdobyte.
	var owned: int = 0
	for obj in objectives:
		if bool(obj["owned"]):
			owned += 1
	if not objectives.is_empty() and owned == objectives.size():
		if not victory:
			over = true
			victory = true
			_push_news("ZWYCIĘSTWO! Wszystkie cele zdobyte.")


func _enemy_near(p: Vector2i, radius: int) -> bool:
	for enemy in enemies:
		if Enemy.chebyshev(enemy["pos"], p) <= radius:
			return true
	return false


func _check_contact() -> bool:
	if over:
		return false
	if contact_cooldown > 0:
		return false
	for enemy in enemies:
		if Enemy.chebyshev(enemy["pos"], position) <= CONTACT_RADIUS:
			pending_battle = enemy
			contact_cooldown = CONTACT_COOLDOWN_HOURS
			_push_news("Kontakt z wrogiem — bitwa!")
			return true
	return false


# --- ruch gracza -------------------------------------------------------------


## Wyznacza trasę marszu. Zwraca "" albo komunikat dla gracza.
func start_move(target: Vector2i) -> String:
	if over:
		return "Kampania zakończona."
	if pending_battle != null:
		return "Najpierw rozstrzygnij bitwę."
	if not Pathfind.in_bounds(map, target):
		return "Poza mapą."
	var kind: int = Pathfind.terrain_at(map, target)
	if not Terrain.is_passable(kind):
		return "Nieprzechodni teren: %s." % Terrain.terrain_name(kind)
	var blocked := func(p: Vector2i) -> bool:
		return not Terrain.is_passable(Pathfind.terrain_at(map, p))
	var result: Variant = Pathfind.find_path(map, position, target, blocked)
	if result == null:
		return "Brak trasy do celu."
	var steps: Array = result
	if steps.is_empty():
		return "Już jesteś na miejscu."
	path = steps
	move_target = {"x": target.x, "y": target.y}
	return ""


## Jeden krok marszu (wywoływany co jakiś czas przez widok kampanii).
func player_step() -> void:
	if over or pending_battle != null:
		return
	if path.is_empty():
		return
	var step: Vector2i = path[0]
	path.remove_at(0)
	if not Pathfind.in_bounds(map, step):
		path.clear()
		return
	var cost: float = Terrain.cost(Pathfind.terrain_at(map, step))
	position = step
	fog.explore(position.x, position.y, 1.0)
	var city: Dictionary = Pathfind.city_at(map, position)
	if not city.is_empty():
		_push_news("Wkroczyłeś do miasta %s." % str(city["name"]))
	if path.is_empty():
		move_target = {}
	spend_move_time(cost)


## Czas marszu: każde pole to 1-2 godziny (zależnie od terenu).
func spend_move_time(cost: float) -> int:
	var spent: int = maxi(1, int(round(cost)))
	for i in range(spent):
		if over or pending_battle != null:
			break
		world_hour()
	return spent


func stop_move() -> void:
	path = []
	move_target = {}


# --- akcje gracza ------------------------------------------------------------


func buy_food() -> String:
	if funds < FOOD_PACK_COST:
		return "Brak funduszy (potrzeba %d)." % FOOD_PACK_COST
	funds -= FOOD_PACK_COST
	food += FOOD_PACK
	_push_news("Kupiono żywność (+%d)." % FOOD_PACK)
	return ""


func recruit_infantry() -> String:
	var city: Dictionary = Pathfind.city_at(map, position)
	if city.is_empty():
		return "Rekrutacja tylko w mieście."
	if funds < RECRUIT_COST:
		return "Brak funduszy (potrzeba %d)." % RECRUIT_COST
	if army.size() >= UnitsData.LIMIT_TOTAL:
		return "Limit oddziału (%d) osiągnięty." % UnitsData.LIMIT_TOTAL
	var unit: Dictionary = Army.make_unit(rng, side, UnitsData.CLS_INFANTRY, next_unit_id)
	if str(unit["def_id"]) == "":
		return "Brak dostępnych jednostek."
	next_unit_id += 1
	army.append(unit)
	funds -= RECRUIT_COST
	_push_news("Zrekrutowano: %s." % str(unit["name"]))
	return ""


func rest() -> String:
	var city: Dictionary = Pathfind.city_at(map, position)
	if city.is_empty():
		return "Odpoczynek tylko w mieście."
	morale = mini(100, morale + REST_MORALE_GAIN)
	_push_news("Odpoczynek w %s. Morale +%d." % [str(city["name"]), REST_MORALE_GAIN])
	for i in range(REST_HOURS):
		if over or pending_battle != null:
			break
		world_hour()
	return ""


func dispatch_scout(target: Vector2i) -> String:
	if scout != null:
		return "Zwiadowca już jest w drodze."
	if not Pathfind.in_bounds(map, target):
		return "Poza mapą."
	var unit: Dictionary = Army.first_infantry(army)
	if unit.is_empty():
		return "Brak piechoty do wysłania na zwiad."
	var blocked := func(p: Vector2i) -> bool:
		return not Terrain.is_passable(Pathfind.terrain_at(map, p))
	var result: Variant = Pathfind.find_path(map, position, target, blocked)
	if result == null:
		return "Brak trasy dla zwiadowcy."
	var out_steps: Array = result
	if out_steps.is_empty():
		return "Cel zwiadu jest zbyt blisko."
	# Trasa tam i z powrotem.
	var back_steps: Array = out_steps.duplicate()
	back_steps.reverse()
	var path_out: Array = []
	for step in out_steps:
		path_out.append(step)
	for step in back_steps:
		path_out.append(step)
	var cost: float = Pathfind.path_cost(map, out_steps)
	army.erase(unit)
	scout = {
		"unit": unit,
		"pos": position,
		"target": target,
		"path": path_out,
		"hours_left": int(ceil(cost * SCOUT_HOURS_FACTOR)),
		"seen": 0,
	}
	_push_news("Wysłano zwiadowcę (%s) — powrót za ok. %d h." % [str(unit["name"]), int(scout["hours_left"])])
	return ""


func ferry_cross() -> String:
	var idx: int = Ferry.boat_at(boats, position)
	if idx < 0:
		# łódź może stać na sąsiednim polu
		for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			idx = Ferry.boat_at(boats, position + dir)
			if idx >= 0:
				break
	if idx < 0:
		return "Brak łodzi w pobliżu."
	var boat: Dictionary = boats[idx]
	var result: Dictionary = Ferry.cross(boat)
	var to: Vector2i = result["to"]
	position = to
	path = []
	move_target = {}
	var spent: int = maxi(1, int(round(float(result["hours"]))))
	_push_news("Przeprawa łodzią (%d h)." % spent)
	for i in range(spent):
		if over or pending_battle != null:
			break
		world_hour()
	return ""


func can_build_bridge() -> bool:
	if Army.find_engineer(army).is_empty():
		return false
	return Ferry.can_build_bridge(map, position)


func build_bridge_at() -> String:
	if Army.find_engineer(army).is_empty():
		return "Potrzebny pojazd inżynieryjny (np. M728 CEV, MTU-20)."
	var result: Dictionary = Ferry.build_bridge(map, position)
	if not bool(result["ok"]):
		return "Nie ma tu wody do przerzucenia mostu."
	var span: Array = result["tiles"]
	_push_news("Zbudowano most (%d przęseł)." % span.size())
	spend_move_time(BRIDGE_HOURS)
	return ""


# --- zwiad -------------------------------------------------------------------


func _update_scout() -> void:
	if scout == null:
		return
	var s: Dictionary = scout
	var pos: Vector2i = s["pos"]
	fog.explore(pos.x, pos.y, SCOUT_REVEAL_RADIUS)
	if not s["path"].is_empty():
		pos = s["path"][0]
		s["path"].remove_at(0)
		s["pos"] = pos
	# Wykrywanie wrogów w drodze.
	for enemy in enemies:
		if Enemy.chebyshev(enemy["pos"], pos) <= SCOUT_DETECT_RADIUS:
			if rng.chance(SCOUT_DEATH_CHANCE):
				_push_news("Zwiadowca (%s) nie wrócił — zginął." % str(s["unit"]["name"]))
				scout = null
				return
			s["seen"] = int(s["seen"]) + 1
			marks.append({"x": enemy["pos"].x, "y": enemy["pos"].y, "day": day})
	s["hours_left"] = int(s["hours_left"]) - 1
	if s["path"].is_empty() or int(s["hours_left"]) <= 0:
		_finish_scout()


func _finish_scout() -> void:
	var s: Dictionary = scout
	var target: Vector2i = s["target"]
	fog.explore(target.x, target.y, SCOUT_REVEAL_RADIUS)
	army.append(s["unit"])
	_push_news("Zwiadowca wrócił. Wykryci wrogowie: %d." % int(s["seen"]))
	scout = null


# --- wynik bitwy -------------------------------------------------------------


## Rozliczenie bitwy FPS: armia gracza = ocalali, wróg dostaje swoje straty.
func apply_battle_outcome(enemy: Dictionary, outcome: Dictionary) -> void:
	var before: int = army.size()
	army = []
	var player_survivors: Array = outcome.get("player_survivors", [])
	for unit in player_survivors:
		army.append(unit)

	var enemy_survivors: Array = outcome.get("enemy_survivors", [])
	enemy["units"] = []
	for unit in enemy_survivors:
		enemy["units"].append(unit)

	var result: String = str(outcome.get("result", "stalemate"))

	if bool(outcome.get("commander_lost", false)):
		morale = maxi(0, morale - COMMANDER_MORALE_LOSS)
		_push_news("Poległ nasz dowódca. Morale -%d." % COMMANDER_MORALE_LOSS)
	if bool(outcome.get("enemy_commander_lost", false)):
		enemy["organization"] = 50
		_push_news("Poległ dowódca wroga — jego organizacja spada do 50.")

	var lost: int = maxi(0, before - army.size())
	if lost > 0:
		morale = maxi(0, morale - mini(MAX_LOSS_MORALE, lost * LOSS_MORALE_PER_UNIT))

	if enemy["units"].is_empty():
		enemies.erase(enemy)
		_push_news("Oddział wroga rozbity i usunięty z mapy.")

	if result == "win":
		morale = mini(100, morale + WIN_MORALE_GAIN)

	relief = Difficulty.update_relief(relief, result)
	contact_cooldown = CONTACT_COOLDOWN_HOURS
	pending_battle = null

	if army.is_empty():
		over = true
		victory = false
		_push_news("Bez wojska — kampania przegrana.")
	_push_news("Wynik bitwy: %s (ocalało %d jednostek)." % [result, army.size()])


# --- informacje dla interfejsu ----------------------------------------------


func _push_news(text: String) -> void:
	news.append("[%s] %s" % [DayNight.format_time(day, hours), text])
	while news.size() > 40:
		news.remove_at(0)


func time_text() -> String:
	return DayNight.format_time(day, hours)


func status_text() -> String:
	return "%s  |  żywność %d  |  fundusze %d  |  morale %d  |  wojsko %d (%s)" % [
		time_text(), food, funds, morale, army.size(), Army.strength(army)
	]


func last_news(count: int = 6) -> Array:
	var out: Array = []
	var start: int = maxi(0, news.size() - count)
	for i in range(start, news.size()):
		out.append(news[i])
	return out


func objective_texts() -> Array:
	var out: Array = []
	for obj in objectives:
		var state: String = "zdobyte" if bool(obj["owned"]) else "%d/%d h" % [int(obj["hold"]), int(OBJECTIVE_HOLD_HOURS)]
		out.append("%s — %s" % [str(obj["name"]), state])
	return out


func terrain_here() -> String:
	return Terrain.terrain_name(Pathfind.terrain_at(map, position))


func visible_enemies() -> Array:
	var out: Array = []
	for enemy in enemies:
		if fog.is_visible(enemy["pos"].x, enemy["pos"].y):
			out.append(enemy)
	return out


func is_city_here() -> bool:
	return not Pathfind.city_at(map, position).is_empty()


# --- zapis i odczyt ----------------------------------------------------------


static func _vec_to_arr(p: Vector2i) -> Array:
	return [p.x, p.y]


static func _arr_to_vec(value) -> Vector2i:
	return Vector2i(int(value[0]), int(value[1]))


static func _path_to_arr(steps: Array) -> Array:
	var out: Array = []
	for step in steps:
		out.append(_vec_to_arr(step))
	return out


static func _arr_to_path(value) -> Array:
	var out: Array = []
	for step in value:
		out.append(_arr_to_vec(step))
	return out


func _enemies_to_dict() -> Array:
	var out: Array = []
	for enemy in enemies:
		out.append({
			"id": int(enemy["id"]),
			"side": str(enemy["side"]),
			"units": enemy["units"],
			"pos": _vec_to_arr(enemy["pos"]),
			"home": _vec_to_arr(enemy["home"]),
			"organization": int(enemy["organization"]),
			"skill": int(enemy["skill"]),
			"personality": str(enemy["personality"]),
			"garrison": bool(enemy["garrison"]),
			"role": str(enemy.get("role", "raider")),
			"goal": enemy["goal"],
			"path": _path_to_arr(enemy["path"]),
			"next_think": int(enemy["next_think"]),
			"alive": bool(enemy["alive"]),
			"name": str(enemy["name"]),
		})
	return out


## Identyfikatory jednostek po odczycie JSON są liczbami zmiennoprzecinkowymi.
static func _normalize_units(value) -> Array:
	var out: Array = []
	for unit in value:
		var copy: Dictionary = {
			"id": int(unit["id"]),
			"def_id": str(unit["def_id"]),
			"cls": str(unit["cls"]),
			"name": str(unit["name"]),
		}
		out.append(copy)
	return out


static func _enemies_from_dict(value) -> Array:
	var out: Array = []
	for e in value:
		out.append({
			"id": int(e["id"]),
			"side": str(e["side"]),
			"units": _normalize_units(e["units"]),
			"pos": _arr_to_vec(e["pos"]),
			"home": _arr_to_vec(e["home"]),
			"organization": int(e["organization"]),
			"skill": int(e["skill"]),
			"personality": str(e["personality"]),
			"garrison": bool(e["garrison"]),
			"role": str(e.get("role", "raider")),
			"goal": e["goal"],
			"path": _arr_to_path(e["path"]),
			"next_think": int(e["next_think"]),
			"alive": bool(e["alive"]),
			"name": str(e["name"]),
		})
	return out


func _boats_to_dict() -> Array:
	var out: Array = []
	for b in boats:
		out.append({"pos": _vec_to_arr(b["pos"]), "to": _vec_to_arr(b["to"]), "hours": float(b["hours"])})
	return out


static func _boats_from_dict(value) -> Array:
	var out: Array = []
	for b in value:
		out.append({"pos": _arr_to_vec(b["pos"]), "to": _arr_to_vec(b["to"]), "hours": float(b["hours"])})
	return out


func to_dict() -> Dictionary:
	var tiles: PackedByteArray = map["tiles"]
	var city_list: Array = []
	for c in map["cities"]:
		city_list.append({"x": int(c["x"]), "y": int(c["y"]), "name": str(c["name"])})
	var scout_dict: Variant = null
	if scout != null:
		var s: Dictionary = scout
		scout_dict = {
			"unit": s["unit"],
			"pos": _vec_to_arr(s["pos"]),
			"target": _vec_to_arr(s["target"]),
			"path": _path_to_arr(s["path"]),
			"hours_left": int(s["hours_left"]),
			"seen": int(s["seen"]),
		}
	return {
		"version": SAVE_VERSION,
		"side": side,
		"seed": world_seed,
		"rng_state": int(rng.state),
		"hours": hours,
		"day": day,
		"food": food,
		"funds": funds,
		"morale": morale,
		"relief": relief,
		"position": _vec_to_arr(position),
		"path": _path_to_arr(path),
		"map": {
			"w": int(map["w"]),
			"h": int(map["h"]),
			"tiles": Marshalls.raw_to_base64(tiles),
			"start": _vec_to_arr(map["start"]),
			"cities": city_list,
		},
		"fog": fog.to_dict(),
		"army": army,
		"enemies": _enemies_to_dict(),
		"scout": scout_dict,
		"boats": _boats_to_dict(),
		"objectives": objectives,
		"captured": captured,
		"news": news,
		"marks": marks,
		"pending_battle_id": -1 if pending_battle == null else int(pending_battle["id"]),
		"contact_cooldown": contact_cooldown,
		"over": over,
		"victory": victory,
		"next_enemy_id": next_enemy_id,
		"next_unit_id": next_unit_id,
	}


static func from_dict(d: Dictionary) -> RefCounted:
	var campaign = load("res://scripts/logic/campaign.gd").new(str(d.get("side", "us")), int(d.get("seed", 0)))
	var fog_data: Dictionary = d["fog"]
	campaign.fog = Fog.from_dict(fog_data)
	var map_data: Dictionary = d["map"]
	campaign.map = {
		"w": int(map_data["w"]),
		"h": int(map_data["h"]),
		"tiles": Marshalls.base64_to_raw(str(map_data["tiles"])),
		"start": _arr_to_vec(map_data["start"]),
		"cities": map_data["cities"],
	}
	campaign.rng.state = int(d["rng_state"])
	campaign.position = _arr_to_vec(d["position"])
	campaign.path = _arr_to_path(d["path"])
	campaign.hours = int(d["hours"])
	campaign.day = int(d["day"])
	campaign.food = int(d["food"])
	campaign.funds = int(d["funds"])
	campaign.morale = int(d["morale"])
	campaign.relief = float(d["relief"])
	campaign.army = _normalize_units(d["army"])
	campaign.enemies = _enemies_from_dict(d["enemies"])
	campaign.boats = _boats_from_dict(d["boats"])
	campaign.objectives = d["objectives"]
	campaign.captured = d["captured"]
	campaign.news = d["news"]
	campaign.marks = d["marks"]
	campaign.contact_cooldown = int(d["contact_cooldown"])
	campaign.over = bool(d["over"])
	campaign.victory = bool(d["victory"])
	campaign.next_enemy_id = int(d["next_enemy_id"])
	campaign.next_unit_id = int(d["next_unit_id"])
	campaign.scout = null
	if d.get("scout", null) != null:
		var s: Dictionary = d["scout"]
		campaign.scout = {
			"unit": s["unit"],
			"pos": _arr_to_vec(s["pos"]),
			"target": _arr_to_vec(s["target"]),
			"path": _arr_to_path(s["path"]),
			"hours_left": int(s["hours_left"]),
			"seen": int(s["seen"]),
		}
	campaign.pending_battle = null
	var pending_id: int = int(d.get("pending_battle_id", -1))
	if pending_id >= 0:
		for enemy in campaign.enemies:
			if int(enemy["id"]) == pending_id:
				campaign.pending_battle = enemy
				break
	return campaign
