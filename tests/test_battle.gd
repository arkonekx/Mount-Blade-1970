extends SceneTree
## Test 3: symulacja bitwy — wybór broni, trafienia, dowódca, miny, AI,
## pojazd gracza, odwrót i warunki zakończenia.

const BattleSim = preload("res://scripts/battle/battle_sim.gd")
const UnitsData = preload("res://scripts/logic/units_data.gd")

var failures: Array = []


func _initialize() -> void:
	print("== test_battle ==")
	_test_layout()
	_test_best_weapon()
	_test_can_hit()
	_test_fire_roll()
	_test_commander_and_end()
	_test_mines()
	_test_ai()
	_test_player_vehicle_and_retreat()
	_test_outcome()
	_report()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		print("  BŁĄD: %s" % message)


func _unit(id: int, def_id: String, cls: String, name: String) -> Dictionary:
	return {"id": id, "def_id": def_id, "cls": cls, "name": name}


func _us_army() -> Array:
	return [
		_unit(1, "us_inf_m16", "infantry", "Piechota (M16A1)"),
		_unit(2, "us_inf_law", "infantry", "Drużyna ppanc (M72 LAW)"),
		_unit(3, "us_mech_m113", "mech", "M113 ACAV"),
		_unit(4, "us_arm_m60a1", "armor", "M60A1"),
		_unit(5, "us_inf_m16", "infantry", "Piechota (M16A1)"),
	]


func _su_army() -> Array:
	return [
		_unit(101, "su_inf_ak", "infantry", "Piechota (AKM)"),
		_unit(102, "su_inf_rpg", "infantry", "Drużyna ppanc (RPG-7)"),
		_unit(103, "su_mech_bmp1", "mech", "BMP-1"),
		_unit(104, "su_arm_t62", "armor", "T-62 Obr. 1972"),
	]


func _new_sim(enemy_info: Dictionary = {}, terrain_name: String = "równina", night: bool = false) -> RefCounted:
	var info: Dictionary = {"skill": 3, "personality": "aggressive"}
	for key in enemy_info.keys():
		info[key] = enemy_info[key]
	return BattleSim.new(_us_army(), _su_army(), info, terrain_name, 2024, night)


func _enemy_unit(sim, cls: String) -> Dictionary:
	for unit in sim.units:
		if not bool(unit["side"]) and str(unit["cls"]) == cls:
			return unit
	return {}


func _friend_unit(sim, cls: String) -> Dictionary:
	for unit in sim.units:
		if bool(unit["side"]) and str(unit["cls"]) == cls and not bool(unit["is_player"]):
			return unit
	return {}


func _player_unit(sim) -> Dictionary:
	return sim._player_unit()


func _test_layout() -> void:
	var sim = _new_sim()
	var player: Dictionary = _player_unit(sim)
	_check(not player.is_empty(), "Brak jednostki gracza")
	_check(absf(float(player["x"]) - 60.0) < 0.001 and absf(float(player["z"]) - 200.0) < 0.001, "Gracz powinien startować na polu (60, 200)")
	for unit in sim.units:
		if bool(unit["side"]) and not bool(unit["is_player"]):
			_check(float(unit["x"]) >= 40.0 and float(unit["x"]) <= 110.0, "Nasi powinni startować na zachodzie")
		if not bool(unit["side"]):
			_check(float(unit["x"]) >= 900.0 and float(unit["x"]) <= 970.0, "Wróg powinien startować na wschodzie")
	_check(sim.obstacles.size() == 5, "Na równinie powinno być 5 przeszkód (jest %d)" % sim.obstacles.size())
	_check(_new_sim({}, "las").obstacles.size() == 35, "W lesie powinno być 35 drzew")
	_check(_new_sim({}, "wzgórza").obstacles.size() == 10, "Na wzgórzach powinno być 10 przeszkód")
	_check(sim.mines.size() >= 1, "Na polu powinny być miny")
	_check(absf(sim._org_mult(true) - 1.0) < 0.001, "Świeże zorganizowanie to 1.0")


func _test_best_weapon() -> void:
	var sim = _new_sim()
	sim.time = 10.0
	var infantry: Dictionary = _player_unit(sim)
	var enemy_infantry: Dictionary = _enemy_unit(sim, "infantry")
	var enemy_armor: Dictionary = _enemy_unit(sim, "armor")
	var enemy_mech: Dictionary = _enemy_unit(sim, "mech")

	infantry["ready_at"] = 0.0
	enemy_infantry["x"] = float(infantry["x"]) + 100.0
	enemy_infantry["z"] = float(infantry["z"])
	enemy_armor["x"] = float(infantry["x"]) + 100.0
	enemy_armor["z"] = float(infantry["z"])
	enemy_mech["x"] = float(infantry["x"]) + 100.0
	enemy_mech["z"] = float(infantry["z"])

	_check(str(sim._best_weapon(infantry, enemy_infantry).get("id", "")) == "rifle", "Piechota powinna strzelać z karabinu do piechoty")
	_check(sim._best_weapon(infantry, enemy_armor).is_empty(), "Karabin nie może razić czołgu")
	_check(sim._best_weapon(infantry, enemy_mech).is_empty(), "Karabin nie może razić pojazdu zmechanizowanego")

	var at_team: Dictionary = _friend_unit(sim, "infantry")
	# znajdź drużynę z wyrzutnią ppanc (def_id us_inf_law)
	for unit in sim.units:
		if bool(unit["side"]) and str(unit["def_id"]) == "us_inf_law":
			at_team = unit
			break
	at_team["ready_at"] = 0.0
	at_team["x"] = float(enemy_armor["x"]) - 200.0
	at_team["z"] = float(enemy_armor["z"])
	_check(str(sim._best_weapon(at_team, enemy_armor).get("id", "")) == "at", "Drużyna ppanc powinna wybrać wyrzutnię do czołgu")

	var tank: Dictionary = _friend_unit(sim, "armor")
	tank["ready_at"] = 0.0
	tank["x"] = float(enemy_armor["x"]) - 500.0
	tank["z"] = float(enemy_armor["z"])
	_check(str(sim._best_weapon(tank, enemy_armor).get("id", "")) == "gun", "Czołg powinien wybrać armatę do czołgu")

	# Przeładowanie: broń jeszcze niegotowa.
	tank["ready_at"] = 100.0
	sim.time = 10.0
	_check(sim._best_weapon(tank, enemy_armor).is_empty(), "Przeładowana broń nie powinna być wybierana")


func _test_can_hit() -> void:
	var sim = _new_sim()
	sim.obstacles = []
	sim.time = 10.0
	var infantry: Dictionary = _player_unit(sim)
	var enemy: Dictionary = _enemy_unit(sim, "infantry")
	infantry["ready_at"] = 0.0
	var rifle: Dictionary = BattleSim.WEAPONS["rifle"]
	var gun: Dictionary = BattleSim.WEAPONS["gun"]

	enemy["x"] = float(infantry["x"]) + 200.0
	enemy["z"] = float(infantry["z"])
	_check(sim._can_hit(infantry, enemy, rifle), "Strzał z karabinu na 200 m powinien być możliwy")
	enemy["x"] = float(infantry["x"]) + 400.0
	_check(not sim._can_hit(infantry, enemy, rifle), "Karabin nie sięga 400 m")

	# Noc skraca zasięg do 350 m.
	var night_sim = _new_sim({}, "równina", true)
	night_sim.obstacles = []
	night_sim.time = 10.0
	var night_shooter: Dictionary = night_sim._player_unit()
	var night_target: Dictionary = _enemy_unit(night_sim, "armor")
	night_target["x"] = float(night_shooter["x"]) + 500.0
	night_target["z"] = float(night_shooter["z"])
	_check(not night_sim._can_hit(night_shooter, night_target, gun), "Nocą nie strzela się dalej niż 350 m")
	night_target["x"] = float(night_shooter["x"]) + 300.0
	_check(night_sim._can_hit(night_shooter, night_target, gun), "Nocą strzał na 300 m powinien być możliwy")

	# Przeszkoda przecinająca linię strzału.
	sim.obstacles = [{"x": float(infantry["x"]) + 100.0, "z": float(infantry["z"]), "r": 8.0}]
	enemy["x"] = float(infantry["x"]) + 200.0
	_check(not sim._can_hit(infantry, enemy, rifle), "Przeszkoda powinna blokować strzał")
	sim.obstacles = [{"x": float(infantry["x"]) + 100.0, "z": float(infantry["z"]) + 50.0, "r": 2.0}]
	_check(sim._can_hit(infantry, enemy, rifle), "Przeszkoda obok linii strzału nie może blokować")


func _test_fire_roll() -> void:
	var sim = _new_sim()
	sim.obstacles = []
	sim.time = 10.0
	var shooter: Dictionary = _player_unit(sim)
	var target: Dictionary = _enemy_unit(sim, "infantry")
	target["x"] = float(shooter["x"]) + 100.0
	target["z"] = float(shooter["z"])
	var rifle: Dictionary = BattleSim.WEAPONS["rifle"]

	var hits: int = 0
	var rolls: int = 2000
	for i in range(rolls):
		if sim._fire_roll(shooter, target, rifle):
			hits += 1
	var rate: float = float(hits) / float(rolls)
	_check(rate > 0.05 and rate < 0.30, "Gracz z karabinu powinien trafiać w 5-30%% przypadków (trafił %.3f)" % rate)

	# Wróg bez premii gracza trafia rzadziej.
	var enemy_shooter: Dictionary = _enemy_unit(sim, "infantry")
	enemy_shooter["x"] = float(shooter["x"]) + 400.0
	var enemy_hits: int = 0
	for i in range(rolls):
		if sim._fire_roll(enemy_shooter, shooter, rifle):
			enemy_hits += 1
	_check(float(enemy_hits) < float(hits), "Wróg nie powinien trafiać częściej niż gracz")

	# Szansa jest ograniczona do 0.9.
	var strong: Dictionary = {"acc": 5.0, "anti": "infantry", "id": "test", "name": "test", "reload": 1.0, "range": 1000.0, "targets": ["infantry"]}
	var strong_hits: int = 0
	for i in range(rolls):
		if sim._fire_roll(shooter, target, strong):
			strong_hits += 1
	_check(float(strong_hits) / float(rolls) < 0.95, "Szansa trafienia nie może przekraczać 0.9")
	_check(float(strong_hits) / float(rolls) > 0.80, "Szansa trafienia powinna sięgać sufitu 0.9")


func _test_commander_and_end() -> void:
	var sim = _new_sim()
	var enemy_commander: Dictionary = {}
	var friend_commander: Dictionary = {}
	for unit in sim.units:
		if bool(unit["is_commander"]):
			if bool(unit["side"]):
				friend_commander = unit
			else:
				enemy_commander = unit
	_check(not enemy_commander.is_empty(), "Wróg powinien mieć dowódcę")
	_check(not friend_commander.is_empty(), "Strona gracza powinna mieć dowódcę")
	_check(not bool(friend_commander["is_player"]), "Dowódca nie może być graczem")
	_check(str(friend_commander["cls"]) == "infantry", "Dowódca powinien być piechurem")

	sim._kill(enemy_commander)
	_check(float(sim.org[false]) == 40.0, "Śmierć dowódcy wroga powinna ustawić organizację 40")
	_check(sim.cmd_lost_enemy, "Powinna być flaga straty dowódcy wroga")
	_check(sim.result == "", "Śmierć dowódcy nie kończy bitwy")
	_check(sim._check_end() == "", "Bitwa powinna trwać dalej")

	# Śmierć gracza kończy bitwę porażką, nawet gdy sojusznicy żyją.
	var player: Dictionary = _player_unit(sim)
	sim._kill(player)
	_check(sim._check_end() == "loss", "Śmierć gracza powinna kończyć bitwę porażką")
	var allies_alive: int = 0
	for unit in sim.units:
		if bool(unit["side"]) and bool(unit["alive"]) and not bool(unit["is_player"]):
			allies_alive += 1
	_check(allies_alive > 0, "Test wymaga żywych sojuszników")

	# Wszyscy wrogowie martwi → zwycięstwo.
	var sim2 = _new_sim()
	for unit in sim2.units:
		if not bool(unit["side"]):
			sim2._kill(unit)
	_check(sim2._check_end() == "win", "Brak wrogów powinien dawać zwycięstwo")

	# Upływ czasu → brak rozstrzygnięcia.
	var sim3 = _new_sim()
	sim3.time = 600.0
	_check(sim3._check_end() == "stalemate", "Po 600 s bitwa powinna się kończyć bez rozstrzygnięcia")


## Odstawia wszystkie pojazdy poza obszar miny, żeby test był jednoznaczny.
func _park_vehicles(sim, keep: Dictionary) -> void:
	var index: int = 0
	for unit in sim.units:
		if not UnitsData.is_vehicle(str(unit["cls"])):
			continue
		if is_same(unit, keep):
			continue
		unit["x"] = 985.0
		unit["z"] = 8.0 + float(index) * 12.0
		index += 1


func _test_mines() -> void:
	var sim = _new_sim()
	var vehicle: Dictionary = _enemy_unit(sim, "mech")
	_park_vehicles(sim, vehicle)
	sim.mines = [{"x": float(vehicle["x"]), "z": float(vehicle["z"])}]
	var before: int = sim.mines.size()
	sim._check_mines()
	_check(not bool(vehicle["alive"]), "Mina powinna zniszczyć pojazd zmechanizowany")
	_check(sim.mines.size() == before - 1, "Mina powinna zniknąć po wybuchu")

	var sim2 = _new_sim()
	var tank: Dictionary = _enemy_unit(sim2, "armor")
	_park_vehicles(sim2, tank)
	sim2.mines = [{"x": float(tank["x"]), "z": float(tank["z"])}]
	sim2._check_mines()
	_check(not bool(tank["alive"]), "Mina powinna zniszczyć czołg")

	var sim3 = _new_sim()
	var infantry: Dictionary = _enemy_unit(sim3, "infantry")
	_park_vehicles(sim3, {})
	sim3.mines = [{"x": float(infantry["x"]), "z": float(infantry["z"])}]
	sim3._check_mines()
	_check(bool(infantry["alive"]), "Mina nie powinna zabijać piechoty")
	_check(sim3.mines.size() == 1, "Mina nie powinna znikać bez ofiary")


func _test_ai() -> void:
	var sim = _new_sim()
	sim.obstacles = []
	sim.time = 10.0
	var enemy: Dictionary = _enemy_unit(sim, "infantry")
	var player: Dictionary = _player_unit(sim)
	enemy["x"] = 600.0
	enemy["z"] = 200.0
	player["x"] = 60.0
	player["z"] = 200.0
	enemy["ready_at"] = 0.0
	var x_before: float = float(enemy["x"])
	sim._ai(1.0)
	_check(float(enemy["x"]) < x_before, "Agresywny wróg powinien podejść do gracza")

	# Obrońca trzyma pozycję.
	var defender = _new_sim({"personality": "defender"})
	defender.obstacles = []
	defender.time = 10.0
	var defender_unit: Dictionary = _enemy_unit(defender, "infantry")
	defender_unit["x"] = 600.0
	defender_unit["z"] = 200.0
	var defender_x: float = float(defender_unit["x"])
	defender._ai(1.0)
	_check(absf(float(defender_unit["x"]) - defender_x) < 0.001, "Obrońca nie powinien atakować")

	# Przy organizacji poniżej 30 AI nie idzie do przodu.
	var broken = _new_sim()
	broken.obstacles = []
	broken.time = 10.0
	broken.org[false] = 20.0
	var broken_unit: Dictionary = _enemy_unit(broken, "infantry")
	broken_unit["x"] = 600.0
	broken_unit["z"] = 200.0
	broken_unit["ready_at"] = 0.0
	var broken_x: float = float(broken_unit["x"])
	broken._ai(1.0)
	_check(absf(float(broken_unit["x"]) - broken_x) < 0.001, "Złamana organizacja powinna zatrzymać natarcie")


func _test_player_vehicle_and_retreat() -> void:
	var sim = _new_sim()
	sim.obstacles = []
	var player: Dictionary = _player_unit(sim)
	var vehicle: Dictionary = _friend_unit(sim, "mech")
	vehicle["x"] = float(player["x"]) + 4.0
	vehicle["z"] = float(player["z"])
	_check(sim.player_toggle_vehicle(), "Wsiadanie do pojazdu powinno się udać")
	_check(sim.inside >= 0, "Gracz powinien być w pojeździe")
	_check(absf(float(player["x"]) - float(vehicle["x"])) < 0.001, "Pozycja gracza powinna równać się pozycji pojazdu")
	sim.player_input(1.0, 1.0, 0.0)
	_check(absf(float(player["x"]) - float(vehicle["x"])) < 0.001, "Po ruchu gracz nadal siedzi w pojeździe")
	_check(sim.player_toggle_vehicle(), "Wysiadanie powinno się udać")
	_check(sim.inside < 0, "Gracz powinien być na piechocie")

	player["x"] = 200.0
	_check(not sim.player_retreat(), "Odwrót w środku pola nie powinien działać")
	player["x"] = 20.0
	_check(sim.player_retreat(), "Odwrót na zachodnim skraju powinien działać")
	_check(sim.result == "retreat", "Wynikiem odwrotu powinno być retreat")


func _test_outcome() -> void:
	var sim = _new_sim()
	var player: Dictionary = _player_unit(sim)
	sim._kill(player)
	sim._check_end()
	var outcome: Dictionary = sim.outcome()
	_check(str(outcome["result"]) == "loss", "Wynik powinien brzmieć loss")
	_check(outcome.has("player_survivors"), "Brak listy ocalałych")
	_check(outcome.has("enemy_survivors"), "Brak listy ocalałych wroga")
	_check(bool(outcome["commander_lost"]) == false, "Dowódca nie poległ w tym teście")
	_check(outcome["enemy_survivors"].size() == 4, "Powinno ocalać 4 wrogów")

	var survivor: Dictionary = outcome["player_survivors"][0]
	_check(survivor.has("id") and survivor.has("def_id") and survivor.has("cls") and survivor.has("name"), "Ocalali powinni być wpisami armii")
	var same_object: bool = false
	for unit in sim.units:
		if is_same(unit["ref"], survivor):
			same_object = true
	_check(not same_object, "Ocalali muszą być kopiami, a nie obiektami symulacji")


func _report() -> void:
	if failures.is_empty():
		print("Wszystkie sprawdzenia bitwy przeszły.")
		print("RESULT: PASS")
		quit(0)
		return
	print("Niepowodzenia: %d" % failures.size())
	print("RESULT: FAIL")
	quit(1)
