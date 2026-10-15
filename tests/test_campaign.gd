extends SceneTree
## Test 2: kampania — wartości startowe, marsz, ekonomia, zwiad, przeprawy,
## rozliczenie bitwy i zwycięstwo.

const Campaign = preload("res://scripts/logic/campaign.gd")
const Terrain = preload("res://scripts/logic/terrain.gd")
const Pathfind = preload("res://scripts/logic/pathfind.gd")
const Army = preload("res://scripts/logic/army.gd")
const UnitsData = preload("res://scripts/logic/units_data.gd")
const Enemy = preload("res://scripts/logic/enemy.gd")
const Ferry = preload("res://scripts/logic/ferry.gd")
const Difficulty = preload("res://scripts/logic/difficulty.gd")

var failures: Array = []


func _initialize() -> void:
	print("== test_campaign ==")
	_test_start_values()
	_test_move()
	_test_economy()
	_test_scout()
	_test_ferry_and_bridge()
	_test_battle_outcome()
	_test_victory_and_limits()
	_report()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		print("  BŁĄD: %s" % message)


func _test_start_values() -> void:
	var c = Campaign.new("us", 7)
	_check(int(c.food) == 400, "Żywność startowa powinna wynosić 400 (jest %d)" % int(c.food))
	_check(int(c.funds) == 300, "Fundusze startowe powinny wynosić 300 (jest %d)" % int(c.funds))
	_check(int(c.morale) == 80, "Morale startowe powinno wynosić 80 (jest %d)" % int(c.morale))
	_check(int(c.hours) == 8, "Startowa godzina to 8")
	_check(int(c.day) == 1, "Startowy dzień to 1")
	_check(c.army.size() >= 1, "Brak wojska na start")
	_check(Army.validate(c.army).is_empty(), "Armia startowa łamie limity: %s" % str(Army.validate(c.army)))
	_check(c.objectives.size() == 3, "Powinny być 3 cele (są %d)" % c.objectives.size())
	for obj in c.objectives:
		var p := Vector2i(int(obj["x"]), int(obj["y"]))
		_check(Enemy.chebyshev(p, c.position) >= 15, "Cel %s jest bliżej niż 15 pól od startu" % str(obj["name"]))
	_check(c.enemies.size() >= 1, "Brak wrogów na mapie")
	var roaming: int = 0
	for enemy in c.enemies:
		if not bool(enemy["garrison"]):
			roaming += 1
			_check(Enemy.chebyshev(enemy["pos"], c.position) >= 12, "Wróg wędrujący startuje bliżej niż 12 pól")
	_check(roaming >= 1, "Brak oddziału wędrującego")
	_check(c.enemies.size() <= 6, "Za dużo oddziałów wroga")
	_check(c.boats.size() >= 1, "Brak łodzi na mapie")
	_check(c.fog.is_visible(c.position.x, c.position.y), "Pole startowe powinno być widoczne")


func _test_move() -> void:
	var c = Campaign.new("us", 7)
	# Miasto numer 1 (nie startowe), żeby trasa miała co najmniej kilka pól.
	var city: Dictionary = c.map["cities"][1]
	var target := Vector2i(int(city["x"]), int(city["y"]))
	var message: String = c.start_move(target)
	_check(message == "", "Marsz do miasta %s zwrócił komunikat: %s" % [str(city["name"]), message])
	_check(c.path.size() > 0, "Trasa do miasta jest pusta")
	var cost: float = Pathfind.path_cost(c.map, c.path)
	_check(cost > 0.0, "Koszt trasy powinien być dodatni")

	# Na czas testu marszu usuwamy wrogów — sprawdzamy samą mechanikę ruchu.
	# Uwaga: posiłki pojawiają się z czasem, a kontakt przerywa marsz, więc czyścimy
	# wrogów i ewentualną bitwę w każdej iteracji.
	c.enemies.clear()
	var start_position: Vector2i = c.position
	var guard: int = 0
	while c.path.size() > 0 and guard < 500:
		guard += 1
		c.enemies.clear()
		c.pending_battle = null
		c.player_step()
	_check(c.position != start_position, "Gracz nie ruszył się z pola startowego")
	_check(c.position == target, "Gracz nie dotarł do celu (%s != %s)" % [str(c.position), str(target)])
	_check(c.hours > 8, "Marsz powinien zająć czas (godzina %d)" % c.hours)

	# Pole nieprzechodnie i pole poza mapą muszą dawać komunikaty.
	var lake := Vector2i(-1, -1)
	var tiles: PackedByteArray = c.map["tiles"]
	for i in range(tiles.size()):
		if tiles[i] == Terrain.Kind.LAKE:
			lake = Vector2i(i % int(c.map["w"]), int(i / int(c.map["w"])))
			break
	if lake.x >= 0:
		_check(c.start_move(lake) != "", "Marsz na jezioro powinien być niemożliwy")
	_check(c.start_move(Vector2i(999, 999)) != "", "Marsz poza mapę powinien być niemożliwy")


func _test_economy() -> void:
	var c = Campaign.new("us", 7)
	var food_before: int = c.food
	var army_size: int = c.army.size()
	for i in range(24):
		c.world_hour()
	_check(int(c.day) == 2, "Po 24 godzinach powinien być dzień 2 (jest %d)" % int(c.day))
	var eaten: int = food_before - c.food
	_check(eaten >= 0, "Żywność nie powinna rosnąć sama")
	_check(eaten <= army_size + 1, "Dzienny apetyt nie powinien przekraczać liczby jednostek (zjadł %d)" % eaten)
	_check(int(c.funds) >= 300, "Dochód dzienny powinien zwiększyć fundusze")

	var funds_before: int = c.funds
	var food_pack_before: int = c.food
	var message: String = c.buy_food()
	_check(message == "", "Zakup żywności zwrócił komunikat: %s" % message)
	_check(int(c.funds) == funds_before - 20, "Zakup żywności powinien kosztować 20 funduszy")
	_check(int(c.food) == food_pack_before + 50, "Paczka żywności powinna dawać 50")

	# Rekrutacja działa tylko w mieście.
	var c2 = Campaign.new("us", 21)
	_check(c2.is_city_here(), "Gracz powinien startować w mieście")
	var before_army: int = c2.army.size()
	var before_funds: int = c2.funds
	_check(c2.recruit_infantry() == "", "Rekrutacja w mieście powinna się udać")
	_check(c2.army.size() == before_army + 1, "Rekrutacja powinna dodać jednostkę")
	_check(int(c2.funds) == before_funds - 80, "Rekrutacja powinna kosztować 80 funduszy")

	var open_tile := Vector2i(-1, -1)
	var tiles: PackedByteArray = c2.map["tiles"]
	for i in range(tiles.size()):
		var p := Vector2i(i % int(c2.map["w"]), int(i / int(c2.map["w"])))
		if tiles[i] == Terrain.Kind.PLAINS and Pathfind.city_at(c2.map, p).is_empty():
			open_tile = p
			break
	if open_tile.x >= 0:
		c2.position = open_tile
		_check(c2.recruit_infantry() != "", "Rekrutacja poza miastem powinna być niemożliwa")
		_check(c2.rest() != "", "Odpoczynek poza miastem powinien być niemożliwy")

	# Wyczerpanie żywności obniża morale.
	var c3 = Campaign.new("us", 7)
	c3.food = 0
	var morale_before: int = c3.morale
	for i in range(24):
		c3.world_hour()
	_check(int(c3.morale) < morale_before, "Brak żywności powinien obniżyć morale")


func _test_scout() -> void:
	var c = Campaign.new("us", 42)
	var city: Dictionary = c.map["cities"][2]
	var target := Vector2i(int(city["x"]), int(city["y"]))
	var army_before: int = c.army.size()
	var message: String = c.dispatch_scout(target)
	_check(message == "", "Wysłanie zwiadowcy zwróciło komunikat: %s" % message)
	_check(c.scout != null, "Zwiadowca nie został zapisany")
	_check(c.army.size() == army_before - 1, "Zwiadowca powinien wyjść z oddziału")
	_check(c.dispatch_scout(target) != "", "Drugi zwiadowca nie powinien być możliwy")
	var guard: int = 0
	while c.scout != null and guard < 300:
		guard += 1
		c.world_hour()
	_check(c.scout == null, "Zwiadowca nie wrócił w rozsądnym czasie")
	_check(c.army.size() >= army_before - 1, "Po powrocie zwiadowcy armia powinna wrócić do stanu")
	_check(c.fog.known_fraction() > 0.0, "Zwiad powinien odsłonić mapę")


func _test_ferry_and_bridge() -> void:
	var c = Campaign.new("us", 19)
	var boat: Dictionary = c.boats[0]
	_check(Ferry.boat_at(c.boats, boat["pos"]) == 0, "boat_at nie znajduje łodzi")
	var crossing: Dictionary = Ferry.cross(boat)
	_check(crossing.has("to") and crossing.has("hours"), "cross powinien zwracać cel i czas")
	_check(float(crossing["hours"]) > 0.0, "Przeprawa powinna zająć trochę czasu")

	c.position = boat["pos"]
	var message: String = c.ferry_cross()
	_check(message == "", "Przeprawa łodzią zwróciła komunikat: %s" % message)
	_check(c.position == crossing["to"], "Po przeprawie gracz powinien być na drugim brzegu")

	_check(not c.can_build_bridge(), "Bez pojazdu inżynieryjnego most nie powinien być możliwy")
	# Znajdź brzeg, z którego da się przerzucić most, i dodaj pojazd inżynieryjny.
	var shore := Vector2i(-1, -1)
	var span: Array = []
	var w: int = int(c.map["w"])
	var h: int = int(c.map["h"])
	var tiles: PackedByteArray = c.map["tiles"]
	# find_span jest czyste — w przeciwieństwie do build_bridge nie zmienia mapy.
	for y in range(h):
		for x in range(w):
			var p := Vector2i(x, y)
			if not Terrain.is_passable(tiles[y * w + x]):
				continue
			span = Ferry.find_span(c.map, p)
			if not span.is_empty():
				shore = p
				break
		if shore.x >= 0:
			break
	if shore.x >= 0:
		c.position = shore
		c.army.append({"id": 999, "def_id": "us_eng_cev", "cls": "mech", "name": "M728 CEV (inżynieryjny)"})
		_check(c.can_build_bridge(), "Z pojazdem inżynieryjnym przy wodzie most powinien być możliwy")
		_check(span.size() >= 1, "Most powinien mieć co najmniej jedno przęsło")
		var message_bridge: String = c.build_bridge_at()
		_check(message_bridge == "", "Budowa mostu zwróciła komunikat: %s" % message_bridge)
		var after: PackedByteArray = c.map["tiles"]
		for span_tile in span:
			_check(after[span_tile.y * w + span_tile.x] == Terrain.Kind.BRIDGE, "Przęsło mostu nie jest mostem")
		# Po zbudowaniu mostu nie ma już wody do przerzucenia w tym miejscu.
		_check(not c.can_build_bridge(), "Po zbudowaniu mostu nie powinno być czego przerzucać")
	else:
		_check(false, "Nie znaleziono brzegu z przeprawą na mapie")


func _test_battle_outcome() -> void:
	var c = Campaign.new("us", 11)
	var enemy: Dictionary = c.enemies[0]
	var survivor: Dictionary = c.army[0].duplicate(true)
	var morale_before: int = c.morale
	var outcome := {
		"result": "loss",
		"player_survivors": [survivor],
		"enemy_survivors": [enemy["units"][0].duplicate(true)],
		"player_retreated": false,
		"commander_lost": true,
		"enemy_commander_lost": true,
	}
	c.pending_battle = enemy
	c.apply_battle_outcome(enemy, outcome)
	_check(c.army.size() == 1, "Armia po bitwie powinna liczyć 1 jednostkę (jest %d)" % c.army.size())
	_check(c.morale < morale_before, "Straty i śmierć dowódcy powinny obniżyć morale")
	_check(c.morale >= morale_before - 10 - 30, "Spadek morale nie może przekraczać 40 punktów")
	_check(int(enemy["organization"]) == 50, "Śmierć dowódcy wroga powinna ustawić organizację na 50")
	_check(c.enemies.has(enemy), "Oddział z ocalałymi powinien zostać na mapie")
	_check(c.pending_battle == null, "Po bitwie nie powinno być oczekującej bitwy")
	_check(c.contact_cooldown == 8, "Po bitwie obowiązuje 8 godzin przerwy w kontakcie")
	_check(absf(c.relief - 1.15) < 0.001, "Porażka powinna zwiększyć trudność (relief)")

	var c2 = Campaign.new("us", 12)
	var enemy2: Dictionary = c2.enemies[0]
	var outcome2 := {
		"result": "win",
		"player_survivors": c2.army.duplicate(true),
		"enemy_survivors": [],
		"player_retreated": false,
		"commander_lost": false,
		"enemy_commander_lost": false,
	}
	c2.apply_battle_outcome(enemy2, outcome2)
	_check(not c2.enemies.has(enemy2), "Rozbity oddział wroga powinien zniknąć z mapy")
	_check(c2.relief < 1.0, "Zwycięstwo powinno zmniejszyć trudność (relief)")

	var c3 = Campaign.new("us", 13)
	var empty := {
		"result": "loss",
		"player_survivors": [],
		"enemy_survivors": [],
		"player_retreated": false,
		"commander_lost": false,
		"enemy_commander_lost": false,
	}
	c3.apply_battle_outcome(c3.enemies[0], empty)
	_check(c3.over, "Brak wojska powinien kończyć kampanię")
	_check(not c3.victory, "Kampania bez wojska nie jest zwycięstwem")


func _test_victory_and_limits() -> void:
	var c = Campaign.new("us", 5)
	for obj in c.objectives:
		obj["owned"] = true
	c.world_hour()
	_check(c.over and c.victory, "Wszystkie cele zdobyte powinny dawać zwycięstwo")

	# Limity oddziału: 30 jednostek, 2 pancerne, 5 zmechanizowanych.
	var units: Array = []
	for i in range(31):
		units.append({"id": i + 1, "def_id": "us_inf_m16", "cls": "infantry", "name": "Piechota"})
	_check(not Army.validate(units).is_empty(), "Przekroczenie limitu 30 jednostek powinno być błędem")
	units = []
	for i in range(3):
		units.append({"id": i + 1, "def_id": "us_arm_m60a1", "cls": "armor", "name": "Czołg"})
	_check(not Army.validate(units).is_empty(), "Przekroczenie limitu pancernych powinno być błędem")
	units = []
	for i in range(6):
		units.append({"id": i + 1, "def_id": "us_mech_m113", "cls": "mech", "name": "Transporter"})
	_check(not Army.validate(units).is_empty(), "Przekroczenie limitu zmechanizowanych powinno być błędem")
	_check(UnitsData.LIMIT_TOTAL == 30 and UnitsData.LIMIT_ARMOR == 2 and UnitsData.LIMIT_MECH == 5, "Limity oddziału muszą pozostać niezmienione")
	_check(UnitsData.is_prototype("us_proto_xm803"), "XM803 powinien być prototypem")
	_check(UnitsData.is_prototype("su_proto_775"), "Obiekt 775 powinien być prototypem")
	for unit in UnitsData.defs_for("us", "armor"):
		_check(not bool(unit["prototype"]), "Prototypy nie mogą trafiać do losowej rekrutacji")

	_check(Difficulty.base_difficulty(1) < Difficulty.base_difficulty(10), "Trudność powinna rosnąć z dniami")
	_check(Difficulty.effective_difficulty(30, 2.0) <= 2.5, "Trudność nie może przekroczyć 2.5")
	_check(Difficulty.update_relief(0.5, "win") == 0.5, "Ulga nie może spaść poniżej 0.5")
	_check(Difficulty.enemy_army_size(1.0) >= 2, "Wróg powinien wystawiać co najmniej 2 jednostki")


func _report() -> void:
	if failures.is_empty():
		print("Wszystkie sprawdzenia kampanii przeszły.")
		print("RESULT: PASS")
		quit(0)
		return
	print("Niepowodzenia: %d" % failures.size())
	print("RESULT: FAIL")
	quit(1)
