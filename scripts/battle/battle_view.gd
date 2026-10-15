extends Node3D
## Widok bitwy FPS: pole 1000 × 400 m, kamera pierwszej osoby, prymitywy 3D.
##
## Sylwetki: piechur to kapsuła w mundurze, czołg i wóz bojowy mają kadłub,
## dwie gąsienice z kołami, wieżę z włazem i lufę (bryły z teksturami AI).
##
## Klawisze: WSAD/strzałki — ruch, mysz — obrót, LPM/Spacja — ognia,
## E — wsiadanie/wysiadanie, R — odwrót (x < 40 m), Esc — pauza, Enter — powrót.

const BattleSim = preload("res://scripts/battle/battle_sim.gd")
const GameState = preload("res://scripts/game_state.gd")
const UnitsData = preload("res://scripts/logic/units_data.gd")
const DayNight = preload("res://scripts/logic/daynight.gd")
const Terrain = preload("res://scripts/logic/terrain.gd")
const GameTextures = preload("res://scripts/logic/game_textures.gd")

const MOUSE_SENSITIVITY := 0.0015
const RESULT_DELAY := 1.5
const MAX_MESSAGES := 4

const COLOR_PLAYER := Color(0.25, 0.90, 0.35)
const COLOR_FRIEND := Color(0.25, 0.45, 0.90)
const COLOR_ENEMY := Color(0.85, 0.20, 0.20)
const COLOR_TRUNK := Color(0.30, 0.22, 0.14)
const COLOR_CANOPY := Color(0.16, 0.42, 0.20)
const COLOR_ROCK := Color(0.45, 0.42, 0.38)
const METAL_DARK := Color(0.15, 0.15, 0.15)

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
	_add_ground(terrain_kind)
	_add_box(Vector3(0.6, 0.12, BattleSim.FIELD_H), Color(0.95, 0.95, 0.95, 0.85), Vector3(40.0, 0.06, BattleSim.FIELD_H * 0.5))

	# Tekstury otoczenia (gdy któregoś brakuje, wracamy do płaskiego koloru).
	var bark: Texture2D = GameTextures.prop("tree_bark")
	var canopy: Texture2D = GameTextures.prop("tree_canopy")
	var rock: Texture2D = GameTextures.prop("rock")
	var wall: Texture2D = GameTextures.prop("wall")
	var roof: Texture2D = GameTextures.prop("roof")
	var uv_env := Vector3(2.0, 2.0, 1.0)

	for obstacle in sim.obstacles:
		var pos := Vector3(float(obstacle["x"]), 0.0, float(obstacle["z"]))
		var radius: float = float(obstacle["r"])
		if terrain_kind == "forest":
			_add_cylinder(radius * 0.35, radius * 0.35, 4.0, COLOR_TRUNK, pos + Vector3(0, 2.0, 0), bark, uv_env)
			_add_sphere(radius, COLOR_CANOPY, pos + Vector3(0, 4.0, 0), canopy, uv_env)
		elif terrain_kind == "hills":
			_add_sphere(radius, COLOR_ROCK, pos + Vector3(0, radius * 0.4, 0), rock, uv_env)
		else:
			_add_box(Vector3(radius, 1.2, radius), COLOR_ROCK, pos + Vector3(0, 0.6, 0), rock, uv_env)

	if terrain_kind == "city":
		var roof_color := Color(0.38, 0.38, 0.39)
		for i in range(6):
			var x: float = 430.0 + float(i % 3) * 22.0
			var z: float = 160.0 + float(i / 3) * 40.0
			_add_box(Vector3(14.0, 9.0, 14.0), Color(0.62, 0.58, 0.52), Vector3(x, 4.5, z), wall, Vector3(2.0, 1.0, 1.0))
			_add_box(Vector3(14.4, 0.4, 14.4), roof_color, Vector3(x, 9.2, z), roof, uv_env)

	camera = Camera3D.new()
	camera.current = true
	add_child(camera)


## Grunt bitwy: pole 1000 × 400 m z teksturą terenu rozłożoną co ~50 m.
func _add_ground(terrain_kind: String) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(BattleSim.FIELD_W, 1.0, BattleSim.FIELD_H)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	var kind: int = _terrain_kind_of(terrain_kind)
	var texture: Texture2D = GameTextures.master(kind)
	if texture != null:
		var material := StandardMaterial3D.new()
		material.albedo_texture = texture
		material.uv1_scale = Vector3(BattleSim.FIELD_W / 50.0, BattleSim.FIELD_H / 50.0, 1.0)
		material.roughness = 0.95
		node.material_override = material
	else:
		node.material_override = _material(_ground_color(terrain_kind))
	node.position = Vector3(BattleSim.FIELD_W * 0.5, -0.5, BattleSim.FIELD_H * 0.5)
	add_child(node)


## Nazwa terenu z GameState („las”, „wzgórza”, …) → Terrain.Kind.
func _terrain_kind_of(terrain_kind: String) -> int:
	match terrain_kind:
		"forest":
			return Terrain.Kind.FOREST
		"hills":
			return Terrain.Kind.HILLS
		"city":
			return Terrain.Kind.CITY
		_:
			return Terrain.Kind.PLAINS


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


## Materiały są wspólne dla wszystkich brył o tym samym wyglądzie — przy
## sylwetkach z setek brył bez cache’a powstałyby tysiące identycznych
## materiałów (i tyle samo wywołań rysowania). Materiałów nigdy nie
## modyfikujemy po utworzeniu, więc dzielenie ich jest bezpieczne.
var _material_cache: Dictionary = {}


func _material(color: Color) -> StandardMaterial3D:
	var key := "flat:%s" % color.to_html()
	if _material_cache.has(key):
		return _material_cache[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	_material_cache[key] = material
	return material


## Materiał jednostki: kolor strony × tekstura sprzętu (Godot mnoży albedo_color
## przez teksturę), dzięki czemu detal pochodzi z tekstury, a przynależność do
## strony pozostaje czytelna. Bez tekstury — sam kolor strony.
func _material_side(texture: Texture2D, side_color: Color, uv_scale: Vector3 = Vector3.ONE) -> StandardMaterial3D:
	if texture == null:
		return _material(side_color)
	var key := "side:%d:%s:%s" % [texture.get_instance_id(), side_color.to_html(), str(uv_scale)]
	if _material_cache.has(key):
		return _material_cache[key]
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.albedo_color = side_color
	material.uv1_scale = uv_scale
	material.roughness = 0.9
	_material_cache[key] = material
	return material


## Materiał z teksturą (albo płaski kolor, gdy tekstury brak).
func _material_for(texture: Texture2D, fallback: Color, uv_scale: Vector3 = Vector3.ONE) -> StandardMaterial3D:
	if texture == null:
		return _material(fallback)
	var key := "tex:%d:%s" % [texture.get_instance_id(), str(uv_scale)]
	if _material_cache.has(key):
		return _material_cache[key]
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.uv1_scale = uv_scale
	material.roughness = 0.95
	_material_cache[key] = material
	return material


func _add_box(size: Vector3, color: Color, pos: Vector3, texture: Texture2D = null, uv_scale: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _material_for(texture, color, uv_scale)
	node.position = pos
	add_child(node)
	return node


func _add_cylinder(top: float, bottom: float, height: float, color: Color, pos: Vector3, texture: Texture2D = null, uv_scale: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _material_for(texture, color, uv_scale)
	node.position = pos
	add_child(node)
	return node


func _add_sphere(radius: float, color: Color, pos: Vector3, texture: Texture2D = null, uv_scale: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _material_for(texture, color, uv_scale)
	node.position = pos
	add_child(node)
	return node


## Sylwetki jednostek są składane z brył, ale tak, żeby przypominały prawdziwe
## pojazdy z 1975 roku: pochyły pancerz czołowy, błotniki z fartuchami, gąsienice
## z osobnych ogniw, koła jezdne z piastą i felgą, koło napędowe i napinające,
## koła podtrzymujące, wieża kopułowa (ZSRR) albo kanciasta (USA), jarzmo, lufa
## z przedmuchiwaczem i wylotem, włazy, km przeciwlotniczy, reflektory, anteny,
## wydechy, narzędzia, zbiorniki paliwa (ZSRR) albo skrzynie (USA) i zapasowe
## ogniwa na pancerzu.
##
## Liczba brył jest stała i pilnuje jej tests/test_views.gd:
## czołg 256, wóz bojowy 128, piechur 10.
const ARMOR_PARTS := 256
const MECH_PARTS := 128
const INFANTRY_PARTS := 10

## Tony barwy strony: 0 = barwa strony, większe = ciemniejsze, -1 = ciemny metal.
const TONE_BODY := 0.0
const TONE_DARK := 0.3
const TONE_DEEP := 0.55
const TONE_TRACK := 0.5
const TONE_WHEEL := 0.68
const TONE_METAL := -1.0

const TRACK_UV := Vector3(0.6, 1.0, 1.0)
const PLAIN_UV := Vector3(1.0, 1.0, 1.0)
const HULL_UV := Vector3(2.0, 1.0, 1.0)


func _build_units() -> void:
	unit_nodes = []
	# Tekstury: mundur dla piechoty, pancerz i gąsienice dla pojazdów. Są jasne
	# i neutralne, bo kolor strony jest mnożony w materiale (_material_side).
	var textures: Dictionary = {
		"uniform": GameTextures.unit("uniform"),
		"armor": GameTextures.unit("armor"),
		"track": GameTextures.unit("track"),
	}
	for unit in sim.units:
		var cls: String = str(unit["cls"])
		var is_player: bool = bool(unit["is_player"])
		var color: Color = COLOR_PLAYER if is_player else (COLOR_FRIEND if bool(unit["side"]) else COLOR_ENEMY)
		var variant: String = "su" if UnitsData.side_of(str(unit["def_id"])) == "su" else "us"
		var node := Node3D.new()
		node.name = "unit_%d" % unit_nodes.size()
		add_child(node)
		if cls == UnitsData.CLS_INFANTRY:
			_build_infantry(node, color, textures["uniform"])
		elif cls == UnitsData.CLS_MECH:
			_instantiate_parts(node, _mech_parts(variant), color, textures)
		else:
			_instantiate_parts(node, _tank_parts(variant), color, textures)
		unit_nodes.append(node)


## Piechur: hełm, tors, plecak, ręce, nogi i karabin (10 brył).
func _build_infantry(node: Node3D, color: Color, uniform: Texture2D) -> void:
	var uv := Vector3(1.5, 1.5, 1.5)
	var body := CapsuleMesh.new()
	body.radius = 0.32
	body.height = 1.2
	var body_node := MeshInstance3D.new()
	body_node.mesh = body
	body_node.material_override = _material_side(uniform, color, uv)
	body_node.position = Vector3(0, 1.05, 0)
	node.add_child(body_node)

	var helmet := SphereMesh.new()
	helmet.radius = 0.22
	helmet.height = 0.36
	var helmet_node := MeshInstance3D.new()
	helmet_node.mesh = helmet
	helmet_node.material_override = _material_side(uniform, color.darkened(TONE_DEEP), uv)
	helmet_node.position = Vector3(0, 1.72, 0)
	node.add_child(helmet_node)

	var pack := BoxMesh.new()
	pack.size = Vector3(0.3, 0.42, 0.5)
	var pack_node := MeshInstance3D.new()
	pack_node.mesh = pack
	pack_node.material_override = _material_side(uniform, color.darkened(TONE_DARK), uv)
	pack_node.position = Vector3(-0.26, 1.2, 0)
	node.add_child(pack_node)

	for side in [-1.0, 1.0]:
		var arm := BoxMesh.new()
		arm.size = Vector3(0.16, 0.6, 0.16)
		var arm_node := MeshInstance3D.new()
		arm_node.mesh = arm
		arm_node.material_override = _material_side(uniform, color.darkened(TONE_DARK), uv)
		arm_node.position = Vector3(0.06, 1.15, side * 0.3)
		arm_node.rotation = Vector3(0.0, 0.0, side * 0.15)
		node.add_child(arm_node)
		var leg := BoxMesh.new()
		leg.size = Vector3(0.2, 0.85, 0.2)
		var leg_node := MeshInstance3D.new()
		leg_node.mesh = leg
		leg_node.material_override = _material_side(uniform, color.darkened(TONE_DEEP), uv)
		leg_node.position = Vector3(0.0, 0.45, side * 0.14)
		node.add_child(leg_node)
		var pouch := BoxMesh.new()
		pouch.size = Vector3(0.18, 0.22, 0.12)
		var pouch_node := MeshInstance3D.new()
		pouch_node.mesh = pouch
		pouch_node.material_override = _material_side(uniform, color.darkened(TONE_DEEP), uv)
		pouch_node.position = Vector3(0.2, 0.95, side * 0.26)
		node.add_child(pouch_node)

	var rifle := BoxMesh.new()
	rifle.size = Vector3(1.1, 0.12, 0.12)
	var rifle_node := MeshInstance3D.new()
	rifle_node.mesh = rifle
	rifle_node.material_override = _material(METAL_DARK)
	rifle_node.position = Vector3(0.5, 1.30, 0.26)
	node.add_child(rifle_node)


# --- opisy brył ---------------------------------------------------------------


## Jedna bryła sylwetki: prostopadłościan (`box`) albo walec (`cyl`).
func _part_box(size: Vector3, pos: Vector3, rot: Vector3, tone: float, tex: String,
		uv: Vector3 = PLAIN_UV, shadow: bool = true) -> Dictionary:
	return {"prim": "box", "size": size, "pos": pos, "rot": rot,
		"tone": tone, "tex": tex, "uv": uv, "shadow": shadow}


func _part_cyl(top: float, bottom: float, height: float, segments: int, pos: Vector3,
		rot: Vector3, tone: float, tex: String, uv: Vector3 = PLAIN_UV,
		shadow: bool = true) -> Dictionary:
	return {"prim": "cyl", "top": top, "bottom": bottom, "height": height, "seg": segments,
		"pos": pos, "rot": rot, "tone": tone, "tex": tex, "uv": uv, "shadow": shadow}


## Tworzy bryły z opisów. Materiał: barwa strony przyciemniona o `tone`
## (tone < 0 to ciemny metal, niezależny od strony).
func _instantiate_parts(node: Node3D, parts: Array, color: Color, textures: Dictionary) -> void:
	for part in parts:
		var tone: float = float(part["tone"])
		var tex_key: String = str(part["tex"])
		var texture: Texture2D = null
		if tex_key != "" and textures.has(tex_key):
			texture = textures[tex_key]
		var part_color: Color = METAL_DARK if tone < 0.0 else color.darkened(tone)
		var mesh_node := MeshInstance3D.new()
		if str(part["prim"]) == "box":
			var box := BoxMesh.new()
			box.size = part["size"]
			mesh_node.mesh = box
		else:
			var cyl := CylinderMesh.new()
			cyl.top_radius = float(part["top"])
			cyl.bottom_radius = float(part["bottom"])
			cyl.height = float(part["height"])
			cyl.radial_segments = int(part["seg"])
			mesh_node.mesh = cyl
		var uv_scale: Vector3 = part["uv"]
		mesh_node.material_override = _material_side(texture, part_color, uv_scale)
		mesh_node.position = part["pos"]
		mesh_node.rotation = part["rot"]
		if not bool(part.get("shadow", true)):
			mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(mesh_node)


# --- gąsienice ----------------------------------------------------------------


## Punkty bieżni gąsienicy (dolny bieg, tylny łuk, górny bieg, przedni łuk).
func _track_path(front_x: float, rear_x: float, y_bottom: float, y_top: float) -> Array:
	var r_end: float = (y_top - y_bottom) * 0.5
	var y_center: float = (y_bottom + y_top) * 0.5
	var ds: float = 0.01
	var run: int = maxi(2, int(round((front_x - rear_x) / ds)))
	var arc: int = maxi(4, int(round(PI * r_end / ds)))
	var points: Array = []
	for s in range(run + 1):
		points.append(Vector2(front_x - ds * float(s), y_bottom))
	for s in range(arc + 1):
		var a: float = PI * 1.5 - PI * float(s) / float(arc)
		points.append(Vector2(rear_x + cos(a) * r_end, y_center + sin(a) * r_end))
	for s in range(run + 1):
		points.append(Vector2(rear_x + ds * float(s), y_top))
	for s in range(arc + 1):
		var a: float = PI * 0.5 - PI * float(s) / float(arc)
		points.append(Vector2(front_x + cos(a) * r_end, y_center + sin(a) * r_end))
	return points


## Gąsienica jako rząd ogniw rozłożonych równomiernie wzdłuż bieżni.
## `count` określa dokładną liczbę ogniw, więc brył w sylwetce nie da się
## przeoczyć.
func _add_track_links(parts: Array, count: int, z: float, width: float,
		front_x: float, rear_x: float, y_bottom: float, y_top: float) -> void:
	var points: Array = _track_path(front_x, rear_x, y_bottom, y_top)
	var total: int = points.size()
	if count < 4 or total < 4:
		return
	var perimeter: float = 0.0
	for s in range(1, total):
		perimeter += (points[s] - points[s - 1]).length()
	var pitch: float = perimeter / float(count)
	for i in range(count):
		var index: int = int(round(float(i) * float(total - 1) / float(count)))
		var point: Vector2 = points[index]
		var prev: Vector2 = points[maxi(0, index - 3)]
		var next: Vector2 = points[mini(total - 1, index + 3)]
		var tangent: Vector2 = next - prev
		if tangent.length() < 0.0001:
			tangent = Vector2.RIGHT
		tangent = tangent.normalized()
		parts.append(_part_box(Vector3(maxf(0.12, pitch * 0.92), 0.07, width),
			Vector3(point.x, point.y, z), Vector3(0.0, 0.0, atan2(tangent.y, tangent.x)),
			TONE_TRACK, "track", TRACK_UV, false))


## Koło jezdne: opona, felga i piasta.
func _add_road_wheel(parts: Array, x: float, y: float, z: float, radius: float, width: float) -> void:
	var rot := Vector3(PI * 0.5, 0.0, 0.0)
	parts.append(_part_cyl(radius, radius, width, 16, Vector3(x, y, z), rot, TONE_WHEEL, "track", PLAIN_UV, false))
	parts.append(_part_cyl(radius * 0.52, radius * 0.52, width * 1.12, 16, Vector3(x, y, z), rot, TONE_DEEP, "track", PLAIN_UV, false))
	parts.append(_part_cyl(radius * 0.17, radius * 0.17, width * 1.3, 10, Vector3(x, y, z), rot, TONE_METAL, "", PLAIN_UV, false))


## Podwozie jednej strony: koła jezdne, koło napędowe, napinające, podtrzymujące.
## Zwraca liczbę brył stałych (bez ogniw), żeby dało się policzyć budżet ogniw.
func _add_running_gear(parts: Array, z: float, wheels: int, wheel_radius: float, width: float,
		front_x: float, rear_x: float, y_bottom: float, y_top: float) -> int:
	var rot := Vector3(PI * 0.5, 0.0, 0.0)
	var y_center: float = (y_bottom + y_top) * 0.5
	var span: float = (front_x - rear_x) * 0.72
	for w in range(wheels):
		var t: float = 0.0 if wheels <= 1 else float(w) / float(wheels - 1)
		_add_road_wheel(parts, -span * 0.5 + span * t, y_bottom + wheel_radius, z, wheel_radius, width * 0.45)
	# koło napędowe (tył) i napinające (przód): tarcza + piasta
	parts.append(_part_cyl(0.36, 0.36, width * 0.42, 16, Vector3(rear_x, y_center, z), rot, TONE_WHEEL, "track", PLAIN_UV, false))
	parts.append(_part_cyl(0.15, 0.15, width * 0.5, 10, Vector3(rear_x, y_center, z), rot, TONE_METAL, "", PLAIN_UV, false))
	parts.append(_part_cyl(0.32, 0.32, width * 0.4, 16, Vector3(front_x, y_center, z), rot, TONE_WHEEL, "track", PLAIN_UV, false))
	parts.append(_part_cyl(0.13, 0.13, width * 0.48, 10, Vector3(front_x, y_center, z), rot, TONE_METAL, "", PLAIN_UV, false))
	# koła podtrzymujące pod górnym biegiem
	for r in range(3):
		parts.append(_part_cyl(0.11, 0.11, width * 0.35, 8,
			Vector3(-1.6 + 1.6 * float(r), y_top - 0.08, z), rot, TONE_DEEP, "track", PLAIN_UV, false))
	return wheels * 3 + 4 + 3


# --- czołg --------------------------------------------------------------------


## Sylwetka czołgu: `us` (M48A5 / M60A1) albo `su` (T-55 / T-62 / T-72).
func _tank_parts(variant: String) -> Array:
	var parts: Array = []
	_add_tank_hull(parts, variant)
	_add_tank_turret(parts, variant)
	_add_tank_details(parts, variant)
	# Gąsienice dostają resztę budżetu brył, więc liczba wychodzi co do jednej.
	var width: float = 0.62
	var front_x: float = 2.5
	var rear_x: float = -2.5
	var y_bottom: float = 0.10
	var y_top: float = 0.82
	var fixed: int = (5 * 3 + 4 + 3) * 2
	var links_total: int = maxi(16, ARMOR_PARTS - parts.size() - fixed)
	var per_belt: int = links_total >> 1  # połowa ogniw na każdą gąsienicę
	for side in [-1.0, 1.0]:
		_add_running_gear(parts, side * 1.3, 5, 0.34, width, front_x, rear_x, y_bottom, y_top)
		_add_track_links(parts, per_belt, side * 1.3, width, front_x, rear_x, y_bottom, y_top)
	return _fit_parts(parts, ARMOR_PARTS)


## Kadłub: wanna, górna część, pokład, pochyły pancerz czołowy, tył, błotniki.
func _add_tank_hull(parts: Array, variant: String) -> void:
	parts.append(_part_box(Vector3(6.2, 0.7, 2.4), Vector3(0.0, 0.85, 0.0), Vector3.ZERO, TONE_BODY, "armor", HULL_UV))
	parts.append(_part_box(Vector3(6.2, 0.5, 2.44), Vector3(0.0, 1.4, 0.0), Vector3.ZERO, TONE_BODY, "armor", HULL_UV))
	parts.append(_part_box(Vector3(6.0, 0.16, 2.5), Vector3(0.0, 1.7, 0.0), Vector3.ZERO, TONE_DARK, "armor", HULL_UV))
	# pochyły pancerz czołowy i dolna płyta nosa
	parts.append(_part_box(Vector3(2.6, 0.14, 2.46), Vector3(2.35, 1.45, 0.0), Vector3(0.0, 0.0, -0.72), TONE_BODY, "armor", HULL_UV))
	parts.append(_part_box(Vector3(1.3, 0.5, 2.42), Vector3(3.05, 1.1, 0.0), Vector3.ZERO, TONE_DARK, "armor", HULL_UV))
	if variant == "su":
		# T-55: niżej osadzony kadłub i bardziej ścięty przód
		parts.append(_part_box(Vector3(1.2, 0.5, 2.3), Vector3(3.35, 0.95, 0.0), Vector3(0.0, 0.0, -0.35), TONE_BODY, "armor", HULL_UV))
	else:
		parts.append(_part_box(Vector3(1.0, 0.62, 2.5), Vector3(3.2, 1.05, 0.0), Vector3(0.0, 0.0, -0.25), TONE_BODY, "armor", HULL_UV))
	# płyta tylna i osłona przekładni
	parts.append(_part_box(Vector3(1.6, 0.9, 2.42), Vector3(-2.9, 1.3, 0.0), Vector3(0.0, 0.0, 0.5), TONE_DARK, "armor", HULL_UV))
	parts.append(_part_box(Vector3(0.5, 1.4, 2.3), Vector3(-3.3, 1.3, 0.0), Vector3.ZERO, TONE_DEEP, "armor", HULL_UV))
	# błotniki, fartuchy i uchwyty nad gąsienicami
	for side in [-1.0, 1.0]:
		parts.append(_part_box(Vector3(5.9, 0.12, 0.78), Vector3(-0.1, 1.32, side * 1.28), Vector3.ZERO, TONE_DARK, "armor", Vector3(2.0, 1.0, 1.0)))
		parts.append(_part_box(Vector3(0.9, 0.1, 0.7), Vector3(2.95, 1.3, side * 1.28), Vector3(0.0, 0.0, side * -0.2), TONE_DARK, "armor"))
		parts.append(_part_box(Vector3(0.55, 0.42, 0.66), Vector3(3.4, 0.98, side * 1.28), Vector3.ZERO, TONE_DEEP, "armor"))
		parts.append(_part_box(Vector3(0.5, 0.45, 0.62), Vector3(-3.05, 0.98, side * 1.28), Vector3.ZERO, TONE_DEEP, "armor"))


## Wieża: kopułowa warstwowa (ZSRR) albo kanciasta z pochyłym przodem (USA).
func _add_tank_turret(parts: Array, variant: String) -> void:
	parts.append(_part_cyl(1.4, 1.4, 0.14, 24, Vector3(0.0, 1.8, 0.0), Vector3.ZERO, TONE_DEEP, "armor"))
	if variant == "su":
		parts.append(_part_cyl(1.36, 1.18, 0.34, 24, Vector3(0.0, 2.02, 0.0), Vector3.ZERO, TONE_BODY, "armor", HULL_UV))
		parts.append(_part_cyl(1.18, 0.98, 0.3, 24, Vector3(0.0, 2.34, 0.0), Vector3.ZERO, TONE_BODY, "armor", HULL_UV))
		parts.append(_part_cyl(0.98, 0.8, 0.28, 24, Vector3(0.0, 2.6, 0.0), Vector3.ZERO, TONE_BODY, "armor", HULL_UV))
		# odlewane jarzmo działa
		parts.append(_part_cyl(0.46, 0.52, 0.62, 16, Vector3(1.3, 2.25, 0.0), Vector3(0.0, 0.0, -PI * 0.5), TONE_BODY, "armor"))
	else:
		parts.append(_part_box(Vector3(2.5, 0.72, 2.7), Vector3(-0.1, 2.16, 0.0), Vector3.ZERO, TONE_BODY, "armor", HULL_UV))
		parts.append(_part_box(Vector3(1.7, 0.56, 2.62), Vector3(1.15, 2.3, 0.0), Vector3(0.0, 0.0, -0.6), TONE_BODY, "armor", HULL_UV))
		parts.append(_part_box(Vector3(2.3, 0.12, 2.52), Vector3(-0.2, 2.56, 0.0), Vector3.ZERO, TONE_DARK, "armor", HULL_UV))
		parts.append(_part_box(Vector3(0.5, 0.56, 0.92), Vector3(1.85, 2.28, 0.0), Vector3.ZERO, TONE_DARK, "armor"))
	# lufa z przedmuchiwaczem i wylotem
	var gun_y: float = 2.28 if variant == "us" else 2.25
	var barrel_len: float = 3.4 if variant == "us" else 4.0
	var barrel_start: float = 1.9 if variant == "us" else 1.55
	parts.append(_part_cyl(0.1, 0.115, barrel_len, 16, Vector3(barrel_start + barrel_len * 0.5, gun_y, 0.0), Vector3(0.0, 0.0, -PI * 0.5), TONE_DEEP, "armor", Vector3(2.0, 1.0, 1.0)))
	parts.append(_part_cyl(0.16, 0.16, 0.5, 16, Vector3(barrel_start + barrel_len * 0.35, gun_y, 0.0), Vector3(0.0, 0.0, -PI * 0.5), TONE_DEEP, "armor"))
	parts.append(_part_cyl(0.13, 0.13, 0.3, 16, Vector3(barrel_start + barrel_len + 0.1, gun_y, 0.0), Vector3(0.0, 0.0, -PI * 0.5), TONE_METAL, ""))
	# włazy, km przeciwlotniczy, wyrzutnie granatów dymnych
	parts.append(_part_cyl(0.3, 0.3, 0.12, 12, Vector3(-0.35, 2.78, 0.0), Vector3.ZERO, TONE_DEEP, "armor"))
	parts.append(_part_cyl(0.26, 0.26, 0.1, 12, Vector3(0.45, 2.72, 0.0), Vector3.ZERO, TONE_DEEP, "armor"))
	parts.append(_part_box(Vector3(0.3, 0.26, 0.28), Vector3(-0.35, 2.9, 0.0), Vector3.ZERO, TONE_METAL, ""))
	parts.append(_part_box(Vector3(0.72, 0.16, 0.16), Vector3(-0.3, 3.02, 0.0), Vector3.ZERO, TONE_METAL, ""))
	parts.append(_part_cyl(0.04, 0.04, 0.9, 8, Vector3(0.35, 3.02, 0.0), Vector3(0.0, 0.0, -PI * 0.5), TONE_METAL, ""))
	parts.append(_part_box(Vector3(0.3, 0.22, 0.14), Vector3(-0.62, 2.96, 0.0), Vector3.ZERO, TONE_DEEP, "armor"))
	for smoke in range(6):
		var side: float = 1.0 if smoke % 2 == 0 else -1.0
		var row: int = smoke >> 1  # co dwa pociski tworzą rząd wyrzutni
		parts.append(_part_cyl(0.06, 0.06, 0.22, 6,
			Vector3(0.85 - float(row) * 0.22, 2.5 if variant == "su" else 2.15, side * 1.05),
			Vector3(0.0, 0.0, -0.5), TONE_DEEP, "armor"))


## Szczegóły: reflektory, anteny, wydech, narzędzia, paliwo i zapasowe ogniwa.
func _add_tank_details(parts: Array, variant: String) -> void:
	# reflektory z osłonami i sygnał dźwiękowy
	for side in [-1.0, 1.0]:
		parts.append(_part_cyl(0.13, 0.13, 0.16, 12, Vector3(3.0, 1.62, side * 0.86), Vector3(0.0, 0.0, -PI * 0.5), TONE_METAL, ""))
		parts.append(_part_box(Vector3(0.18, 0.22, 0.3), Vector3(3.05, 1.72, side * 0.86), Vector3.ZERO, TONE_DEEP, "armor"))
		parts.append(_part_cyl(0.05, 0.05, 0.18, 8, Vector3(3.0, 1.5, side * 1.05), Vector3(0.0, 0.0, -PI * 0.5), TONE_METAL, ""))
	parts.append(_part_box(Vector3(0.2, 0.2, 0.2), Vector3(3.2, 1.5, 0.0), Vector3.ZERO, TONE_METAL, ""))
	# haki holownicze z przodu i z tyłu
	for side in [-1.0, 1.0]:
		parts.append(_part_box(Vector3(0.22, 0.14, 0.12), Vector3(3.4, 0.85, side * 1.0), Vector3.ZERO, TONE_METAL, ""))
		parts.append(_part_box(Vector3(0.22, 0.14, 0.12), Vector3(-3.55, 1.2, side * 1.0), Vector3.ZERO, TONE_METAL, ""))
	# lina holownicza wzdłuż burty i narzędzia pionierskie
	parts.append(_part_cyl(0.035, 0.035, 3.4, 6, Vector3(0.4, 1.34, 1.2), Vector3(0.0, 0.0, -PI * 0.5), TONE_METAL, ""))
	parts.append(_part_box(Vector3(1.1, 0.08, 0.16), Vector3(-1.2, 1.36, 1.15), Vector3.ZERO, TONE_DEEP, "armor"))
	parts.append(_part_box(Vector3(0.9, 0.09, 0.12), Vector3(0.2, 1.36, -1.16), Vector3.ZERO, TONE_DEEP, "armor"))
	parts.append(_part_box(Vector3(0.6, 0.12, 0.16), Vector3(-2.0, 1.36, 1.16), Vector3.ZERO, TONE_DEEP, "armor"))
	# wydech (ZSRR: dwie rury z osłoną, USA: tłumik)
	if variant == "su":
		for side in [-1.0, 1.0]:
			parts.append(_part_cyl(0.12, 0.12, 0.5, 10, Vector3(-2.6, 1.35, side * 1.15), Vector3(0.0, 0.0, -PI * 0.5), TONE_METAL, ""))
			parts.append(_part_box(Vector3(0.7, 0.2, 0.24), Vector3(-2.6, 1.48, side * 1.15), Vector3.ZERO, TONE_DEEP, "armor"))
	else:
		parts.append(_part_box(Vector3(1.0, 0.26, 0.3), Vector3(-2.9, 1.55, -1.15), Vector3.ZERO, TONE_METAL, ""))
		parts.append(_part_cyl(0.09, 0.09, 0.4, 10, Vector3(-3.4, 1.55, -1.15), Vector3(0.0, 0.0, -PI * 0.5), TONE_METAL, ""))
	# zbiorniki paliwa z tyłu (ZSRR) albo skrzynie i plandeka (USA)
	if variant == "su":
		for side in [-1.0, 1.0]:
			parts.append(_part_cyl(0.3, 0.3, 1.0, 16, Vector3(-3.75, 1.75, side * 0.6), Vector3(0.0, 0.0, -PI * 0.5), TONE_WHEEL, "armor", Vector3(1.5, 1.0, 1.0)))
			parts.append(_part_box(Vector3(0.1, 0.14, 0.7), Vector3(-3.75, 2.05, side * 0.6), Vector3.ZERO, TONE_METAL, ""))
	else:
		for side in [-1.0, 1.0]:
			parts.append(_part_box(Vector3(0.8, 0.5, 0.7), Vector3(-3.7, 1.9, side * 0.62), Vector3.ZERO, TONE_DEEP, "armor"))
			parts.append(_part_box(Vector3(0.66, 0.1, 0.56), Vector3(-3.7, 2.2, side * 0.62), Vector3.ZERO, TONE_METAL, ""))
		parts.append(_part_cyl(0.2, 0.2, 2.2, 12, Vector3(-3.6, 1.75, 0.0), Vector3(0.0, 0.0, -PI * 0.5), TONE_DEEP, "armor"))
	# anteny na wieży
	for side in [-1.0, 1.0]:
		parts.append(_part_cyl(0.02, 0.02, 1.6, 4, Vector3(-1.0, 3.4, side * 0.9), Vector3.ZERO, TONE_METAL, "", PLAIN_UV, false))
	# zapasowe ogniwa na pancerzu czołowym
	for spare in range(6):
		parts.append(_part_box(Vector3(0.2, 0.07, 0.56),
			Vector3(2.45 - 0.24 * float(spare), 1.62 + 0.05 * float(spare % 3), -0.95),
			Vector3(0.0, 0.0, -0.72), TONE_TRACK, "track", TRACK_UV))


# --- wóz bojowy ---------------------------------------------------------------


## Sylwetka wozu bojowego: `us` (M113) albo `su` (BMP-1 / BTR-60 / MT-LB).
func _mech_parts(variant: String) -> Array:
	var parts: Array = []
	parts.append(_part_box(Vector3(5.2, 0.56, 2.0), Vector3(0.0, 0.75, 0.0), Vector3.ZERO, TONE_BODY, "armor", HULL_UV))
	parts.append(_part_box(Vector3(5.2, 0.5, 2.1), Vector3(0.0, 1.22, 0.0), Vector3.ZERO, TONE_BODY, "armor", HULL_UV))
	parts.append(_part_box(Vector3(5.0, 0.14, 2.16), Vector3(0.0, 1.5, 0.0), Vector3.ZERO, TONE_DARK, "armor", HULL_UV))
	parts.append(_part_box(Vector3(2.4, 0.12, 2.06), Vector3(1.8, 1.3, 0.0), Vector3(0.0, 0.0, -0.66), TONE_BODY, "armor", HULL_UV))
	parts.append(_part_box(Vector3(1.1, 0.44, 2.02), Vector3(2.5, 1.0, 0.0), Vector3.ZERO, TONE_DARK, "armor", HULL_UV))
	parts.append(_part_box(Vector3(1.2, 0.8, 2.02), Vector3(-2.3, 1.15, 0.0), Vector3(0.0, 0.0, 0.45), TONE_DARK, "armor", HULL_UV))
	for side in [-1.0, 1.0]:
		parts.append(_part_box(Vector3(5.0, 0.12, 0.62), Vector3(-0.1, 1.22, side * 1.12), Vector3.ZERO, TONE_DARK, "armor", Vector3(2.0, 1.0, 1.0)))
		parts.append(_part_box(Vector3(0.7, 0.09, 0.56), Vector3(2.6, 1.2, side * 1.12), Vector3(0.0, 0.0, side * -0.18), TONE_DARK, "armor"))
	# wieżyczka (BMP: z działkiem 73 mm, M113: z km-em)
	parts.append(_part_cyl(0.72, 0.78, 0.46, 16, Vector3(0.35, 1.7, 0.0), Vector3.ZERO, TONE_BODY, "armor", HULL_UV))
	parts.append(_part_cyl(0.6, 0.6, 0.1, 16, Vector3(0.35, 1.96, 0.0), Vector3.ZERO, TONE_DEEP, "armor"))
	parts.append(_part_cyl(0.26, 0.28, 0.3, 12, Vector3(0.15, 2.1, 0.0), Vector3.ZERO, TONE_DEEP, "armor"))
	if variant == "su":
		parts.append(_part_cyl(0.07, 0.08, 2.0, 12, Vector3(1.7, 1.72, 0.0), Vector3(0.0, 0.0, -PI * 0.5), TONE_DEEP, "armor"))
		parts.append(_part_cyl(0.1, 0.1, 0.26, 12, Vector3(2.75, 1.72, 0.0), Vector3(0.0, 0.0, -PI * 0.5), TONE_METAL, ""))
		parts.append(_part_box(Vector3(1.4, 0.3, 0.34), Vector3(1.6, 2.0, 0.0), Vector3.ZERO, TONE_DEEP, "armor"))
	else:
		parts.append(_part_box(Vector3(0.7, 0.18, 0.18), Vector3(0.55, 2.0, 0.0), Vector3.ZERO, TONE_METAL, ""))
		parts.append(_part_cyl(0.04, 0.04, 0.8, 8, Vector3(1.3, 2.0, 0.0), Vector3(0.0, 0.0, -PI * 0.5), TONE_METAL, ""))
	# reflektory, anteny, narzędzia, lina
	for side in [-1.0, 1.0]:
		parts.append(_part_cyl(0.11, 0.11, 0.14, 12, Vector3(2.45, 1.42, side * 0.78), Vector3(0.0, 0.0, -PI * 0.5), TONE_METAL, ""))
		parts.append(_part_box(Vector3(0.16, 0.2, 0.26), Vector3(2.5, 1.52, side * 0.78), Vector3.ZERO, TONE_DEEP, "armor"))
		parts.append(_part_box(Vector3(0.2, 0.12, 0.1), Vector3(2.7, 0.7, side * 0.9), Vector3.ZERO, TONE_METAL, ""))
	parts.append(_part_cyl(0.02, 0.02, 1.5, 4, Vector3(-1.1, 2.5, 0.8), Vector3.ZERO, TONE_METAL, "", PLAIN_UV, false))
	parts.append(_part_cyl(0.03, 0.03, 2.6, 6, Vector3(-0.4, 1.28, 1.0), Vector3(0.0, 0.0, -PI * 0.5), TONE_METAL, ""))
	parts.append(_part_box(Vector3(0.9, 0.08, 0.14), Vector3(-1.3, 1.3, 0.95), Vector3.ZERO, TONE_DEEP, "armor"))
	# ogniwa na pancerzu czołowym
	for spare in range(4):
		parts.append(_part_box(Vector3(0.18, 0.07, 0.5),
			Vector3(1.75 - 0.22 * float(spare), 1.45 + 0.04 * float(spare % 2), -0.75),
			Vector3(0.0, 0.0, -0.66), TONE_TRACK, "track", TRACK_UV))
	var width: float = 0.52
	var front_x: float = 2.0
	var rear_x: float = -2.1
	var y_bottom: float = 0.08
	var y_top: float = 0.72
	var fixed: int = (4 * 3 + 4 + 3) * 2
	var links_total: int = maxi(12, MECH_PARTS - parts.size() - fixed)
	var per_belt: int = links_total >> 1  # połowa ogniw na każdą gąsienicę
	for side in [-1.0, 1.0]:
		_add_running_gear(parts, side * 1.1, 4, 0.3, width, front_x, rear_x, y_bottom, y_top)
		_add_track_links(parts, per_belt, side * 1.1, width, front_x, rear_x, y_bottom, y_top)
	return _fit_parts(parts, MECH_PARTS)


# --- wyrównanie liczby brył ---------------------------------------------------


## Domyka liczbę brył do `target`: brakujące zamienia na zapasowe ogniwa
## na pancerzu, nadmiar usuwa z końca listy (to zawsze ostatnie ogniwa).
func _fit_parts(parts: Array, target: int) -> Array:
	while parts.size() > target:
		parts.remove_at(parts.size() - 1)
	var index: int = 0
	while parts.size() < target:
		var ring: int = index >> 3  # co ósme ogniwo trafia do wyższego rzędu
		parts.append(_part_box(Vector3(0.2, 0.07, 0.56),
			Vector3(2.15 - 0.24 * float(index % 8), 1.68 + 0.18 * float(ring), -1.05),
			Vector3(0.0, 0.0, -0.72), TONE_TRACK, "track", TRACK_UV))
		index += 1
	return parts


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
