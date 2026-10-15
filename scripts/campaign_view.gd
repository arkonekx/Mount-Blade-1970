extends Node2D
## Widok kampanii: mapa 2D, mgła wojny, HUD i dziennik.
##
## Klawisze: LPM marsz, PPM zwiadowca, T czekaj 1 h, S stop, J żywność,
## K rekrutacja, R odpoczynek (w mieście), F przeprawa łodzią, B most,
## F5/F9 zapis/odczyt, N nowa kampania.

const Campaign = preload("res://scripts/logic/campaign.gd")
const Terrain = preload("res://scripts/logic/terrain.gd")
const Pathfind = preload("res://scripts/logic/pathfind.gd")
const Fog = preload("res://scripts/logic/fog.gd")
const UnitsData = preload("res://scripts/logic/units_data.gd")
const GameState = preload("res://scripts/game_state.gd")
const GameTextures = preload("res://scripts/logic/game_textures.gd")

const TILE := 16.0
const MAP_ORIGIN := Vector2(14.0, 48.0)
const MAP_PIXEL_W := 960.0
const MAP_PIXEL_H := 640.0
const PANEL_X := 986.0
const PANEL_W := 280.0

const STEP_SECONDS := 0.25
const WAIT_SECONDS := 0.35
const MESSAGE_SECONDS := 5.0

const COLORS: Dictionary = {
	Terrain.Kind.PLAINS: Color(0.42, 0.55, 0.31),
	Terrain.Kind.FOREST: Color(0.18, 0.36, 0.20),
	Terrain.Kind.HILLS: Color(0.52, 0.45, 0.32),
	Terrain.Kind.MOUNTAIN: Color(0.42, 0.40, 0.38),
	Terrain.Kind.MARSH: Color(0.30, 0.40, 0.34),
	Terrain.Kind.RIVER: Color(0.20, 0.38, 0.62),
	Terrain.Kind.FORD: Color(0.40, 0.60, 0.78),
	Terrain.Kind.LAKE: Color(0.16, 0.28, 0.50),
	Terrain.Kind.CITY: Color(0.72, 0.66, 0.55),
	Terrain.Kind.ROAD: Color(0.62, 0.56, 0.42),
	Terrain.Kind.BRIDGE: Color(0.70, 0.58, 0.38),
	Terrain.Kind.SAND: Color(0.80, 0.74, 0.52),
	Terrain.Kind.SNOW: Color(0.92, 0.94, 0.97),
}

var campaign
var hud: CanvasLayer
var status_label: Label
var journal_label: Label
var objectives_label: Label
var help_label: Label
var message_label: Label
var title_label: Label

var _step_accum: float = 0.0
var _wait_accum: float = 0.0
var _waiting: bool = false
var _switching: bool = false
var _message: String = ""
var _message_timer: float = 0.0


func _ready() -> void:
	if GameState.campaign == null:
		GameState.new_campaign()
	campaign = GameState.campaign
	if GameState.last_outcome != null:
		_set_message(GameState.outcome_text(), 12.0)
	_build_hud()
	queue_redraw()


func _build_hud() -> void:
	hud = CanvasLayer.new()
	add_child(hud)

	var background := ColorRect.new()
	background.color = Color(0.06, 0.07, 0.09)
	background.position = Vector2.ZERO
	background.size = Vector2(1280, 44)
	hud.add_child(background)

	title_label = Label.new()
	title_label.text = "ZIMNA WOJNA 1975 — kampania USA"
	title_label.position = Vector2(PANEL_X, 6)
	title_label.size = Vector2(PANEL_W, 22)
	title_label.add_theme_font_size_override("font_size", 13)
	hud.add_child(title_label)

	status_label = Label.new()
	status_label.position = Vector2(12, 8)
	status_label.size = Vector2(960, 30)
	status_label.add_theme_font_size_override("font_size", 15)
	hud.add_child(status_label)

	objectives_label = Label.new()
	objectives_label.position = Vector2(PANEL_X, 46)
	objectives_label.size = Vector2(PANEL_W, 110)
	objectives_label.add_theme_font_size_override("font_size", 13)
	hud.add_child(objectives_label)

	journal_label = Label.new()
	journal_label.position = Vector2(PANEL_X, 180)
	journal_label.size = Vector2(PANEL_W, 320)
	journal_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	journal_label.add_theme_font_size_override("font_size", 12)
	hud.add_child(journal_label)

	help_label = Label.new()
	help_label.position = Vector2(PANEL_X, 520)
	help_label.size = Vector2(PANEL_W, 200)
	help_label.add_theme_font_size_override("font_size", 12)
	help_label.text = _join_lines([
		"Sterowanie",
		"LPM — marsz, PPM — zwiadowca",
		"T — czekaj 1 h, S — stop",
		"J — żywność (+50 za 20), K — rekrutacja",
		"R — odpoczynek (w mieście)",
		"F — przeprawa łodzią, B — most",
		"F5 — zapis, F9 — odczyt, N — nowa",
	])
	hud.add_child(help_label)

	message_label = Label.new()
	message_label.position = Vector2(12, 692)
	message_label.size = Vector2(1260, 24)
	message_label.add_theme_font_size_override("font_size", 14)
	hud.add_child(message_label)


func _process(delta: float) -> void:
	if campaign == null:
		return
	if _switching:
		return
	if campaign.pending_battle != null and not campaign.over:
		_go_to_battle()
		return
	if not campaign.over:
		_advance_time(delta)
	if _message_timer > 0.0:
		_message_timer -= delta
		if _message_timer <= 0.0:
			_message = ""
	_update_hud()
	queue_redraw()


func _advance_time(delta: float) -> void:
	if campaign.over:
		return
	if campaign.path.size() > 0:
		_step_accum += delta
		while _step_accum >= STEP_SECONDS and campaign.path.size() > 0:
			_step_accum -= STEP_SECONDS
			campaign.player_step()
			if campaign.pending_battle != null:
				break
	else:
		_step_accum = 0.0
		if _waiting:
			_wait_accum += delta
			while _wait_accum >= WAIT_SECONDS:
				_wait_accum -= WAIT_SECONDS
				campaign.world_hour()
				if campaign.pending_battle != null:
					break


func _go_to_battle() -> void:
	_switching = true
	GameState.campaign = campaign
	GameState.battle_enemy = campaign.pending_battle
	get_tree().change_scene_to_file("res://scenes/battle.tscn")


# --- HUD ---------------------------------------------------------------------


func _update_hud() -> void:
	status_label.text = campaign.status_text() + "  |  teren: %s" % campaign.terrain_here()
	var objectives: Array = ["Cele (3 miasta, 12 h):"]
	for line in campaign.objective_texts():
		objectives.append(" • " + str(line))
	objectives.append("")
	objectives.append("Zbadane: %d%%   Wojsko: %s" % [
		int(round(campaign.fog.known_fraction() * 100.0)),
		_join_names(_army_names()),
	])
	if campaign.scout != null:
		objectives.append("Zwiadowca w drodze (jeszcze %d h)." % int(campaign.scout["hours_left"]))
	if campaign.can_build_bridge():
		objectives.append("Masz pojazd inżynieryjny — B stawia most.")
	objectives_label.text = _join_lines(objectives)

	journal_label.text = "Dziennik\n" + _join_lines(campaign.last_news(6))

	if campaign.over:
		message_label.text = "ZWYCIĘSTWO! Wszystkie cele zdobyte." if campaign.victory else "Koniec kampanii — brak wojska."
	else:
		message_label.text = _message


## Łączenie linii bez polegania na konwersji Array → PackedStringArray.
func _join_lines(items: Array) -> String:
	var text: String = ""
	for item in items:
		if text != "":
			text += "\n"
		text += str(item)
	return text


func _join_names(items: Array) -> String:
	var text: String = ""
	for item in items:
		if text != "":
			text += " / "
		text += str(item)
	return text


func _army_names() -> Array:
	var names: Array = []
	for unit in campaign.army:
		names.append(str(unit["name"]))
	if names.is_empty():
		names.append("brak")
	return names


func _set_message(text: String, seconds: float = MESSAGE_SECONDS) -> void:
	_message = text
	_message_timer = seconds


# --- rysowanie mapy ----------------------------------------------------------


func _draw() -> void:
	if campaign == null:
		return
	var w: int = int(campaign.map["w"])
	var h: int = int(campaign.map["h"])
	var tiles: PackedByteArray = campaign.map["tiles"]

	for y in range(h):
		for x in range(w):
			var kind: int = tiles[y * w + x]
			var color: Color = COLORS.get(kind, Color.MAGENTA)
			var state: int = campaign.fog.get_state(x, y)
			if state == Fog.UNKNOWN:
				continue
			# Kafel terenu, a gdy tekstury brak — zapasowy kolor z COLORS.
			# Mgła przygasza kafel tak samo, jak wcześniej przygaszała kolor.
			var tint := Color(1, 1, 1)
			if state == Fog.EXPLORED:
				color = color.darkened(0.45)
				tint = Color(0.55, 0.55, 0.55)
			var rect := Rect2(MAP_ORIGIN + Vector2(x, y) * TILE, Vector2(TILE, TILE))
			var texture: Texture2D = GameTextures.tile(kind)
			if texture != null:
				draw_texture_rect(texture, rect, false, tint)
			else:
				draw_rect(rect, color)

	_draw_cities()
	_draw_objectives()
	_draw_boats()
	_draw_marks()
	_draw_path()
	_draw_enemies()
	_draw_scout()
	_draw_player()
	_draw_frame()


## Rysuje ikonę AI wyśrodkowaną na polu mapy. Zwraca false, gdy tekstury brak
## (wtedy wołający rysuje zapasowy kształt).
func _draw_icon(key: String, cell: Vector2i, size: float, tint: Color = Color(1, 1, 1)) -> bool:
	var texture: Texture2D = GameTextures.icon(key)
	if texture == null:
		return false
	var center: Vector2 = MAP_ORIGIN + Vector2(cell) * TILE + Vector2(TILE * 0.5, TILE * 0.5)
	var rect := Rect2(center - Vector2(size, size) * 0.5, Vector2(size, size))
	draw_texture_rect(texture, rect, false, tint)
	return true


func _draw_frame() -> void:
	draw_rect(Rect2(MAP_ORIGIN - Vector2(2, 2), Vector2(MAP_PIXEL_W + 4, MAP_PIXEL_H + 4)), Color(0.10, 0.11, 0.13), false, 2.0)


func _draw_cities() -> void:
	var font: Font = ThemeDB.fallback_font
	for city in campaign.map["cities"]:
		var p := Vector2i(int(city["x"]), int(city["y"]))
		if not campaign.fog.is_known(p.x, p.y):
			continue
		var pos: Vector2 = MAP_ORIGIN + Vector2(p) * TILE
		if not _draw_icon("city", p, TILE + 6.0):
			draw_rect(Rect2(pos + Vector2(3, 3), Vector2(TILE - 6, TILE - 6)), Color(0.95, 0.92, 0.80))
		if campaign.fog.is_visible(p.x, p.y):
			draw_string(font, pos + Vector2(4, -3), str(city["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.95, 0.95, 0.90))


func _draw_objectives() -> void:
	var font: Font = ThemeDB.fallback_font
	for obj in campaign.objectives:
		var p := Vector2i(int(obj["x"]), int(obj["y"]))
		var pos: Vector2 = MAP_ORIGIN + Vector2(p) * TILE + Vector2(TILE * 0.5, TILE * 0.5)
		var color: Color = Color(0.95, 0.80, 0.20) if not bool(obj["owned"]) else Color(0.30, 0.95, 0.40)
		if not _draw_icon("objective", p, TILE + 2.0, Color(1, 1, 1, 0.55 if bool(obj["owned"]) else 1.0)):
			draw_arc(pos, TILE * 0.62, 0.0, TAU, 20, color, 2.0)
		draw_arc(pos, TILE * 0.62, 0.0, TAU, 20, color, 2.0)
		if not bool(obj["owned"]):
			draw_string(font, pos + Vector2(6, 4), "%d/%d" % [int(obj["hold"]), int(Campaign.OBJECTIVE_HOLD_HOURS)], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.85))


func _draw_boats() -> void:
	for boat in campaign.boats:
		var p: Vector2i = boat["pos"]
		if not campaign.fog.is_known(p.x, p.y):
			continue
		if _draw_icon("boat", p, TILE - 1.0):
			continue
		var pos: Vector2 = MAP_ORIGIN + Vector2(p) * TILE + Vector2(TILE * 0.5, TILE * 0.5)
		draw_circle(pos, 3.5, Color(0.55, 0.85, 0.95))


func _draw_marks() -> void:
	var font: Font = ThemeDB.fallback_font
	for mark in campaign.marks:
		var p := Vector2i(int(mark["x"]), int(mark["y"]))
		var pos: Vector2 = MAP_ORIGIN + Vector2(p) * TILE + Vector2(TILE * 0.5, TILE * 0.5)
		draw_line(pos - Vector2(4, 4), pos + Vector2(4, 4), Color(0.95, 0.55, 0.15), 2.0)
		draw_line(pos + Vector2(-4, 4), pos + Vector2(4, -4), Color(0.95, 0.55, 0.15), 2.0)
		draw_string(font, pos + Vector2(6, -4), "d%d" % int(mark["day"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.95, 0.75, 0.35))


func _draw_path() -> void:
	for step in campaign.path:
		var pos: Vector2 = MAP_ORIGIN + Vector2(step) * TILE + Vector2(TILE * 0.5, TILE * 0.5)
		draw_circle(pos, 2.0, Color(0.95, 0.95, 0.35, 0.75))


func _draw_enemies() -> void:
	for enemy in campaign.visible_enemies():
		var p: Vector2i = enemy["pos"]
		if _draw_icon("enemy", p, TILE + 4.0):
			continue
		var pos: Vector2 = MAP_ORIGIN + Vector2(p) * TILE
		draw_rect(Rect2(pos + Vector2(4, 4), Vector2(TILE - 8, TILE - 8)), Color(0.85, 0.22, 0.20))


func _draw_scout() -> void:
	if campaign.scout == null:
		return
	var p: Vector2i = campaign.scout["pos"]
	var pos: Vector2 = MAP_ORIGIN + Vector2(p) * TILE + Vector2(TILE * 0.5, TILE * 0.5)
	if not _draw_icon("scout", p, TILE + 2.0):
		draw_circle(pos, 3.0, Color(0.95, 0.95, 0.95))
	draw_arc(pos, 6.0, 0.0, TAU, 16, Color(0.95, 0.95, 0.95, 0.6), 1.0)


func _draw_player() -> void:
	var pos: Vector2 = MAP_ORIGIN + Vector2(campaign.position) * TILE + Vector2(TILE * 0.5, TILE * 0.5)
	if not _draw_icon("player", campaign.position, TILE + 8.0):
		var points := PackedVector2Array([
			pos + Vector2(0, -8), pos + Vector2(7, 7), pos + Vector2(0, 3), pos + Vector2(-7, 7),
		])
		draw_colored_polygon(points, Color(0.25, 0.95, 0.40))
	draw_rect(Rect2(MAP_ORIGIN + Vector2(campaign.position) * TILE, Vector2(TILE, TILE)), Color(1, 1, 1, 0.35), false, 1.0)


# --- obsługa wejścia ---------------------------------------------------------


func _unhandled_input(event: InputEvent) -> void:
	if campaign == null or _switching:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		_handle_key(event.keycode)
		return
	if event is InputEventMouseButton and event.pressed:
		var tile: Vector2i = _screen_to_tile(get_global_mouse_position())
		if not Pathfind.in_bounds(campaign.map, tile):
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			var message: String = campaign.start_move(tile)
			_set_message(message if message != "" else "Marsz: %d pól." % campaign.path.size())
			_waiting = false
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			var scout_message: String = campaign.dispatch_scout(tile)
			_set_message(scout_message if scout_message != "" else "Zwiadowca wysłany.")


func _handle_key(keycode: int) -> void:
	match keycode:
		KEY_T:
			_waiting = not _waiting
			_set_message("Czekam…" if _waiting else "Koniec czekania.")
		KEY_S:
			campaign.stop_move()
			_waiting = false
			_set_message("Marsz zatrzymany.")
		KEY_J:
			_set_message(_report(campaign.buy_food(), "Kupiono żywność (+50)."))
		KEY_K:
			_set_message(_report(campaign.recruit_infantry(), "Zrekrutowano piechotę."))
		KEY_R:
			_set_message(_report(campaign.rest(), "Odpoczynek."))
		KEY_F:
			_set_message(_report(campaign.ferry_cross(), "Przeprawa łodzią."))
		KEY_B:
			_set_message(_report(campaign.build_bridge_at(), "Most zbudowany."))
		KEY_F5:
			var save_message: String = GameState.save_slot()
			_set_message(save_message if save_message != "" else "Zapisano stan kampanii.")
		KEY_F9:
			var load_message: String = GameState.load_slot()
			if load_message == "":
				campaign = GameState.campaign
				_set_message("Odczytano zapis.")
			else:
				_set_message(load_message)
		KEY_N:
			GameState.new_campaign()
			campaign = GameState.campaign
			_set_message("Nowa kampania (seed %d)." % int(campaign.world_seed))


func _report(message: String, success: String) -> String:
	return message if message != "" else success


func _screen_to_tile(pos: Vector2) -> Vector2i:
	var local: Vector2 = (pos - MAP_ORIGIN) / TILE
	return Vector2i(int(floor(local.x)), int(floor(local.y)))
