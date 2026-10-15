extends Node3D
## Widok bitwy FPS: pole 1000 × 400 m, kamera pierwszej osoby, prymitywy 3D.
##
## Klawisze: WSAD/strzałki — ruch, mysz — obrót, LPM/Spacja — ognia,
## E — wsiadanie/wysiadanie, R — odwrót (x < 40 m), Esc — pauza, Enter — powrót.

const BattleSim = preload("res://scripts/battle/battle_sim.gd")
const GameState = preload("res://scripts/game_state.gd")
const UnitsData = preload("res://scripts/logic/units_data.gd")
const DayNight = preload("res://scripts/logic/daynight.gd")

const MOUSE_SENSITIVITY := 0.0015
const RESULT_DELAY := 1.5
const MAX_MESSAGES := 4

const COLOR_PLAYER := Color(0.25, 0.90, 0.35)
const COLOR_FRIEND := Color(0.25, 0.45, 0.90)
const COLOR_ENEMY := Color(0.85, 0.20, 0.20)
const COLOR_TRUNK := Color(0.30, 0.22, 0.14)
const COLOR_CANOPY := Color(0.16, 0.42, 0.20)
const COLOR_ROCK := Color(0.45, 0.42, 0.38)

var sim
var campaign
var camera: Camera3D
var hud: CanvasLayer
var status_label: Label
var log_label: Label
var hint_label: Label
var overlay: ColorRect
var overlay_label: Label
var crosshair_h: ColorRect
var crosshair_v: ColorRect

var unit_nodes: Array = []
var messages: Array = []
var paused: bool = false
var finished: bool = false
var finish_timer: float = 0.0
var last_sim_message: String = ""


func _ready() -> void:
	GameState.ensure_demo()
	campaign = GameState.campaign
	var enemy: Dictionary = GameState.battle_enemy
	var enemy_pos: Vector2i = enemy["pos"]
	var terrain_kind: String = GameState.terrain_kind_at(campaign, enemy_pos)
	var terrain_name: String = GameState.terrain_name_at(campaign, enemy_pos)
	var is_night: bool = DayNight.is_night(int(campaign.hours))
	sim = BattleSim.new(
		campaign.army,
		enemy["units"],
		{"skill": int(enemy["skill"]), "personality": str(enemy["personality"])},
		terrain_name,
		int(campaign.world_seed) * 31 + int(enemy["id"]),
		is_night
	)
	_build_world(terrain_kind, is_night)
	_build_units()
	_build_hud(terrain_name, is_night)
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_add_message("Bitwa pod %s (%s)." % ["terenie", terrain_name])


# --- świat 3D ----------------------------------------------------------------


func _build_world(terrain_kind: String, is_night: bool) -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.10, 0.12, 0.18) if is_night else Color(0.55, 0.70, 0.90)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.35, 0.40, 0.55) if is_night else Color(0.70, 0.72, 0.78)
	environment.ambient_light_energy = 0.5 if is_night else 0.9
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-55.0), deg_to_rad(35.0), 0.0)
	sun.light_energy = 0.35 if is_night else 1.1
	sun.light_color = Color(0.70, 0.78, 1.0) if is_night else Color(1.0, 0.96, 0.88)
	add_child(sun)

	# Grunt + linia odwrotu
	_add_box(Vector3(BattleSim.FIELD_W, 1.0, BattleSim.FIELD_H), _ground_color(terrain_kind), Vector3(BattleSim.FIELD_W * 0.5, -0.5, BattleSim.FIELD_H * 0.5))
	_add_box(Vector3(0.6, 0.12, BattleSim.FIELD_H), Color(0.95, 0.95, 0.95, 0.85), Vector3(40.0, 0.06, BattleSim.FIELD_H * 0.5))

	for obstacle in sim.obstacles:
		var pos := Vector3(float(obstacle["x"]), 0.0, float(obstacle["z"]))
		var radius: float = float(obstacle["r"])
		if terrain_kind == "forest":
			_add_cylinder(radius * 0.35, radius * 0.35, 4.0, COLOR_TRUNK, pos + Vector3(0, 2.0, 0))
			_add_sphere(radius, COLOR_CANOPY, pos + Vector3(0, 4.0, 0))
		elif terrain_kind == "hills":
			_add_sphere(radius, COLOR_ROCK, pos + Vector3(0, radius * 0.4, 0))
		else:
			_add_box(Vector3(radius, 1.2, radius), COLOR_ROCK, pos + Vector3(0, 0.6, 0))

	if terrain_kind == "city":
		for i in range(6):
			var x: float = 430.0 + float(i % 3) * 22.0
			var z: float = 160.0 + float(i / 3) * 40.0
			_add_box(Vector3(14.0, 9.0, 14.0), Color(0.62, 0.58, 0.52), Vector3(x, 4.5, z))

	camera = Camera3D.new()
	camera.current = true
	add_child(camera)


func _ground_color(terrain_kind: String) -> Color:
	match terrain_kind:
		"forest":
			return Color(0.16, 0.32, 0.18)
		"hills":
			return Color(0.44, 0.38, 0.26)
		"city":
			return Color(0.42, 0.41, 0.39)
		_:
			return Color(0.34, 0.48, 0.26)


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	return material


func _add_box(size: Vector3, color: Color, pos: Vector3) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _material(color)
	node.position = pos
	add_child(node)
	return node


func _add_cylinder(top: float, bottom: float, height: float, color: Color, pos: Vector3) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _material(color)
	node.position = pos
	add_child(node)
	return node


func _add_sphere(radius: float, color: Color, pos: Vector3) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _material(color)
	node.position = pos
	add_child(node)
	return node


func _build_units() -> void:
	unit_nodes = []
	for unit in sim.units:
		var cls: String = str(unit["cls"])
		var is_player: bool = bool(unit["is_player"])
		var color: Color = COLOR_PLAYER if is_player else (COLOR_FRIEND if bool(unit["side"]) else COLOR_ENEMY)
		var node := Node3D.new()
		node.name = "unit_%d" % unit_nodes.size()
		add_child(node)
		if cls == UnitsData.CLS_INFANTRY:
			var body := CapsuleMesh.new()
			body.radius = 0.4
			body.height = 1.7
			var body_node := MeshInstance3D.new()
			body_node.mesh = body
			body_node.material_override = _material(color)
			body_node.position = Vector3(0, 0.85, 0)
			node.add_child(body_node)
			var rifle := BoxMesh.new()
			rifle.size = Vector3(1.1, 0.12, 0.12)
			var rifle_node := MeshInstance3D.new()
			rifle_node.mesh = rifle
			rifle_node.material_override = _material(Color(0.15, 0.15, 0.15))
			rifle_node.position = Vector3(0.5, 1.30, 0)
			node.add_child(rifle_node)
		elif cls == UnitsData.CLS_MECH:
			var hull := BoxMesh.new()
			hull.size = Vector3(6.0, 1.9, 2.6)
			var hull_node := MeshInstance3D.new()
			hull_node.mesh = hull
			hull_node.material_override = _material(color)
			hull_node.position = Vector3(0, 1.0, 0)
			node.add_child(hull_node)
		else:
			var hull := BoxMesh.new()
			hull.size = Vector3(7.0, 2.0, 3.2)
			var hull_node := MeshInstance3D.new()
			hull_node.mesh = hull
			hull_node.material_override = _material(color)
			hull_node.position = Vector3(0, 1.1, 0)
			node.add_child(hull_node)
			var turret := CylinderMesh.new()
			turret.top_radius = 1.1
			turret.bottom_radius = 1.3
			turret.height = 0.7
			var turret_node := MeshInstance3D.new()
			turret_node.mesh = turret
			turret_node.material_override = _material(color.darkened(0.2))
			turret_node.position = Vector3(0.2, 2.4, 0)
			node.add_child(turret_node)
		unit_nodes.append(node)


# --- HUD ---------------------------------------------------------------------


func _build_hud(terrain_name: String, is_night: bool) -> void:
	hud = CanvasLayer.new()
	add_child(hud)

	crosshair_h = ColorRect.new()
	crosshair_h.color = Color(1, 1, 1, 0.75)
	crosshair_h.position = Vector2(640 - 9, 360)
	crosshair_h.size = Vector2(18, 2)
	hud.add_child(crosshair_h)

	crosshair_v = ColorRect.new()
	crosshair_v.color = Color(1, 1, 1, 0.75)
	crosshair_v.position = Vector2(640, 360 - 9)
	crosshair_v.size = Vector2(2, 18)
	hud.add_child(crosshair_v)

	status_label = Label.new()
	status_label.position = Vector2(12, 8)
	status_label.size = Vector2(900, 24)
	status_label.add_theme_font_size_override("font_size", 15)
	hud.add_child(status_label)

	log_label = Label.new()
	log_label.position = Vector2(12, 620)
	log_label.size = Vector2(900, 90)
	log_label.add_theme_font_size_override("font_size", 13)
	hud.add_child(log_label)

	hint_label = Label.new()
	hint_label.position = Vector2(12, 578)
	hint_label.size = Vector2(1260, 34)
	hint_label.add_theme_font_size_override("font_size", 12)
	hint_label.text = "WSAD — ruch, mysz — obrót, LPM/Spacja — ognia, E — pojazd, R — odwrót (x < 40 m), Esc — pauza\nTeren: %s%s" % [terrain_name, ", noc" if is_night else ""]
	hud.add_child(hint_label)

	overlay = ColorRect.new()
	overlay.color = Color(0.0, 0.0, 0.0, 0.55)
	overlay.position = Vector2(340, 280)
	overlay.size = Vector2(600, 120)
	overlay.visible = false
	hud.add_child(overlay)

	overlay_label = Label.new()
	overlay_label.position = Vector2(360, 300)
	overlay_label.size = Vector2(560, 80)
	overlay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay_label.add_theme_font_size_override("font_size", 17)
	overlay_label.visible = false
	hud.add_child(overlay_label)


func _join_lines(items: Array) -> String:
	var text: String = ""
	for item in items:
		if text != "":
			text += "\n"
		text += str(item)
	return text


func _add_message(text: String) -> void:
	if text == "":
		return
	messages.append(text)
	while messages.size() > MAX_MESSAGES:
		messages.remove_at(0)


# --- pętla -------------------------------------------------------------------


func _process(delta: float) -> void:
	if sim == null:
		return
	if not finished and not paused:
		var forward: float = 0.0
		var turn: float = 0.0
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			forward += 1.0
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			forward -= 1.0
		if Input.is_key_pressed(KEY_A):
			turn -= 1.0
		if Input.is_key_pressed(KEY_D):
			turn += 1.0
		sim.player_input(delta, forward, turn)
		sim.update(delta)
	_update_units()
	_update_camera()
	_update_hud()
	if sim.last_message != last_sim_message:
		last_sim_message = sim.last_message
		_add_message(last_sim_message)
	if sim.result != "" and not finished:
		finish_timer += delta
		if finish_timer >= RESULT_DELAY:
			_finish_and_return()


func _update_units() -> void:
	for i in range(unit_nodes.size()):
		if i >= sim.units.size():
			continue
		var unit: Dictionary = sim.units[i]
		var node: Node3D = unit_nodes[i]
		var alive: bool = bool(unit["alive"])
		var in_vehicle: bool = sim.inside == i
		node.visible = alive and not in_vehicle
		node.position = Vector3(float(unit["x"]), 0.0, float(unit["z"]))
		node.rotation = Vector3(0.0, -float(unit["yaw"]), 0.0)


func _update_camera() -> void:
	var unit: Dictionary = sim.player_unit()
	if unit.is_empty():
		return
	camera.position = Vector3(float(unit["x"]), sim.eye_height(), float(unit["z"]))
	camera.rotation = Vector3(0.0, -float(unit["yaw"]), 0.0)


func _update_hud() -> void:
	var counts: Dictionary = sim.alive_counts()
	var distance: float = sim.distance_to_nearest_enemy()
	status_label.text = "Czas: %d s  |  nasi: %d  |  wrogowie: %d  |  organizacja: %d%%  |  broń: %s  |  cel: %s" % [
		int(sim.time_left()),
		int(counts["friends"]),
		int(counts["enemies"]),
		int(round(float(sim.org[true]))),
		sim.player_weapon_name(),
		"brak" if distance < 0.0 else "%d m" % int(distance),
	]
	log_label.text = _join_lines(messages)
	if sim.result != "":
		overlay.visible = true
		overlay_label.visible = true
		overlay_label.text = "%s\nPowrót do kampanii…" % _result_text(sim.result)
	elif paused:
		overlay.visible = true
		overlay_label.visible = true
		overlay_label.text = "PAUZA\nEsc — wznów, Enter — powrót do kampanii (odwrót)"
	else:
		overlay.visible = false
		overlay_label.visible = false


func _result_text(result: String) -> String:
	match result:
		"win":
			return "ZWYCIĘSTWO — wróg rozbity."
		"loss":
			return "PORAŻKA — dowódca poległ."
		"retreat":
			return "ODWRÓT — wracasz na mapę."
		_:
			return "BEZ ROZSTRZYGNIĘCIA — czas minął."


# --- wejście -----------------------------------------------------------------


func _unhandled_input(event: InputEvent) -> void:
	if sim == null or finished:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_E:
				sim.player_toggle_vehicle()
			KEY_R:
				sim.player_retreat()
			KEY_ENTER, KEY_KP_ENTER:
				sim.abort_battle()
			KEY_SPACE:
				if not paused:
					sim.player_fire()
			KEY_ESCAPE:
				paused = not paused
				if DisplayServer.get_name() != "headless":
					Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if paused else Input.MOUSE_MODE_CAPTURED
		return
	if paused:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if DisplayServer.get_name() != "headless" and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			return
		sim.player_fire()
	elif event is InputEventMouseMotion and DisplayServer.get_name() != "headless":
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			sim.player_turn(1.0, event.relative.x * MOUSE_SENSITIVITY)


# --- zakończenie -------------------------------------------------------------


func _finish_and_return() -> void:
	if finished:
		return
	finished = true
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var outcome: Dictionary = sim.outcome()
	if GameState.campaign != null and GameState.battle_enemy != null:
		GameState.campaign.apply_battle_outcome(GameState.battle_enemy, outcome)
	GameState.last_outcome = outcome
	GameState.battle_enemy = null
	get_tree().change_scene_to_file("res://scenes/campaign.tscn")
