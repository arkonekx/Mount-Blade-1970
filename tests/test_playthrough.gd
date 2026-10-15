extends SceneTree
## Test integracyjny: cała rozgrywka bez okna graficznego.
##
## Bot prowadzi kampanię tak, jak zrobiłby to gracz: maszeruje do celów, stoi
## w mieście, żeby je utrzymać, a każdą bitwę rozgrywa prawdziwym symulatorem
## (BattleSim) i rozlicza jej wynik przez `apply_battle_outcome`. W trakcie
## kampanii zapisuje i wczytuje stan (F5/F9), żeby sprawdzić, że rozgrywka
## przetrwa zapis.
##
## Uruchomienie:
##   godot --headless --path . -s res://tests/test_playthrough.gd

const BattleSim = preload("res://scripts/battle/battle_sim.gd")
const GameState = preload("res://scripts/game_state.gd")
const Army = preload("res://scripts/logic/army.gd")
const DayNight = preload("res://scripts/logic/daynight.gd")
const Enemy = preload("res://scripts/logic/enemy.gd")

const SEED := 4242
const MAX_HOURS := 24 * 45          # budżet kampanii: 45 dni
const MAX_BATTLES := 40
const MAX_HOURS_PER_OBJECTIVE := 36 # po tylu godzinach bot idzie szukać przeszkody
const BLOCKER_RANGE := 6            # jak blisko celu musi stać wróg, żeby go zaatakować
const MAX_CHASES := 6               # ile razy bot może ruszyć na wroga blokującego cel
const MAX_LOOP_STEPS := 40000
const BATTLE_DT := 1.0 / 30.0
const BATTLE_MAX_STEPS := 21000     # 600 s bitwy przy kroku 1/30 s

var failures: Array = []


func _initialize() -> void:
	print("== test_playthrough ==")
	_play()
	_report()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		print("  BŁĄD: %s" % message)


# --- przebieg kampanii -------------------------------------------------------


func _play() -> void:
	GameState.new_campaign(SEED)
	var c = GameState.campaign
	_check(c != null, "GameState.new_campaign nie ustawiło kampanii")
	if c == null:
		return

	var start_hours: int = int(c.hours)
	var battles: int = 0
	var wins: int = 0
	var losses: int = 0
	var skipped: Array = []
	var chases: int = 0
	var objective: Dictionary = {}
	var objective_start_hours: int = start_hours
	var saved_and_loaded: bool = false
	var last_position: Vector2i = c.position
	var moves: int = 0
	var all_objectives_settled: bool = false

	var steps: int = 0
	while not c.over and int(c.hours) - start_hours < MAX_HOURS and battles < MAX_BATTLES and steps < MAX_LOOP_STEPS:
		steps += 1

		# 1. Kontakt z wrogiem: rozegraj bitwę i rozlicz ją w kampanii.
		if c.pending_battle != null:
			var enemy_name: String = str(c.pending_battle.get("name", "?"))
			var outcome: Dictionary = _resolve_battle(c)
			battles += 1
			if str(outcome.get("result", "")) == "win":
				wins += 1
			elif str(outcome.get("result", "")) == "loss":
				losses += 1
			c.apply_battle_outcome(c.pending_battle, outcome)
			_check(c.pending_battle == null, "Bitwa z %s nie została rozliczona" % enemy_name)
			_check(Army.validate(c.army).is_empty(), "Armia po bitwie łamie limity: %s" % str(Army.validate(c.army)))
			_check(c.morale >= 0 and c.morale <= 100, "Morale po bitwie poza zakresem: %d" % c.morale)
			if c.army.is_empty():
				_check(c.over, "Bez wojska kampania powinna się zakończyć")
			# Zapis i odczyt w trakcie kampanii (klawisze F5/F9).
			if not saved_and_loaded:
				saved_and_loaded = true
				_check(GameState.save_slot() == "", "Zapis kampanii nie udał się")
				var load_error: String = GameState.load_slot()
				_check(load_error == "", "Odczyt kampanii nie udał się: %s" % load_error)
				if load_error == "" and GameState.campaign != null:
					var loaded = GameState.campaign
					_check(loaded.position == c.position, "Po odczycie inne pole gracza")
					_check(int(loaded.hours) == int(c.hours), "Po odczycie inna godzina")
					_check(loaded.army.size() == c.army.size(), "Po odczycie inna liczba jednostek")
					_check(loaded.objectives.size() == c.objectives.size(), "Po odczycie inna liczba celów")
					c = loaded
					objective = {}
			continue

		# 2. Wybór celu, gdy poprzedni zdobyty, porzucony albo przekroczony czas.
		var spent_on_objective: int = int(c.hours) - objective_start_hours
		var need_new_objective: bool = objective.is_empty() or bool(objective.get("owned", false))
		if not need_new_objective:
			need_new_objective = skipped.has(str(objective.get("name", ""))) or spent_on_objective > MAX_HOURS_PER_OBJECTIVE
		if need_new_objective:
			var stalled: bool = not objective.is_empty() and not bool(objective.get("owned", false))
			if stalled:
				# Cel nie daje się utrzymać? Sprawdź, czy blokuje go oddział wroga —
				# gracz zrobiłby to samo: najpierw bitwa, potem utrzymanie miasta.
				var blocker: Vector2i = _blocker_near(c, objective)
				if blocker != Vector2i(-1, -1) and chases < MAX_CHASES:
					var chase_message: String = c.start_move(blocker)
					if chase_message == "":
						chases += 1
						objective_start_hours = int(c.hours)
						print("  pościg %d za wrogiem przy %s (godzina %d)" % [chases, str(objective["name"]), int(c.hours)])
						continue
				skipped.append(str(objective["name"]))
				print("  cel %s porzucony po %d godzinach" % [str(objective["name"]), spent_on_objective])
			objective = _next_objective(c, skipped)
			objective_start_hours = int(c.hours)
			if objective.is_empty():
				all_objectives_settled = true
				break
			var start_target := Vector2i(int(objective["x"]), int(objective["y"]))
			var start_message: String = c.start_move(start_target)
			if start_message != "":
				print("  cel %s nieosiągalny: %s" % [str(objective["name"]), start_message])
				skipped.append(str(objective["name"]))
				objective = {}
				continue

		var target := Vector2i(int(objective["x"]), int(objective["y"]))
		if c.position == target:
			# Stanie w mieście bez wroga w promieniu = utrzymywanie celu.
			c.world_hour()
		elif c.path.size() > 0:
			c.player_step()
		else:
			# Trasa się skończyła, a nie ma nas na miejscu — spróbuj jeszcze raz.
			var retry: String = c.start_move(target)
			if retry != "":
				skipped.append(str(objective["name"]))
				objective = {}

		if c.position != last_position:
			moves += 1
			last_position = c.position

	# --- podsumowanie i spójność stanu końcowego ---
	var owned: int = 0
	for obj in c.objectives:
		if bool(obj["owned"]):
			owned += 1
		var hold: float = float(obj["hold"])
		_check(hold >= 0.0 and hold <= 12.0, "Cel %s ma nieprawidłowy licznik utrzymania: %f" % [str(obj["name"]), hold])
	_check(Army.validate(c.army).is_empty(), "Armia na końcu kampanii łamie limity: %s" % str(Army.validate(c.army)))
	_check(c.food >= 0, "Żywność poniżej zera: %d" % c.food)
	_check(c.funds >= 0, "Fundusze poniżej zera: %d" % c.funds)
	_check(c.morale >= 0 and c.morale <= 100, "Morale poza zakresem: %d" % c.morale)
	_check(moves > 0, "Bot nie ruszył się z miejsca przez całą kampanię")
	_check(saved_and_loaded, "Kampania zakończyła się bez ani jednej bitwy — nie było okazji sprawdzić zapisu")
	if c.victory:
		_check(c.over, "Zwycięstwo bez zakończenia kampanii")
		_check(owned == c.objectives.size(), "Zwycięstwo bez zdobycia wszystkich celów (%d/%d)" % [owned, c.objectives.size()])

	print("  dni: %d, godziny: %d, kroki: %d" % [int(c.day), int(c.hours) - start_hours, steps])
	print("  bitwy: %d (wygrane %d, przegrane %d), cele: %d/%d" % [battles, wins, losses, owned, c.objectives.size()])
	print("  wojsko: %d, morale: %d, żywność: %d, fundusze: %d" % [c.army.size(), c.morale, c.food, c.funds])
	if c.over:
		print("  koniec kampanii: %s" % ("zwycięstwo" if c.victory else "porażka"))
	else:
		print("  kampania trwa (wyczerpany budżet testu)")
	_check(battles >= 1, "W 45 dni kampanii nie doszło do ani jednej bitwy")
	var hours_used: int = int(c.hours) - start_hours
	_check(c.over or battles >= MAX_BATTLES or hours_used >= MAX_HOURS or all_objectives_settled,
		"Pętla kampanii zakończyła się bez powodu (krok %d)" % steps)


## Pole najbliższego wroga stojącego przy celu (albo (-1, -1), gdy nikogo nie ma).
## Taki oddział blokuje zdobycie celu, bo walka w promieniu 3 pól zeruje licznik.
func _blocker_near(c, objective: Dictionary) -> Vector2i:
	var obj_pos := Vector2i(int(objective["x"]), int(objective["y"]))
	var best := Vector2i(-1, -1)
	var best_distance: int = BLOCKER_RANGE + 1
	for enemy in c.enemies:
		var distance: int = Enemy.chebyshev(enemy["pos"], obj_pos)
		if distance < best_distance:
			best_distance = distance
			best = enemy["pos"]
	if best_distance <= BLOCKER_RANGE:
		return best
	return Vector2i(-1, -1)


func _next_objective(c, skipped: Array) -> Dictionary:
	for obj in c.objectives:
		if bool(obj["owned"]):
			continue
		if skipped.has(str(obj["name"])):
			continue
		return obj
	return {}


# --- bitwa -------------------------------------------------------------------


## Rozgrywa bitwę tak jak widok bitwy: gracz podchodzi i strzela do najbliższego
## wroga (celuje w niego `player_fire`), towarzysze walczą sami.
func _resolve_battle(c) -> Dictionary:
	var enemy: Dictionary = c.pending_battle
	var enemy_pos: Vector2i = enemy["pos"]
	var sim = BattleSim.new(
		c.army,
		enemy["units"],
		{"skill": int(enemy["skill"]), "personality": str(enemy["personality"])},
		GameState.terrain_name_at(c, enemy_pos),
		int(c.world_seed) * 31 + int(enemy["id"]),
		DayNight.is_night(int(c.hours))
	)
	_check(sim.player_unit() != null, "Symulacja bitwy nie ma jednostki gracza")
	var steps: int = 0
	while sim.result == "" and steps < BATTLE_MAX_STEPS:
		steps += 1
		var spacing: float = sim.distance_to_nearest_enemy()
		var forward: float = 1.0 if spacing > 240.0 else 0.0
		sim.player_input(BATTLE_DT, forward, 0.0)
		sim.player_fire()
		sim.update(BATTLE_DT)
	_check(sim.result != "", "Bitwa nie rozstrzygnęła się w ciągu 600 s")
	var outcome: Dictionary = sim.outcome()
	_check(outcome.has("result") and outcome.has("player_survivors"), "Wynik bitwy nie ma wymaganych pól")
	return outcome


func _report() -> void:
	if failures.is_empty():
		print("Cała rozgrywka przeszła bez błędów.")
		print("RESULT: PASS")
		quit(0)
		return
	print("Niepowodzenia: %d" % failures.size())
	print("RESULT: FAIL")
	quit(1)
