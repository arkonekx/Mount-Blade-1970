extends RefCounted
## Symulacja bitwy FPS: pole 1000 × 400 m, gracz na piechocie lub w pojeździe.
##
## Strona gracza startuje na zachodzie (x ≈ 40-110 m, gracz na polu 60,200),
## wróg na wschodzie (x ≈ 900-970 m). Czas bitwy to 600 s.

const RNG = preload("res://scripts/logic/rng.gd")
const UnitsData = preload("res://scripts/logic/units_data.gd")

# --- pole bitwy ---
const FIELD_W := 1000.0
const FIELD_H := 400.0
const MAX_TIME := 600.0
const PLAYER_START := Vector2(60.0, 200.0)
const FRIENDLY_X_MIN := 40.0
const FRIENDLY_X_MAX := 110.0
const ENEMY_X_MIN := 900.0
const ENEMY_X_MAX := 970.0
const SPREAD_MIN := 40.0
const SPREAD_MAX := 360.0

# --- strona gracza ---
const FRIENDLY_SKILL := 3
const FRIENDLY_PERSONALITY := "cautious"
const PLAYER_HIT_FACTOR := 2.5

# --- walka ---
const ORG_MIN_ADVANCE := 30.0
const NIGHT_RANGE := 350.0
const NIGHT_HIT_FACTOR := 0.85
const MAX_HIT_CHANCE := 0.9
const REACTION_TIME := 0.3

# --- ruch ---
const PLAYER_SPEED := 3.0
const PLAYER_TURN_SPEED := 2.2
const VEHICLE_TURN_SPEED := 1.2
const SPEED_INFANTRY := 3.0
const SPEED_MECH := 7.0
const SPEED_ARMOR := 6.0
const FOREST_SPEED_FACTOR := 0.7
const VEHICLE_ENTER_RANGE := 6.0
const MINE_RADIUS := 3.0

const PLAYER_EYE := 1.7
const VEHICLE_EYE := 2.4

## Odległość, w jakiej AI się zatrzymuje (m).
const STOP_DISTANCE: Dictionary = {
	"aggressive": 120.0,
	"cautious": 220.0,
	"opportunist": 160.0,
	"defender": 260.0,
}

## Broń: zasięg w metrach, celność, przeładowanie w sekundach, cele, kontra.
const WEAPONS: Dictionary = {
	"rifle": {"id": "rifle", "name": "Karabin", "range": 300.0, "acc": 0.06, "reload": 1.5, "targets": ["infantry"], "anti": "infantry"},
	"hmg": {"id": "hmg", "name": "Karabin maszynowy", "range": 600.0, "acc": 0.10, "reload": 2.0, "targets": ["infantry", "mech"], "anti": "infantry"},
	"at": {"id": "at", "name": "Wyrzutnia ppanc", "range": 450.0, "acc": 0.45, "reload": 6.0, "targets": ["mech", "armor"], "anti": "armor"},
	"gun": {"id": "gun", "name": "Armata czołgowa", "range": 900.0, "acc": 0.40, "reload": 5.0, "targets": ["mech", "armor"], "anti": "armor"},
}

## Uzbrojenie poszczególnych jednostek (klucz: def_id z units_data.gd).
const UNIT_WEAPONS: Dictionary = {
	"us_inf_m16": ["rifle"],
	"us_inf_m60": ["rifle", "hmg"],
	"us_inf_law": ["rifle", "at"],
	"us_inf_dragon": ["rifle", "at"],
	"us_mech_m113": ["hmg"],
	"us_mech_m113tow": ["hmg"],
	"us_mech_m577": ["hmg"],
	"us_eng_cev": ["hmg"],
	"us_arm_m48a5": ["gun", "hmg"],
	"us_arm_m60a1": ["gun", "hmg"],
	"us_arm_m551": ["gun", "hmg"],
	"us_proto_xm803": ["gun", "hmg"],
	"su_inf_ak": ["rifle"],
	"su_inf_rpk": ["rifle", "hmg"],
	"su_inf_rpg": ["rifle", "at"],
	"su_inf_ags": ["rifle", "hmg"],
	"su_mech_btr60": ["hmg"],
	"su_mech_bmp1": ["hmg"],
	"su_mech_mtlb": ["hmg"],
	"su_eng_mtu": ["hmg"],
	"su_arm_t55": ["gun", "hmg"],
	"su_arm_t62": ["gun", "hmg"],
	"su_arm_t72": ["gun", "hmg"],
	"su_proto_775": ["gun", "hmg"],
}

## Osłona terenu (mnożnik szansy trafienia).
const COVER: Dictionary = {
	"las": 0.8, "forest": 0.8,
	"wzgórza": 0.9, "hills": 0.9, "góry": 0.9,
	"miasto": 0.9, "city": 0.9,
	"równina": 1.0, "plains": 1.0,
}

# --- stan symulacji ---
var time: float = 0.0
var rng
var units: Array = []
var obstacles: Array = []
var mines: Array = []
## Zorganizowanie stron: org[true] to gracz, org[false] to wróg.
var org: Dictionary = {true: 100.0, false: 100.0}
var inside: int = -1
var yaw: float = 0.0
var result: String = ""
var player_retreated: bool = false
var cmd_lost_friend: bool = false
var cmd_lost_enemy: bool = false
var last_message: String = ""
var terrain: String = "plains"
var night: bool = false
var enemy_info: Dictionary = {}


func _init(friends: Array, enemies: Array, p_enemy_info: Dictionary = {}, terrain_name: String = "plains", seed_value: int = 1, is_night: bool = false) -> void:
	rng = RNG.new(seed_value)
	enemy_info = p_enemy_info
	terrain = terrain_name.to_lower()
	night = is_night
	_build_obstacles()
	_spawn_units(friends, enemies)
	_place_mines()
	last_message = "Bitwa! %s" % ("Noc." if night else "Dzień.")


# --- tworzenie świata --------------------------------------------------------


func _build_obstacles() -> void:
	obstacles = []
	var count: int = 5
	var radius_min: float = 1.5
	var radius_max: float = 2.5
	if terrain.begins_with("las") or terrain.begins_with("forest"):
		count = 35
		radius_min = 2.5
		radius_max = 5.0
	elif terrain.begins_with("wzg") or terrain.begins_with("hill") or terrain.begins_with("gór"):
		count = 10
		radius_min = 6.0
		radius_max = 12.0
	for i in range(count):
		var x: float = rng.float_range(30.0, FIELD_W - 30.0)
		var z: float = rng.float_range(10.0, FIELD_H - 10.0)
		# nie stawiaj przeszkód na polach startowych obu stron
		if x < FRIENDLY_X_MAX + 10.0 or x > ENEMY_X_MIN - 10.0:
			x = rng.float_range(200.0, 800.0)
		obstacles.append({"x": x, "z": z, "r": rng.float_range(radius_min, radius_max)})


func _spawn_units(friends: Array, enemies: Array) -> void:
	units = []
	var player_ref: Dictionary = {}
	for ref in friends:
		var cls: String = str(ref.get("cls", UnitsData.CLS_INFANTRY))
		if player_ref.is_empty() and cls == UnitsData.CLS_INFANTRY:
			player_ref = ref
	if player_ref.is_empty() and not friends.is_empty():
		player_ref = friends[0]

	for i in range(friends.size()):
		var ref: Dictionary = friends[i]
		var is_player: bool = is_same(ref, player_ref)
		var x: float = PLAYER_START.x if is_player else rng.float_range(FRIENDLY_X_MIN, FRIENDLY_X_MAX)
		var z: float = PLAYER_START.y if is_player else _spread(i, friends.size())
		units.append(_make_unit(ref, true, x, z, is_player))

	for i in range(enemies.size()):
		var ref: Dictionary = enemies[i]
		var x: float = rng.float_range(ENEMY_X_MIN, ENEMY_X_MAX)
		var z: float = _spread(i, enemies.size())
		units.append(_make_unit(ref, false, x, z, false))

	# Dowódcy: pierwszy piechur strony (u gracza — pierwszy piechur poza graczem).
	_assign_commanders()


func _spread(index: int, total: int) -> float:
	if total <= 1:
		return (SPREAD_MIN + SPREAD_MAX) * 0.5
	var step: float = (SPREAD_MAX - SPREAD_MIN) / float(total - 1)
	return SPREAD_MIN + step * float(index) + rng.float_range(-8.0, 8.0)


func _make_unit(ref: Dictionary, is_friend: bool, x: float, z: float, is_player: bool) -> Dictionary:
	var cls: String = str(ref.get("cls", UnitsData.CLS_INFANTRY))
	var skill: int = FRIENDLY_SKILL if is_friend else int(enemy_info.get("skill", 3))
	var personality: String = FRIENDLY_PERSONALITY if is_friend else str(enemy_info.get("personality", "cautious"))
	return {
		"ref": ref,
		"side": is_friend,
		"cls": cls,
		"def_id": str(ref.get("def_id", "")),
		"name": str(ref.get("name", "jednostka")),
		"x": x,
		"z": z,
		"yaw": 0.0 if is_friend else PI,
		"alive": true,
		"ready_at": maxf(0.0, float(5 - skill)) * REACTION_TIME,
		"is_player": is_player,
		"is_commander": false,
		"skill": skill,
		"personality": personality,
		"weapon": "",
	}


func _assign_commanders() -> void:
	for side in [true, false]:
		for unit in units:
			if bool(unit["side"]) != side or not bool(unit["alive"]):
				continue
			if str(unit["cls"]) != UnitsData.CLS_INFANTRY:
				continue
			if side and bool(unit["is_player"]):
				continue
			unit["is_commander"] = true
			break


func _place_mines() -> void:
	mines = []
	var count: int = rng.int_range(4, 7)
	for i in range(count):
		mines.append({
			"x": rng.float_range(320.0, 680.0),
			"z": rng.float_range(20.0, FIELD_H - 20.0),
		})


# --- wejście gracza ----------------------------------------------------------


## Ruch gracza: `forward` (-1..1) i `turn` (-1..1) w skali sekundy.
func player_input(dt: float, forward: float, turn: float) -> void:
	if result != "":
		return
	if turn != 0.0:
		player_turn(dt, turn)
	if forward == 0.0:
		return
	var unit: Dictionary = _player_unit()
	if unit.is_empty() or not bool(unit["alive"]):
		return
	var speed: float = PLAYER_SPEED
	if inside >= 0:
		speed = _speed_of(str(_vehicle().get("cls", UnitsData.CLS_MECH)))
	elif _is_forest():
		speed *= FOREST_SPEED_FACTOR
	var angle: float = float(unit["yaw"])
	var nx: float = float(unit["x"]) + cos(angle) * speed * forward * dt
	var nz: float = float(unit["z"]) + sin(angle) * speed * forward * dt
	nx = clampf(nx, 2.0, FIELD_W - 2.0)
	nz = clampf(nz, 2.0, FIELD_H - 2.0)
	unit["x"] = nx
	unit["z"] = nz
	if inside >= 0:
		var veh: Dictionary = _vehicle()
		veh["x"] = nx
		veh["z"] = nz
		veh["yaw"] = angle


## Obrót gracza (mysz albo klawiatura). Zwraca nowy kąt.
func player_turn(dt: float, turn: float) -> float:
	var unit: Dictionary = _player_unit()
	if unit.is_empty() or not bool(unit["alive"]):
		return yaw
	var speed: float = VEHICLE_TURN_SPEED if inside >= 0 else PLAYER_TURN_SPEED
	unit["yaw"] = float(unit["yaw"]) + turn * speed * dt
	yaw = float(unit["yaw"])
	return yaw


## Strzał gracza (z pojazdu, gdy gracz jest w środku).
func player_fire() -> bool:
	if result != "":
		return false
	var shooter: Dictionary = _shooter()
	if shooter.is_empty() or not bool(shooter["alive"]):
		return false
	var target: Dictionary = _nearest_enemy(shooter)
	if target.is_empty():
		last_message = "Brak celu."
		return false
	return _fire(shooter, target)


## Wsiadanie i wysiadanie z pojazdu własnej strony.
func player_toggle_vehicle() -> bool:
	var unit: Dictionary = _player_unit()
	if unit.is_empty() or not bool(unit["alive"]):
		return false
	if inside >= 0:
		var veh: Dictionary = _vehicle()
		inside = -1
		unit["x"] = clampf(float(veh["x"]) - 3.0, 2.0, FIELD_W - 2.0)
		unit["z"] = clampf(float(veh["z"]) + 3.0, 2.0, FIELD_H - 2.0)
		unit["yaw"] = float(veh["yaw"])
		last_message = "Wysiadłeś."
		return true
	var best: int = -1
	var best_dist: float = VEHICLE_ENTER_RANGE
	for i in range(units.size()):
		var other: Dictionary = units[i]
		if bool(other["is_player"]) or not bool(other["alive"]):
			continue
		if bool(other["side"]) != true:
			continue
		if not UnitsData.is_vehicle(str(other["cls"])):
			continue
		var dist: float = _distance(unit, other)
		if dist <= best_dist:
			best_dist = dist
			best = i
	if best < 0:
		last_message = "Brak pojazdu w pobliżu."
		return false
	inside = best
	var veh: Dictionary = units[best]
	unit["x"] = veh["x"]
	unit["z"] = veh["z"]
	unit["yaw"] = float(veh["yaw"])
	last_message = "Wsiadłeś do pojazdu."
	return true


## Przerwanie bitwy przez gracza (klawisz Enter) — liczone jako odwrót.
func abort_battle() -> void:
	if result != "":
		return
	result = "retreat"
	player_retreated = true
	last_message = "Bitwa przerwana — odwrót do kampanii."


## Odwrót: działa tylko na zachodnim skraju pola (x < 40 m).
func player_retreat() -> bool:
	var unit: Dictionary = _player_unit()
	if unit.is_empty() or not bool(unit["alive"]):
		return false
	if float(unit["x"]) < 40.0:
		result = "retreat"
		player_retreated = true
		last_message = "Odwrót — wracasz do kampanii."
		return true
	last_message = "Odwrót możliwy tylko na zachodnim skraju pola (x < 40 m)."
	return false


# --- przebieg bitwy ----------------------------------------------------------


func update(dt: float) -> void:
	if result != "":
		return
	time += dt
	_check_mines()
	_ai(dt)
	_check_end()


func _ai(dt: float) -> void:
	for unit in units:
		if not bool(unit["alive"]) or bool(unit["is_player"]):
			continue
		var target: Dictionary = _nearest_enemy(unit)
		if target.is_empty():
			continue
		var stop: float = float(STOP_DISTANCE.get(str(unit["personality"]), 200.0))
		var dist: float = _distance(unit, target)
		var holding: bool = str(unit["personality"]) == "defender"
		var can_advance: bool = float(org[bool(unit["side"])]) >= ORG_MIN_ADVANCE
		if dist > stop and can_advance and not holding:
			_advance(unit, target, dt)
		else:
			_fire(unit, target, true)


func _advance(unit: Dictionary, target: Dictionary, dt: float) -> void:
	var speed: float = _speed_of(str(unit["cls"]))
	if _is_forest():
		speed *= FOREST_SPEED_FACTOR
	var dx: float = float(target["x"]) - float(unit["x"])
	var dz: float = float(target["z"]) - float(unit["z"])
	var length: float = sqrt(dx * dx + dz * dz)
	if length < 0.001:
		return
	unit["yaw"] = atan2(dz, dx)
	unit["x"] = float(unit["x"]) + dx / length * speed * dt
	unit["z"] = float(unit["z"]) + dz / length * speed * dt


## Strzał: wybór broni, warunki trafienia, przeładowanie.
func _fire(shooter: Dictionary, target: Dictionary, quiet: bool = false) -> bool:
	var weapon: Dictionary = _best_weapon(shooter, target)
	if weapon.is_empty():
		if not quiet:
			if _can_engage(shooter, target):
				last_message = "Bronie się przeładowują."
			else:
				last_message = "Brak broni zdolnej razić ten cel."
		return false
	if not _can_hit(shooter, target, weapon):
		if not quiet:
			last_message = "Cel poza zasięgiem albo zasłonięty."
		return false
	shooter["weapon"] = str(weapon["id"])
	shooter["ready_at"] = time + float(weapon["reload"]) * _reload_mult(bool(shooter["side"]))
	if _fire_roll(shooter, target, weapon):
		_kill(target)
		if not quiet:
			last_message = "%s trafiony (%s)." % [str(target["name"]), str(weapon["name"])]
		return true
	if not quiet:
		last_message = "Strzał chybiony."
	return false


## Najlepsza gotowa broń zdolna razić cel (acc × 3 przy zgodnej kontrze).
func _best_weapon(unit: Dictionary, target: Dictionary) -> Dictionary:
	var cls: String = str(target["cls"])
	var dist: float = _distance(unit, target)
	var best: Dictionary = {}
	var best_score: float = -1.0
	for weapon in _weapons_for(str(unit["def_id"]), str(unit["cls"])):
		if float(unit["ready_at"]) > time:
			continue  # broń jeszcze się przeładowuje
		var targets: Array = weapon["targets"]
		if not targets.has(cls):
			continue
		if float(weapon["range"]) < dist:
			continue
		var score: float = float(weapon["acc"])
		if str(weapon["anti"]) == cls:
			score *= 3.0
		if score > best_score:
			best_score = score
			best = weapon
	return best


## Czy jednostka ma w ogóle czym razić ten cel (niezależnie od przeładowania).
func _can_engage(unit: Dictionary, target: Dictionary) -> bool:
	var cls: String = str(target["cls"])
	var dist: float = _distance(unit, target)
	for weapon in _weapons_for(str(unit["def_id"]), str(unit["cls"])):
		if not (weapon["targets"] as Array).has(cls):
			continue
		if float(weapon["range"]) >= dist:
			return true
	return false


func _weapons_for(def_id: String, cls: String) -> Array:
	var out: Array = []
	if UNIT_WEAPONS.has(def_id):
		for id in UNIT_WEAPONS[def_id]:
			out.append(WEAPONS[id])
		return out
	if cls == UnitsData.CLS_ARMOR:
		return [WEAPONS["gun"], WEAPONS["hmg"]]
	if cls == UnitsData.CLS_MECH:
		return [WEAPONS["hmg"]]
	return [WEAPONS["rifle"]]


## Czy strzał w ogóle może dojść: zasięg, noc, przeszkody terenowe.
func _can_hit(shooter: Dictionary, target: Dictionary, weapon: Dictionary) -> bool:
	var dist: float = _distance(shooter, target)
	if dist > float(weapon["range"]):
		return false
	if night and dist > NIGHT_RANGE:
		return false
	return not _los_blocked(shooter, target)


func _fire_roll(shooter: Dictionary, target: Dictionary, weapon: Dictionary) -> bool:
	var chance: float = float(weapon["acc"])
	chance *= _org_mult(bool(shooter["side"]))
	chance *= _skill_mult(shooter)
	if bool(shooter["is_player"]) or (inside >= 0 and is_same(shooter, _vehicle())):
		chance *= PLAYER_HIT_FACTOR
	chance *= _cover_for(_terrain_at_pos(target))
	if night:
		chance *= NIGHT_HIT_FACTOR
	chance = minf(chance, MAX_HIT_CHANCE)
	return rng.next() < chance


## Mnożnik zorganizowania strony: 0,7 + 0,3 · organizacja/100.
func _org_mult(side_value: bool) -> float:
	return 0.7 + 0.3 * float(org[side_value]) / 100.0


## Mnożnik czasu przeładowania: 1 + (1 − organizacja/100) · 0,8.
func _reload_mult(side_value: bool) -> float:
	return 1.0 + (1.0 - float(org[side_value]) / 100.0) * 0.8


func _skill_mult(unit: Dictionary) -> float:
	return 0.8 + 0.1 * float(unit["skill"])


func _cover_for(terrain_kind: String) -> float:
	return float(COVER.get(terrain_kind, 1.0))


## Śmierć jednostki; strata dowódcy łamie zorganizowanie strony.
func _kill(unit: Dictionary) -> void:
	if not bool(unit["alive"]):
		return
	unit["alive"] = false
	if bool(unit["is_commander"]):
		org[bool(unit["side"])] = 40.0
		if bool(unit["side"]):
			cmd_lost_friend = true
			last_message = "Poległ nasz dowódca!"
		else:
			cmd_lost_enemy = true
			last_message = "Poległ dowódca wroga!"
	if bool(unit["is_player"]):
		last_message = "Gracz poległ."


## Miny: niszczą pojazd w promieniu 3 m (razem z załogą) i znikają.
func _check_mines() -> void:
	if mines.is_empty():
		return
	for i in range(mines.size() - 1, -1, -1):
		var mine: Dictionary = mines[i]
		var hit: Dictionary = {}
		for unit in units:
			if not bool(unit["alive"]):
				continue
			if not UnitsData.is_vehicle(str(unit["cls"])):
				continue
			var dx: float = float(unit["x"]) - float(mine["x"])
			var dz: float = float(unit["z"]) - float(mine["z"])
			if sqrt(dx * dx + dz * dz) <= MINE_RADIUS:
				hit = unit
				break
		if hit.is_empty():
			continue
		_kill(hit)
		mines.remove_at(i)
		last_message = "Mina! %s zniszczony." % str(hit["name"])
		if inside >= 0 and is_same(hit, units[inside]):
			_kill(_player_unit())


## Warunki zakończenia bitwy.
func _check_end() -> String:
	if result != "":
		return result
	var unit: Dictionary = _player_unit()
	if not unit.is_empty() and not bool(unit["alive"]):
		result = "loss"
		return result
	for other in units:
		if not bool(other["side"]) and bool(other["alive"]):
			if time >= MAX_TIME:
				result = "stalemate"
			return result
	result = "win"
	return result


## Wynik bitwy: ocalali jako kopie wpisów armii.
func outcome() -> Dictionary:
	var friends: Array = []
	var foes: Array = []
	for unit in units:
		if not bool(unit["alive"]):
			continue
		if bool(unit["side"]):
			friends.append(_ref_copy(unit))
		else:
			foes.append(_ref_copy(unit))
	return {
		"result": "stalemate" if result == "" else result,
		"player_survivors": friends,
		"enemy_survivors": foes,
		"player_retreated": player_retreated,
		"commander_lost": cmd_lost_friend,
		"enemy_commander_lost": cmd_lost_enemy,
	}


# --- pomocnicze --------------------------------------------------------------


func _ref_copy(unit: Dictionary) -> Dictionary:
	var ref: Dictionary = unit["ref"]
	return ref.duplicate(true)


## Jednostka gracza (publiczne dla widoku bitwy).
func player_unit() -> Dictionary:
	return _player_unit()


func _player_unit() -> Dictionary:
	for unit in units:
		if bool(unit["is_player"]):
			return unit
	return {}


func _vehicle() -> Dictionary:
	if inside < 0 or inside >= units.size():
		return {}
	return units[inside]


## Ten, kto strzela: gracz, a gdy siedzi w pojeździe — pojazd.
func _shooter() -> Dictionary:
	if inside >= 0:
		return _vehicle()
	return _player_unit()


func _nearest_enemy(unit: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_dist: float = 1e30
	for other in units:
		if not bool(other["alive"]):
			continue
		if bool(other["side"]) == bool(unit["side"]):
			continue
		var dist: float = _distance(unit, other)
		if dist < best_dist:
			best_dist = dist
			best = other
	return best


func _distance(a: Dictionary, b: Dictionary) -> float:
	var dx: float = float(a["x"]) - float(b["x"])
	var dz: float = float(a["z"]) - float(b["z"])
	return sqrt(dx * dx + dz * dz)


static func _speed_of(cls: String) -> float:
	if cls == UnitsData.CLS_MECH:
		return SPEED_MECH
	if cls == UnitsData.CLS_ARMOR:
		return SPEED_ARMOR
	return SPEED_INFANTRY


func _terrain_at_pos(_pos) -> String:
	return terrain


## Czy bitwa toczy się w lesie (nazwa polska albo angielska).
func _is_forest() -> bool:
	return terrain.begins_with("las") or terrain.begins_with("forest")


## Czy linia strzału przecina którąś z przeszkód terenowych.
func _los_blocked(shooter: Dictionary, target: Dictionary) -> bool:
	var ax: float = float(shooter["x"])
	var az: float = float(shooter["z"])
	var bx: float = float(target["x"])
	var bz: float = float(target["z"])
	for obstacle in obstacles:
		var ox: float = float(obstacle["x"])
		var oz: float = float(obstacle["z"])
		var radius: float = float(obstacle["r"])
		var cx: float = ox - ax
		var cz: float = oz - az
		var dx: float = bx - ax
		var dz: float = bz - az
		var length_sq: float = dx * dx + dz * dz
		if length_sq < 0.0001:
			continue
		var t: float = (cx * dx + cz * dz) / length_sq
		if t < 0.0 or t > 1.0:
			continue
		var px: float = ax + dx * t - ox
		var pz: float = az + dz * t - oz
		if px * px + pz * pz <= radius * radius:
			return true
	return false


# --- informacje dla interfejsu ----------------------------------------------


func alive_counts() -> Dictionary:
	var friends: int = 0
	var foes: int = 0
	for unit in units:
		if not bool(unit["alive"]):
			continue
		if bool(unit["side"]):
			friends += 1
		else:
			foes += 1
	return {"friends": friends, "enemies": foes}


func player_weapon_name() -> String:
	var shooter: Dictionary = _shooter()
	if shooter.is_empty():
		return "-"
	var target: Dictionary = _nearest_enemy(shooter)
	if target.is_empty():
		return "brak celu"
	var weapon: Dictionary = _best_weapon(shooter, target)
	if weapon.is_empty():
		return "brak broni na ten cel"
	return str(weapon["name"])


func distance_to_nearest_enemy() -> float:
	var shooter: Dictionary = _shooter()
	if shooter.is_empty():
		return -1.0
	var target: Dictionary = _nearest_enemy(shooter)
	if target.is_empty():
		return -1.0
	return _distance(shooter, target)


func time_left() -> float:
	return maxf(0.0, MAX_TIME - time)


func eye_height() -> float:
	return VEHICLE_EYE if inside >= 0 else PLAYER_EYE
