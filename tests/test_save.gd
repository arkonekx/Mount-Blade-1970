extends SceneTree
## Test 4: zapis i odczyt kampanii (jeden slot, wersja 1).

const Campaign = preload("res://scripts/logic/campaign.gd")
const GameState = preload("res://scripts/game_state.gd")
const Fog = preload("res://scripts/logic/fog.gd")

var failures: Array = []


func _initialize() -> void:
	print("== test_save ==")
	_test_round_trip()
	_test_slot_file()
	_report()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		print("  BŁĄD: %s" % message)


func _test_round_trip() -> void:
	var c = Campaign.new("us", 123)
	# Rozruszaj kampanię, żeby zapis nie był stanem początkowym.
	for i in range(6):
		c.world_hour()
	var city: Dictionary = c.map["cities"][1]
	c.start_move(Vector2i(int(city["x"]), int(city["y"])))
	for i in range(3):
		c.player_step()
	c.dispatch_scout(Vector2i(int(c.map["cities"][2]["x"]), int(c.map["cities"][2]["y"])))
	c.pending_battle = c.enemies[0]

	var data: Dictionary = c.to_dict()
	_check(int(data["version"]) == 1, "Wersja zapisu powinna wynosić 1")
	var text: String = JSON.stringify(data)
	var parsed: Variant = JSON.parse_string(text)
	_check(typeof(parsed) == TYPE_DICTIONARY, "Nie można było odczytać zapisu")
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var restored = Campaign.from_dict(parsed)

	_check(restored.side == c.side, "Inna strona po odczycie")
	_check(int(restored.world_seed) == int(c.world_seed), "Inny seed po odczycie")
	_check(int(restored.hours) == int(c.hours), "Inna godzina po odczycie (%d != %d)" % [int(restored.hours), int(c.hours)])
	_check(int(restored.day) == int(c.day), "Inny dzień po odczycie")
	_check(int(restored.food) == int(c.food), "Inna żywność po odczycie")
	_check(int(restored.funds) == int(c.funds), "Inne fundusze po odczycie")
	_check(int(restored.morale) == int(c.morale), "Inne morale po odczycie")
	_check(absf(float(restored.relief) - float(c.relief)) < 0.0001, "Inna ulga (relief) po odczycie")
	_check(restored.position == c.position, "Inna pozycja gracza po odczycie")
	_check(int(restored.rng.state) == int(c.rng.state), "Inny stan generatora po odczycie")

	var tiles_a: PackedByteArray = c.map["tiles"]
	var tiles_b: PackedByteArray = restored.map["tiles"]
	_check(tiles_a == tiles_b, "Mapa po odczycie różni się od zapisanej")
	_check(restored.map["start"] == c.map["start"], "Inne pole startowe po odczycie")
	_check(restored.map["cities"].size() == c.map["cities"].size(), "Inna liczba miast po odczycie")
	var fog_a: PackedByteArray = c.fog.state
	var fog_b: PackedByteArray = restored.fog.state
	_check(fog_a == fog_b, "Mgła wojny po odczycie różni się od zapisanej")

	_check(restored.army.size() == c.army.size(), "Inna liczba jednostek po odczycie")
	_check(restored.enemies.size() == c.enemies.size(), "Inna liczba oddziałów wroga po odczycie")
	_check(restored.objectives.size() == c.objectives.size(), "Inna liczba celów po odczycie")
	_check(restored.boats.size() == c.boats.size(), "Inna liczba łodzi po odczycie")
	_check(restored.captured.size() == c.captured.size(), "Inna liczba zdobytych miast po odczycie")

	for i in range(mini(restored.army.size(), c.army.size())):
		_check(int(restored.army[i]["id"]) == int(c.army[i]["id"]), "Inne id jednostki %d po odczycie" % i)
		_check(str(restored.army[i]["def_id"]) == str(c.army[i]["def_id"]), "Inny typ jednostki %d po odczycie" % i)
	for i in range(mini(restored.enemies.size(), c.enemies.size())):
		_check(int(restored.enemies[i]["id"]) == int(c.enemies[i]["id"]), "Inny id oddziału wroga po odczycie")
		_check(restored.enemies[i]["pos"] == c.enemies[i]["pos"], "Inna pozycja wroga po odczycie")

	_check(restored.scout != null, "Zwiadowca nie został odczytany")
	if restored.scout != null:
		_check(restored.scout["pos"] == c.scout["pos"], "Inna pozycja zwiadowcy po odczycie")
		_check(int(restored.scout["hours_left"]) == int(c.scout["hours_left"]), "Inny czas powrotu zwiadowcy")
	_check(restored.boats[0]["pos"] == c.boats[0]["pos"], "Łodzie po odczycie różnią się od zapisanych")

	_check(restored.pending_battle != null, "Oczekująca bitwa nie została odczytana")
	if restored.pending_battle != null:
		_check(int(restored.pending_battle["id"]) == int(c.pending_battle["id"]), "Oczekująca bitwa wskazuje inny oddział")

	# Po odczycie świat powinien się rozwijać tak samo.
	c.pending_battle = null
	restored.pending_battle = null
	c.world_hour()
	restored.world_hour()
	_check(int(restored.hours) == int(c.hours), "Po odczycie czas płynie inaczej")
	_check(restored.enemies.size() == c.enemies.size(), "Po odczycie liczba wrogów się rozjechała")
	if c.enemies.size() > 0:
		_check(restored.enemies[0]["pos"] == c.enemies[0]["pos"], "Po odczycie wrogowie ruszają się inaczej")


func _test_slot_file() -> void:
	GameState.new_campaign(4242)
	var food_before: int = GameState.campaign.food
	var message: String = GameState.save_slot()
	_check(message == "", "Zapis do slotu zwrócił komunikat: %s" % message)
	_check(FileAccess.file_exists(GameState.SAVE_PATH), "Plik zapisu nie powstał")
	_check(GameState.has_save(), "has_save powinno widzieć zapis")

	GameState.new_campaign(1)
	_check(int(GameState.campaign.world_seed) == 1, "Nowa kampania powinna mieć inny seed")
	var load_message: String = GameState.load_slot()
	_check(load_message == "", "Odczyt ze slotu zwrócił komunikat: %s" % load_message)
	_check(GameState.campaign != null, "Po odczycie brak kampanii")
	if GameState.campaign != null:
		_check(int(GameState.campaign.world_seed) == 4242, "Odczytano kampanię z innym seedem")
		_check(int(GameState.campaign.food) == food_before, "Odczytana kampania ma inną żywność")
	_check(GameState.battle_enemy == null, "Odczyt powinien czyścić oczekującą bitwę")


func _report() -> void:
	if failures.is_empty():
		print("Wszystkie sprawdzenia zapisu przeszły.")
		print("RESULT: PASS")
		quit(0)
		return
	print("Niepowodzenia: %d" % failures.size())
	print("RESULT: FAIL")
	quit(1)
