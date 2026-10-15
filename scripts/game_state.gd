extends RefCounted
## Stan gry przenoszony między scenami kampanii i bitwy.
##
## Wszystkie pola są statyczne, więc widok bitwy widzi tę samą kampanię,
## którą zostawił widok mapy. Skrypty odwołują się do tego pliku przez
## `const GameState = preload("res://scripts/game_state.gd")`.

const Campaign = preload("res://scripts/logic/campaign.gd")
const Pathfind = preload("res://scripts/logic/pathfind.gd")
const Terrain = preload("res://scripts/logic/terrain.gd")
const Enemy = preload("res://scripts/logic/enemy.gd")
const RNG = preload("res://scripts/logic/rng.gd")

const SAVE_PATH := "user://zimna_wojna_slot1.json"
const DEMO_SEED := 20251015

## Bieżąca kampania (albo null).
static var campaign = null
## Oddział wroga, z którym gracz właśnie się zetknął (albo null).
static var battle_enemy = null
## Wynik ostatniej bitwy — czytany przez widok kampanii po powrocie.
static var last_outcome = null


## Rodzaj terenu pod polem mapy: "city", "forest", "hills" albo "plains".
static func terrain_kind_at(c, p: Vector2i) -> String:
	if c == null:
		return "plains"
	var city: Dictionary = Pathfind.city_at(c.map, p)
	if not city.is_empty():
		return "city"
	var kind: int = Pathfind.terrain_at(c.map, p)
	if kind == Terrain.Kind.FOREST:
		return "forest"
	if kind == Terrain.Kind.HILLS or kind == Terrain.Kind.MOUNTAIN:
		return "hills"
	return "plains"


## Nazwa terenu po polsku (np. "las") — dla interfejsu i symulacji bitwy.
static func terrain_name_at(c, p: Vector2i) -> String:
	if c == null:
		return "równina"
	return Terrain.terrain_name(Pathfind.terrain_at(c.map, p))


## Zakłada kampanię demonstracyjną, gdy bitwa startuje bez kampanii.
static func ensure_demo() -> void:
	if campaign == null:
		campaign = Campaign.new("us", DEMO_SEED)
	if battle_enemy == null:
		var camp = campaign
		var spot: Vector2i = camp.position
		var enemy: Dictionary = Enemy.create(9001, camp.enemy_side(), camp.rng, 4, 1.0, spot, false)
		enemy["name"] = "Oddział demonstracyjny"
		camp.enemies.append(enemy)
		battle_enemy = enemy


## Nowa kampania (klawisz N albo brak zapisu).
static func new_campaign(seed_value: int = -1) -> void:
	var used_seed: int = seed_value
	if used_seed < 0:
		used_seed = randi() % 1000000 + 1
	campaign = Campaign.new("us", used_seed)
	battle_enemy = null
	last_outcome = null


static func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


## Zapis stanu kampanii do jedynego slotu. Zwraca "" albo komunikat błędu.
static func save_slot() -> String:
	if campaign == null:
		return "Brak kampanii do zapisania."
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return "Nie udało się zapisać: %s" % error_string(FileAccess.get_open_error())
	file.store_string(JSON.stringify(campaign.to_dict()))
	file.close()
	return ""


## Odczyt stanu kampanii. Zwraca "" albo komunikat błędu.
static func load_slot() -> String:
	if not FileAccess.file_exists(SAVE_PATH):
		return "Brak zapisu."
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return "Nie udało się odczytać zapisu: %s" % error_string(FileAccess.get_open_error())
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return "Uszkodzony zapis."
	campaign = Campaign.from_dict(parsed)
	battle_enemy = null
	last_outcome = null
	return ""


## Tekst wyniku bitwy do pokazania na mapie (albo "").
static func outcome_text() -> String:
	if last_outcome == null:
		return ""
	var out: Dictionary = last_outcome
	var names: Dictionary = {
		"win": "zwycięstwo",
		"loss": "porażka",
		"retreat": "odwrót",
		"stalemate": "bez rozstrzygnięcia",
	}
	var result: String = str(out.get("result", "stalemate"))
	return "Wynik bitwy: %s (ocalało %d, wróg: %d)" % [
		str(names.get(result, result)),
		(out.get("player_survivors", []) as Array).size(),
		(out.get("enemy_survivors", []) as Array).size(),
	]
