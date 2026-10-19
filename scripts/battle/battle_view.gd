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
			var col: int = i % 3
			var row: int = int(float(i) / 3.0)   # 3 kolumny → dwa rzędy
			var x: float = 430.0 + float(col) * 22.0
			var z: float = 160.0 + float(row) * 40.0
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


## Materiał oznaczenia państwowego: gwiazda wycinana kanałem alfa, widoczna
## z obu stron (płytka jest cienka, więc rzuca się ją też na drugą burtę).
func _material_marking(texture: Texture2D) -> StandardMaterial3D:
	var key := "mark:%d" % texture.get_instance_id()
	if _material_cache.has(key):
		return _material_cache[key]
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = 0.5
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 0.9
	_material_cache[key] = material
	return material


## Materiał pierścienia strony: płaski, bez cieniowania, półprzezroczysty.
func _material_ring(color: Color) -> StandardMaterial3D:
	var key := "ring:%s" % color.to_html()
	if _material_cache.has(key):
		return _material_cache[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color.r, color.g, color.b, 0.34)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
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


## Sylwetki pojazdów składamy z brył, ale każda rodzina ma kształt prawdziwego
## wozu z 1975 roku: inną długość, wysokość, liczbę kół i układ bieżni. Pojazdy
## noszą barwy fabryczne (amerykański olive drab, radziecka zieleń 4BO), więc
## strony rozpoznaje się po sylwetce i oznaczeniu państwowym — tak jak wtedy.
##
## Liczba brył jest stała i pilnuje jej tests/test_views.gd: każdy pojazd —
## czołg, wóz kołowy i ich warianty — ma dokładnie 1024 bryły, piechur 10.
const VEHICLE_PARTS := 1024
const INFANTRY_PARTS := 10

## Barwy fabryczne 1975 roku.
const FACTORY_US := Color(0.58, 0.60, 0.39)
const FACTORY_SU := Color(0.43, 0.51, 0.31)
const UNIFORM_US := Color(0.58, 0.59, 0.41)
const UNIFORM_SU := Color(0.49, 0.49, 0.32)

## Rodzina sylwetki dla identyfikatora jednostki (patrz units_data.gd).
const ARMOR_SHAPES := {
	"us_arm_m60a1": "m60a1",
	"us_arm_m551": "sheridan",
	"us_proto_mbt70": "mbt70",
	"su_arm_t62": "t62",
	"su_arm_t72": "t72",
	"su_proto_775": "obj775",
}
const MECH_SHAPES := {
	"us_mech_m113": "m113",
	"us_mech_m113tow": "m113tow",
	"us_eng_cev": "m60cev",
	"su_mech_btr60": "btr60",
	"su_mech_bmp1": "bmp1",
	"su_mech_mtlb": "mtlb",
	"su_eng_mtu": "mtu",
}


## Tony: 0 = barwa fabryczna, większe = ciemniejsze, -1 = ciemny metal.
const TONE_BODY := 0.0
const TONE_DARK := 0.3
const TONE_DEEP := 0.55
const TONE_TRACK := 0.5
const TONE_WHEEL := 0.68
const TONE_METAL := -1.0

const TRACK_UV := Vector3(0.6, 1.0, 1.0)
const PLAIN_UV := Vector3(1.0, 1.0, 1.0)
const HULL_UV := Vector3(2.0, 1.0, 1.0)


## Strona jednostki: "us" albo "su".
func _side_of(def_id: String) -> String:
	return "su" if UnitsData.side_of(def_id) == "su" else "us"


func _factory_color(side: String) -> Color:
	return FACTORY_SU if side == "su" else FACTORY_US


func _uniform_color(side: String) -> Color:
	return UNIFORM_SU if side == "su" else UNIFORM_US


func _build_units() -> void:
	unit_nodes = []
	# Pojazdy noszą barwy fabryczne, więc kolor strony jest tylko na pierścieniu
	# na ziemi — inaczej nie dałoby się poznać, kto jest czyj.
	var textures: Dictionary = {
		"uniform": GameTextures.unit("uniform"),
		"armor": GameTextures.unit("armor"),
		"track": GameTextures.unit("track"),
		"star_us": GameTextures.marking("star_us"),
		"star_su": GameTextures.marking("star_su"),
	}
	for unit in sim.units:
		var cls: String = str(unit["cls"])
		var def_id: String = str(unit["def_id"])
		var is_player: bool = bool(unit["is_player"])
		var side: String = _side_of(def_id)
		var ring_color: Color = COLOR_PLAYER if is_player else (COLOR_FRIEND if bool(unit["side"]) else COLOR_ENEMY)
		var node := Node3D.new()
		node.name = "unit_%d" % unit_nodes.size()
		add_child(node)
		if cls == UnitsData.CLS_INFANTRY:
			_build_infantry(node, _uniform_color(side), textures["uniform"])
			_add_side_ring(node, ring_color, 0.8)
		elif cls == UnitsData.CLS_MECH:
			_instantiate_parts(node, _mech_parts(def_id), _factory_color(side), textures)
			_add_side_ring(node, ring_color, 2.0)
		else:
			_instantiate_parts(node, _armor_parts(def_id), _factory_color(side), textures)
			_add_side_ring(node, ring_color, 2.7)
		unit_nodes.append(node)


## Pierścień na ziemi w barwie strony. Pojazdy mają barwy fabryczne, więc
## przynależność jednostki (gracz / sojusznik / wróg) pokazuje ten znacznik.
func _add_side_ring(node: Node3D, color: Color, radius: float) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.02
	mesh.radial_segments = 28
	var ring := MeshInstance3D.new()
	ring.name = "side_ring"
	ring.mesh = mesh
	ring.material_override = _material_ring(color)
	ring.position = Vector3(0.0, 0.05, 0.0)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(ring)


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


## Kula (albo półkula, gdy `hemisphere`): kopuły wież czołgów są odlewane, więc
## półkula daje właściwą sylwetkę, a nie stos walców.
func _part_sphere(radius: float, height: float, segments: int, rings: int, hemisphere: bool,
		pos: Vector3, rot: Vector3, tone: float, tex: String, uv: Vector3 = PLAIN_UV,
		shadow: bool = true) -> Dictionary:
	return {"prim": "sphere", "radius": radius, "height": height, "seg": segments,
		"rings": rings, "hemi": hemisphere, "pos": pos, "rot": rot, "tone": tone,
		"tex": tex, "uv": uv, "shadow": shadow}


## Płytka z oznaczeniem państwowym (gwiazda) — cienka, z przezroczystą teksturą.
func _part_marking(size: Vector3, pos: Vector3, rot: Vector3, key: String) -> Dictionary:
	return {"prim": "box", "size": size, "pos": pos, "rot": rot, "tone": TONE_BODY,
		"tex": key, "uv": PLAIN_UV, "shadow": false, "marking": true}


## Tworzy bryły z opisów. Materiał: barwa fabryczna przyciemniona o `tone`
## (tone < 0 to ciemny metal), a dla oznaczeń państwowych — tekstura gwiazdy
## wycinana kanałem alfa. Bez tekstury oznaczenia bryłę pomijamy, żeby na
## pancerzu nie została biała plama.
func _instantiate_parts(node: Node3D, parts: Array, color: Color, textures: Dictionary) -> void:
	for part in parts:
		var tone: float = float(part["tone"])
		var tex_key: String = str(part["tex"])
		var marking: bool = bool(part.get("marking", false))
		var texture: Texture2D = null
		if tex_key != "" and textures.has(tex_key):
			texture = textures[tex_key]
		if marking and texture == null:
			continue
		var mesh_node := MeshInstance3D.new()
		var prim: String = str(part["prim"])
		if prim == "box":
			var box := BoxMesh.new()
			box.size = part["size"]
			mesh_node.mesh = box
		elif prim == "sphere":
			var sphere := SphereMesh.new()
			sphere.radius = float(part["radius"])
			sphere.height = float(part["height"])
			sphere.radial_segments = int(part["seg"])
			sphere.rings = int(part["rings"])
			sphere.is_hemisphere = bool(part["hemi"])
			mesh_node.mesh = sphere
		else:
			var cyl := CylinderMesh.new()
			cyl.top_radius = float(part["top"])
			cyl.bottom_radius = float(part["bottom"])
			cyl.height = float(part["height"])
			cyl.radial_segments = int(part["seg"])
			mesh_node.mesh = cyl
		var uv_scale: Vector3 = part["uv"]
		if marking:
			mesh_node.material_override = _material_marking(texture)
		else:
			var part_color: Color = METAL_DARK if tone < 0.0 else color.darkened(tone)
			mesh_node.material_override = _material_side(texture, part_color, uv_scale)
		mesh_node.position = part["pos"]
		mesh_node.rotation = part["rot"]
		if not bool(part.get("shadow", true)):
			mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(mesh_node)


# --- podwozia -----------------------------------------------------------------


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


## Koło jezdne: opona, felga, piasta i kołpak (cztery bryły).
func _add_road_wheel(parts: Array, x: float, y: float, z: float, radius: float, width: float) -> void:
	var rot := Vector3(PI * 0.5, 0.0, 0.0)
	parts.append(_part_cyl(radius, radius, width, 16, Vector3(x, y, z), rot, TONE_WHEEL, "track", PLAIN_UV, false))
	parts.append(_part_cyl(radius * 0.62, radius * 0.62, width * 1.08, 16, Vector3(x, y, z), rot, TONE_DEEP, "track", PLAIN_UV, false))
	parts.append(_part_cyl(radius * 0.30, radius * 0.30, width * 1.18, 12, Vector3(x, y, z), rot, TONE_WHEEL, "track", PLAIN_UV, false))
	parts.append(_part_cyl(radius * 0.15, radius * 0.15, width * 1.3, 10, Vector3(x, y, z), rot, TONE_METAL, "", PLAIN_UV, false))


## Pierścień łbów śrub wokół piasty koła.
func _add_hub_bolts(parts: Array, x: float, y: float, z: float, radius: float, count: int) -> void:
	for b in range(count):
		var a: float = TAU * float(b) / float(count)
		parts.append(_part_box(Vector3(0.08, 0.08, 0.1),
			Vector3(x + cos(a) * radius, y + sin(a) * radius, z),
			Vector3(0.0, 0.0, a), TONE_METAL, "", PLAIN_UV, false))


## Koło napędowe: bęben, piasta i zęby wokół obwodu.
func _add_sprocket(parts: Array, x: float, y: float, z: float, radius: float,
		width: float, teeth: int) -> void:
	var rot := Vector3(PI * 0.5, 0.0, 0.0)
	parts.append(_part_cyl(radius * 0.86, radius * 0.86, width * 0.8, 14, Vector3(x, y, z), rot, TONE_WHEEL, "track", PLAIN_UV, false))
	parts.append(_part_cyl(radius * 0.32, radius * 0.32, width * 0.95, 10, Vector3(x, y, z), rot, TONE_METAL, "", PLAIN_UV, false))
	for t in range(teeth):
		var a: float = TAU * float(t) / float(teeth)
		parts.append(_part_box(Vector3(0.11, 0.09, width * 0.86),
			Vector3(x + cos(a) * radius, y + sin(a) * radius, z),
			Vector3(0.0, 0.0, a), TONE_TRACK, "track", PLAIN_UV, false))


## Koło napinające: obręcz, piasta i szprychy.
func _add_idler(parts: Array, x: float, y: float, z: float, radius: float,
		width: float, spokes: int) -> void:
	var rot := Vector3(PI * 0.5, 0.0, 0.0)
	parts.append(_part_cyl(radius, radius, width * 0.72, 14, Vector3(x, y, z), rot, TONE_WHEEL, "track", PLAIN_UV, false))
	parts.append(_part_cyl(radius * 0.28, radius * 0.28, width * 0.9, 10, Vector3(x, y, z), rot, TONE_METAL, "", PLAIN_UV, false))
	for t in range(spokes):
		var a: float = TAU * float(t) / float(spokes)
		parts.append(_part_box(Vector3(radius * 1.15, 0.09, width * 0.5),
			Vector3(x, y, z), Vector3(0.0, 0.0, a), TONE_DEEP, "track", PLAIN_UV, false))


## Rolka podtrzymująca bieg górny: walec i oś.
func _add_roller(parts: Array, x: float, y: float, z: float, wheel_w: float) -> void:
	var rot := Vector3(PI * 0.5, 0.0, 0.0)
	parts.append(_part_cyl(0.13, 0.13, wheel_w * 0.7, 10, Vector3(x, y, z), rot, TONE_DEEP, "track", PLAIN_UV, false))
	parts.append(_part_cyl(0.05, 0.05, wheel_w * 1.05, 8, Vector3(x, y, z), rot, TONE_METAL, "", PLAIN_UV, false))


## Podwozie gąsienicowe jednej strony: koła jezdne z wahaczami i śrubami piast,
## rolki, koło napędowe z zębami i napinające ze szprychami.
##
## `drive_front` mówi, gdzie stoi koło napędowe: M60 ma je z tyłu, a M551, M113
## i BMP-1 z przodu — to jedna z rzeczy, po których poznaje się wóz z daleka.
## `rollers` to liczba rolek podtrzymujących (M113 i MT-LB ich nie mają).
func _add_running_gear(parts: Array, z: float, wheels: int, wheel_r: float, wheel_w: float,
		span: float, front_x: float, rear_x: float, y_bottom: float, y_top: float,
		rollers: int, drive_front: bool, sprocket_r: float, idler_r: float) -> void:
	var rot := Vector3(PI * 0.5, 0.0, 0.0)
	var step: float = 0.0 if wheels <= 1 else span / float(wheels - 1)
	for w in range(wheels):
		var x: float = -span * 0.5 + step * float(w)
		var y: float = y_bottom + wheel_r
		_add_road_wheel(parts, x, y, z, wheel_r, wheel_w)
		_add_hub_bolts(parts, x, y, z + wheel_w * 0.62, wheel_r * 0.44, 6)
		# wahacz zawieszenia w stronę kadłuba
		parts.append(_part_box(Vector3(0.42, 0.14, 0.3), Vector3(x + 0.16, y + 0.12, z * 0.86),
			Vector3(0.0, 0.0, 0.35), TONE_DEEP, "armor", PLAIN_UV, false))
	for r in range(rollers):
		var t: float = 0.5 if rollers <= 1 else float(r) / float(rollers - 1)
		var x: float = -span * 0.42 + span * 0.84 * t
		_add_roller(parts, x, y_top - 0.10, z, wheel_w)
	var y_center: float = (y_bottom + y_top) * 0.5
	var drive_x: float = front_x if drive_front else rear_x
	var idler_x: float = rear_x if drive_front else front_x
	_add_sprocket(parts, drive_x, y_center, z, sprocket_r, wheel_w, 10)
	_add_idler(parts, idler_x, y_center, z, idler_r, wheel_w, 6)
	# mocowania osi kół: dwa wsporniki przy kole napędowym i napinającym
	for x in [drive_x, idler_x]:
		parts.append(_part_box(Vector3(0.3, 0.34, 0.24), Vector3(x, y_center, z * 0.82),
			Vector3.ZERO, TONE_DEEP, "armor", PLAIN_UV, false))
		parts.append(_part_box(Vector3(0.16, 0.16, 0.3), Vector3(x, y_center, z * 0.62),
			Vector3.ZERO, TONE_METAL, "", PLAIN_UV, false))


## Koło nośne wozu kołowego (BTR-60): opona z klockami bieżni, felga, piasta
## i osłona błotnika. `treads` to liczba klocków bieżni na oponie.
func _add_vehicle_wheel(parts: Array, x: float, z: float, radius: float, width: float,
		treads: int) -> void:
	var y: float = radius + 0.04
	var rot := Vector3(PI * 0.5, 0.0, 0.0)
	parts.append(_part_cyl(radius, radius, width, 18, Vector3(x, y, z), rot, TONE_WHEEL, "armor", PLAIN_UV, false))
	parts.append(_part_cyl(radius * 0.58, radius * 0.58, width * 1.1, 14, Vector3(x, y, z), rot, TONE_DEEP, "armor", PLAIN_UV, false))
	parts.append(_part_cyl(radius * 0.26, radius * 0.26, width * 1.2, 10, Vector3(x, y, z), rot, TONE_WHEEL, "armor", PLAIN_UV, false))
	parts.append(_part_cyl(radius * 0.12, radius * 0.12, width * 1.32, 8, Vector3(x, y, z), rot, TONE_METAL, "", PLAIN_UV, false))
	_add_hub_bolts(parts, x, y, z + width * 0.62, radius * 0.4, 5)
	for t in range(treads):
		var a: float = TAU * float(t) / float(treads)
		parts.append(_part_box(Vector3(0.17, 0.1, width * 1.06),
			Vector3(x + cos(a) * radius, y + sin(a) * radius, z),
			Vector3(0.0, 0.0, a), TONE_TRACK, "armor", PLAIN_UV, false))
	# błotnik nad kołem
	parts.append(_part_box(Vector3(radius * 1.75, 0.1, width * 1.25),
		Vector3(x, radius * 2.0 + 0.1, z), Vector3.ZERO, TONE_DEEP, "armor", PLAIN_UV, false))


## Osłona wlotu powietrza / chłodnicy: rama i żaluzje z cienkich brył.
func _add_grille(parts: Array, center: Vector3, w: float, d: float, slats: int) -> void:
	parts.append(_part_box(Vector3(w, 0.08, d), center, Vector3.ZERO, TONE_DEEP, "armor", HULL_UV))
	for i in range(slats):
		var z_off: float = (float(i) - float(slats - 1) * 0.5) * (d / float(slats))
		parts.append(_part_box(Vector3(w * 0.92, 0.05, d * 0.45 / float(slats)),
			center + Vector3(0.0, 0.055, z_off), Vector3.ZERO, TONE_DARK, "armor", PLAIN_UV))


## Rząd łbów śrub albo uchwytów — drobny detal w równym rytmie.
func _add_bolt_row(parts: Array, start: Vector3, step: Vector3, count: int,
		tone: float = TONE_DEEP) -> void:
	for i in range(count):
		parts.append(_part_box(Vector3(0.09, 0.06, 0.09), start + step * float(i),
			Vector3.ZERO, tone, "armor", PLAIN_UV, false))


## Poręcz / reling z segmentów.
func _add_rail(parts: Array, start: Vector3, end: Vector3, segments: int,
		tone: float = TONE_DEEP) -> void:
	for i in range(segments):
		var t0: float = float(i) / float(segments)
		var t1: float = float(i + 1) / float(segments)
		var a: Vector3 = start.lerp(end, t0)
		var b: Vector3 = start.lerp(end, t1)
		var mid: Vector3 = (a + b) * 0.5
		var d: Vector3 = b - a
		parts.append(_part_box(Vector3(maxf(d.length(), 0.08), 0.055, 0.055), mid,
			Vector3(0.0, 0.0, atan2(d.y, d.x)), tone, "armor", PLAIN_UV, false))


## Lina holownicza biegnąca wzdłuż burty — rząd walców.
func _add_cable_run(parts: Array, start: Vector3, end: Vector3, segments: int) -> void:
	for i in range(segments):
		var t0: float = float(i) / float(segments)
		var t1: float = float(i + 1) / float(segments)
		var a: Vector3 = start.lerp(end, t0)
		var b: Vector3 = start.lerp(end, t1)
		var mid: Vector3 = (a + b) * 0.5
		var d: Vector3 = b - a
		parts.append(_part_cyl(0.045, 0.045, d.length(), 6, mid,
			Vector3(0.0, 0.0, atan2(d.y, d.x) - PI * 0.5), TONE_METAL, "", PLAIN_UV, false))
	# oczka na końcach
	parts.append(_part_box(Vector3(0.14, 0.14, 0.08), start, Vector3.ZERO, TONE_METAL, "", PLAIN_UV, false))
	parts.append(_part_box(Vector3(0.14, 0.14, 0.08), end, Vector3.ZERO, TONE_METAL, "", PLAIN_UV, false))


## Kanister na paliwo w koszu: korpus, uchwyt, wieczko.
func _add_jerry_can(parts: Array, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> void:
	parts.append(_part_box(Vector3(0.18, 0.42, 0.32), pos, rot, TONE_DEEP, "armor"))
	parts.append(_part_box(Vector3(0.2, 0.06, 0.1), pos + Vector3(0.0, 0.24, 0.0), rot, TONE_METAL, ""))
	parts.append(_part_box(Vector3(0.1, 0.08, 0.1), pos + Vector3(0.0, 0.24, 0.1), rot, TONE_METAL, ""))


## Skrzynia/bagażnik: korpus i wieko.
func _add_stowage_box(parts: Array, size: Vector3, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> void:
	parts.append(_part_box(size, pos, rot, TONE_DEEP, "armor"))
	parts.append(_part_box(Vector3(size.x * 0.94, size.y * 0.22, size.z * 1.04),
		pos + Vector3(0.0, size.y * 0.58, 0.0), rot, TONE_DARK, "armor"))


## Narzędzia pokładowe łopata, siekiera i kilof w uchwytach.
func _add_tool_row(parts: Array, base: Vector3, rot: Vector3, along_x: bool) -> void:
	var dir := Vector3(0.55, 0.0, 0.0) if along_x else Vector3(0.0, 0.0, 0.55)
	parts.append(_part_cyl(0.035, 0.035, 0.85, 6, base, rot + Vector3(0.0, 0.0, -PI * 0.5), TONE_METAL, "", PLAIN_UV, false))
	parts.append(_part_box(Vector3(0.22, 0.14, 0.05), base + dir, rot, TONE_DEEP, "armor"))
	parts.append(_part_cyl(0.035, 0.035, 0.75, 6, base + Vector3(0.0, -0.06, 0.14), rot + Vector3(0.0, 0.0, -PI * 0.5), TONE_METAL, "", PLAIN_UV, false))
	parts.append(_part_box(Vector3(0.2, 0.1, 0.06), base + dir + Vector3(0.0, -0.06, 0.14), rot, TONE_METAL, ""))


## Wyrzutnie granatów dymnych: płyta nośna i rury.
func _add_smoke_bank(parts: Array, x: float, y: float, z: float, side: float, tubes: int) -> void:
	parts.append(_part_box(Vector3(0.22, 0.18, 0.1), Vector3(x, y, z), Vector3.ZERO, TONE_DEEP, "armor"))
	for i in range(tubes):
		parts.append(_part_cyl(0.06, 0.06, 0.24, 6,
			Vector3(x - float(i) * 0.16, y + 0.1, z + side * 0.09),
			Vector3(0.0, 0.0, -0.5), TONE_DEEP, "armor"))


## Wieżyczka dowódcy: pierścień, właz, podstawa i rkm na obrotnicy.
func _add_cupola(parts: Array, pos: Vector3, radius: float) -> void:
	parts.append(_part_cyl(radius, radius * 1.06, 0.18, 14, pos, Vector3.ZERO, TONE_DEEP, "armor", HULL_UV))
	parts.append(_part_cyl(radius * 0.86, radius * 0.86, 0.12, 12, pos + Vector3(0.0, 0.15, 0.0), Vector3.ZERO, TONE_DARK, "armor"))
	parts.append(_part_box(Vector3(0.34, 0.08, 0.34), pos + Vector3(-0.06, 0.26, 0.0), Vector3.ZERO, TONE_METAL, ""))
	parts.append(_part_box(Vector3(0.2, 0.18, 0.2), pos + Vector3(0.16, 0.3, 0.0), Vector3.ZERO, TONE_DEEP, "armor"))
	parts.append(_part_cyl(0.035, 0.035, 0.62, 6, pos + Vector3(0.52, 0.32, 0.0), Vector3(0.0, 0.0, -PI * 0.5), TONE_METAL, ""))
	parts.append(_part_box(Vector3(0.12, 0.12, 0.1), pos + Vector3(0.28, 0.32, 0.0), Vector3.ZERO, TONE_METAL, ""))


## Antena z podstawą i trzema segmentami.
func _add_antenna(parts: Array, pos: Vector3, height: float) -> void:
	parts.append(_part_cyl(0.06, 0.07, 0.12, 8, pos, Vector3.ZERO, TONE_DEEP, "armor"))
	for i in range(3):
		var seg: float = height * (1.0 - float(i) * 0.18)
		parts.append(_part_cyl(0.022, 0.018, seg, 4,
			pos + Vector3(0.0, 0.12 + seg * 0.5 + height * 0.16 * float(i), 0.0),
			Vector3.ZERO, TONE_METAL, "", PLAIN_UV, false))


## Reflektor z osłoną i uchwytem.
func _add_light(parts: Array, pos: Vector3, side: float, lamp_r: float = 0.13) -> void:
	parts.append(_part_cyl(lamp_r, lamp_r, 0.16, 10, pos, Vector3(0.0, 0.0, -PI * 0.5), TONE_METAL, ""))
	parts.append(_part_box(Vector3(0.1, lamp_r * 2.6, 0.06), pos + Vector3(0.1, 0.0, side * lamp_r * 1.5), Vector3.ZERO, TONE_DEEP, "armor"))
	parts.append(_part_box(Vector3(0.1, lamp_r * 2.6, 0.06), pos + Vector3(0.1, 0.0, -side * lamp_r * 1.5), Vector3.ZERO, TONE_DEEP, "armor"))
	parts.append(_part_box(Vector3(0.12, 0.06, lamp_r * 3.2), pos + Vector3(0.1, lamp_r * 1.4, 0.0), Vector3.ZERO, TONE_DEEP, "armor"))


## Peryskop: obudowa i ciemna szybka.
func _add_periscope(parts: Array, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> void:
	parts.append(_part_box(Vector3(0.18, 0.12, 0.14), pos, rot, TONE_DEEP, "armor"))
	parts.append(_part_box(Vector3(0.14, 0.07, 0.16), pos + Vector3(0.0, 0.075, 0.0), rot, TONE_METAL, ""))


## Pojedyncza gwiazda państwowa: `flat` daje płytkę poziomą (na dach — tak
## malowano je dla identyfikacji z powietrza), inaczej pionową (na burtę).
func _star_plate(key: String, size: float, pos: Vector3, rot: Vector3 = Vector3.ZERO,
		flat: bool = false) -> Dictionary:
	var dim: Vector3 = Vector3(size, 0.03, size) if flat else Vector3(size, size, 0.03)
	return _part_marking(dim, pos, rot, key)
# --- czołgi -------------------------------------------------------------------


## Sylwetka czołgu: 1024 bryły, kształt zależny od jednostki.
func _armor_parts(def_id: String) -> Array:
	var shape: String = str(ARMOR_SHAPES.get(def_id, "m60a1"))
	match shape:
		"sheridan":
			return _sheridan_parts(def_id)
		"mbt70":
			return _mbt70_parts(def_id)
		"t62":
			return _t62_parts(def_id)
		"t72":
			return _t72_parts(def_id)
		"obj775":
			return _obj775_parts(def_id)
		_:
			return _m60a1_parts(def_id, false)


## M60A1 „Patton”: kadłub 6,9 m, sześć kół jezdnych, wysoka wieża odlewana
## z koszem z tyłu, działo 105 mm i reflektor-powietrzny AN/VSS-1 nad lufą.
## Wariant `cev` to M728 CEV: lemiesz spychacza, żuraw ramowy i krótkie działo.
func _m60a1_parts(def_id: String, cev: bool) -> Array:
	var parts: Array = []
	var side: String = _side_of(def_id)
	var star: String = "star_su" if side == "su" else "star_us"
	# kadłub: wanna, burt, pokład, glacis, rufa
	parts.append(_part_box(Vector3(6.5, 0.62, 2.45), Vector3(0.0, 0.80, 0.0), Vector3.ZERO, TONE_DARK, "armor", HULL_UV))
	parts.append(_part_box(Vector3(6.9, 0.55, 2.50), Vector3(0.0, 1.37, 0.0), Vector3.ZERO, TONE_BODY, "armor", HULL_UV))
	parts.append(_part_box(Vector3(6.85, 0.12, 2.56), Vector3(0.0, 1.70, 0.0), Vector3.ZERO, TONE_DARK, "armor", HULL_UV))
	parts.append(_part_box(Vector3(2.3, 0.14, 2.56), Vector3(3.0, 1.32, 0.0), Vector3(0.0, 0.0, -0.62), TONE_BODY, "armor", HULL_UV))
	parts.append(_part_box(Vector3(1.3, 0.55, 2.40), Vector3(3.55, 0.95, 0.0), Vector3.ZERO, TONE_DARK, "armor", HULL_UV))
	parts.append(_part_box(Vector3(1.5, 1.0, 2.45), Vector3(-2.95, 1.25, 0.0), Vector3(0.0, 0.0, 0.5), TONE_DARK, "armor", HULL_UV))
	parts.append(_part_box(Vector3(0.5, 0.7, 2.30), Vector3(-3.45, 1.0, 0.0), Vector3.ZERO, TONE_DEEP, "armor", HULL_UV))
	parts.append(_star_plate(star, 0.8, Vector3(-0.2, 2.72, 0.0), Vector3.ZERO, true))
	for z in [-1.0, 1.0]:
		parts.append(_star_plate(star, 0.55, Vector3(-1.35, 2.05, z * 1.22)))
	parts.append(_star_plate(star, 0.6, Vector3(-3.72, 1.0, 0.0), Vector3(0.0, PI * 0.5, 0.0)))
	# błotniki w segmentach z podporami, kosze boczne
	for s in [-1.0, 1.0]:
		for seg in range(3):
			parts.append(_part_box(Vector3(2.1, 0.10, 0.85),
				Vector3(2.2 - float(seg) * 2.25, 1.46, s * 1.34), Vector3.ZERO, TONE_DARK, "armor", HULL_UV))
		for seg in range(3):
			parts.append(_part_box(Vector3(0.12, 0.3, 0.6),
				Vector3(3.1 - float(seg) * 2.3, 1.26, s * 1.28), Vector3.ZERO, TONE_DEEP, "armor"))
		_add_stowage_box(parts, Vector3(1.2, 0.5, 0.7), Vector3(-2.6, 1.9, s * 0.85))
		_add_stowage_box(parts, Vector3(0.7, 0.45, 0.6), Vector3(-3.3, 1.75, s * 0.8))
	# wloty powietrza, wydech
	for s in [-1.0, 1.0]:
		_add_grille(parts, Vector3(-1.1, 1.79, s * 0.72), 1.7, 1.05, 8)
		parts.append(_part_cyl(0.13, 0.13, 0.5, 10, Vector3(-2.35, 1.55, s * 1.05), Vector3(0.0, 0.0, -PI * 0.5), TONE_METAL, ""))
		parts.append(_part_box(Vector3(0.4, 0.2, 0.34), Vector3(-2.35, 1.68, s * 1.05), Vector3.ZERO, TONE_DEEP, "armor"))
	# włazy kierowcy i mechanika, peryskopy
	parts.append(_part_cyl(0.34, 0.34, 0.12, 12, Vector3(2.35, 1.82, -0.55), Vector3.ZERO, TONE_DEEP, "armor"))
	parts.append(_part_box(Vector3(0.5, 0.08, 0.44), Vector3(2.35, 1.92, -0.55), Vector3.ZERO, TONE_DARK, "armor"))
	_add_periscope(parts, Vector3(2.75, 1.86, -0.55))
	_add_periscope(parts, Vector3(2.75, 1.86, 0.55))
	_add_periscope(parts, Vector3(1.35, 1.86, 0.0))
	# reflektory z osłonami
	for s in [-1.0, 1.0]:
		_add_light(parts, Vector3(3.35, 1.5, s * 0.9), s)
	# narzędzia, liny, kanistry, uchwyty
	for s in [-1.0, 1.0]:
		_add_tool_row(parts, Vector3(0.6, 1.55, s * 1.3), Vector3.ZERO, true)
		_add_cable_run(parts, Vector3(3.3, 1.5, s * 1.32), Vector3(-2.2, 1.5, s * 1.32), 8)
		_add_jerry_can(parts, Vector3(-0.4, 1.78, s * 1.12))
		_add_bolt_row(parts, Vector3(3.1, 1.28, s * 1.4), Vector3(-0.34, 0.0, 0.0), 10)
		_add_bolt_row(parts, Vector3(2.9, 1.14, s * 1.4), Vector3(-0.34, 0.0, 0.0), 9)
	parts.append(_part_box(Vector3(0.22, 0.14, 0.12), Vector3(3.75, 0.85, 1.0), Vector3.ZERO, TONE_METAL, ""))
	parts.append(_part_box(Vector3(0.22, 0.14, 0.12), Vector3(3.75, 0.85, -1.0), Vector3.ZERO, TONE_METAL, ""))
	# wieża: kopuła odlewana z koszem i jarzmem
	parts.append(_part_sphere(1.45, 0.95, 24, 10, true, Vector3(0.0, 1.74, 0.0), Vector3.ZERO, TONE_BODY, "armor", HULL_UV))
	parts.append(_part_cyl(1.5, 1.52, 0.16, 20, Vector3(0.0, 1.76, 0.0), Vector3.ZERO, TONE_DARK, "armor", HULL_UV))
	parts.append(_part_box(Vector3(1.9, 0.6, 2.4), Vector3(-1.35, 2.05, 0.0), Vector3.ZERO, TONE_BODY, "armor", HULL_UV))
	parts.append(_part_box(Vector3(1.2, 0.5, 2.2), Vector3(-2.15, 2.0, 0.0), Vector3(0.0, 0.0, 0.18), TONE_DARK, "armor", HULL_UV))
	parts.append(_part_box(Vector3(0.9, 0.55, 1.6), Vector3(1.15, 2.15, 0.0), Vector3.ZERO, TONE_BODY, "armor", HULL_UV))
	# jarzmo i działo
	parts.append(_part_cyl(0.46, 0.46, 0.7, 16, Vector3(1.45, 2.35, 0.0), Vector3(0.0, 0.0, -PI * 0.5), TONE_BODY, "armor"))
	if cev:
		# M728 CEV: krótkie działo 165 mm, lemiesz i żuraw
		parts.append(_part_cyl(0.22, 0.24, 1.6, 12, Vector3(2.55, 2.35, 0.0), Vector3(0.0, 0.0, -PI * 0.5), TONE_DEEP, "armor"))
		parts.append(_part_cyl(0.16, 0.16, 0.3, 10, Vector3(3.45, 2.35, 0.0), Vector3(0.0, 0.0, -PI * 0.5), TONE_METAL, ""))
		parts.append(_part_box(Vector3(0.5, 0.7, 2.6), Vector3(3.95, 1.15, 0.0), Vector3(0.0, 0.0, -0.35), TONE_DEEP, "armor", HULL_UV))
		parts.append(_part_box(Vector3(0.35, 0.5, 2.6), Vector3(4.25, 0.85, 0.0), Vector3(0.0, 0.0, -0.35), TONE_DARK, "armor"))
		for s in [-1.0, 1.0]:
			parts.append(_part_box(Vector3(1.1, 0.16, 0.16), Vector3(3.6, 1.7, s * 0.9), Vector3(0.0, 0.0, -0.5), TONE_METAL, ""))
		parts.append(_part_cyl(0.06, 0.06, 1.9, 6, Vector3(-0.4, 3.35, 0.0), Vector3(0.0, 0.0, 0.45), TONE_METAL, ""))
		parts.append(_part_cyl(0.05, 0.05, 1.2, 6, Vector3(-1.15, 3.25, 0.0), Vector3.ZERO, TONE_METAL, "", PLAIN_UV, false))
		parts.append(_part_box(Vector3(0.18, 0.18, 0.18), Vector3(-0.75, 4.25, 0.0), Vector3.ZERO, TONE_METAL, ""))
	else:
		parts.append(_part_cyl(0.095, 0.105, 3.9, 14, Vector3(3.75, 2.35, 0.0), Vector3(0.0, 0.0, -PI * 0.5), TONE_DEEP, "armor", Vector3(3.0, 1.0, 1.0)))
		parts.append(_part_cyl(0.13, 0.13, 1.6, 12, Vector3(2.6, 2.35, 0.0), Vector3(0.0, 0.0, -PI * 0.5), TONE_DEEP, "armor"))
		parts.append(_part_cyl(0.12, 0.12, 0.26, 12, Vector3(5.8, 2.35, 0.0), Vector3(0.0, 0.0, -PI * 0.5), TONE_METAL, ""))
		# reflektor AN/VSS-1 nad działem
		parts.append(_part_cyl(0.38, 0.38, 0.5, 16, Vector3(2.5, 2.72, 0.0), Vector3(0.0, 0.0, -PI * 0.5), TONE_DARK, "armor"))
		parts.append(_part_box(Vector3(0.2, 0.5, 0.3), Vector3(2.2, 2.5, 0.0), Vector3.ZERO, TONE_DEEP, "armor"))
		parts.append(_part_box(Vector3(0.34, 0.1, 0.34), Vector3(2.5, 2.98, 0.0), Vector3.ZERO, TONE_METAL, ""))
	# włazy, km dowódcy, wyrzutnie dymne, anteny, poręcze
	_add_cupola(parts, Vector3(-0.35, 2.72, 0.62), 0.42)
	parts.append(_part_cyl(0.36, 0.36, 0.3, 14, Vector3(0.5, 2.72, -0.62), Vector3.ZERO, TONE_DEEP, "armor"))
	parts.append(_part_box(Vector3(0.24, 0.22, 0.24), Vector3(0.5, 2.9, -0.62), Vector3.ZERO, TONE_METAL, ""))
	_add_smoke_bank(parts, 1.0, 2.55, 1.18, 1.0, 3)
	_add_smoke_bank(parts, 1.0, 2.55, -1.18, -1.0, 3)
	for s in [-1.0, 1.0]:
		_add_antenna(parts, Vector3(-1.15, 2.85, s * 0.85), 1.7)
		_add_rail(parts, Vector3(0.9, 2.62, s * 1.28), Vector3(-1.7, 2.5, s * 1.28), 3)
		_add_rail(parts, Vector3(-1.7, 2.5, s * 1.28), Vector3(-2.2, 2.2, s * 1.2), 2)
		for link in range(6):
			parts.append(_part_box(Vector3(0.2, 0.07, 0.56),
				Vector3(0.7 - float(link) * 0.26, 2.42, s * 1.3), Vector3(0.0, 0.0, -0.72),
				TONE_TRACK, "track", TRACK_UV, false))
	# podwozie: sześć kół, trzy rolki, napęd z tyłu
	for s in [-1.0, 1.0]:
		_add_running_gear(parts, s * 1.34, 6, 0.33, 0.6, 3.7, 3.35, -3.35, 0.06, 1.06, 3, false, 0.38, 0.34)
	var per_belt: int = maxi(30, (VEHICLE_PARTS - parts.size() - 24) >> 1)
	for s in [-1.0, 1.0]:
		_add_track_links(parts, per_belt, s * 1.34, 0.6, 3.35, -3.35, 0.06, 1.06)
	return _fit_parts(parts, VEHICLE_PARTS, Vector3(2.2, 1.78, -1.1), Vector3(-0.24, 0.075, 0.0), "links")


## M551 Sheridan: lekki czołg powietrznodesantowy — niska sylwetka, pięć dużych
## kół, napęd z przodu i grube działo 152 mm z przedmuchiwaczem.
func _sheridan_parts(def_id: String) -> Array:
	var parts: Array = []
	var side: String = _side_of(def_id)
	var star: String = "star_su" if side == "su" else "star_us"
	parts.append(_part_box(Vector3(5.7, 0.5, 2.3), Vector3(0.0, 0.70, 0.0), Vector3.ZERO, TONE_DARK, "armor", HULL_UV))
	parts.append(_part_box(Vector3(6.1, 0.55, 2.35), Vector3(0.0, 1.22, 0.0), Vector3.ZERO, TONE_BODY, "armor", HULL_UV))
	parts.append(_part_box(Vector3(6.0, 0.12, 2.4), Vector3(0.0, 1.55, 0.0), Vector3.ZERO, TONE_DARK, "armor", HULL_UV))
	parts.append(_part_box(Vector3(2.5, 0.12, 2.4), Vector3(2.45, 1.15, 0.0), Vector3(0.0, 0.0, -0.85), TONE_BODY, "armor", HULL_UV))
	parts.append(_part_box(Vector3(0.9, 0.5, 2.3), Vector3(2.9, 0.85, 0.0), Vector3(0.0, 0.0, -0.3), TONE_DARK, "armor", HULL_UV))
	parts.append(_part_box(Vector3(1.2, 0.9, 2.3), Vector3(-2.7, 1.10, 0.0), Vector3(0.0, 0.0, 0.5), TONE_DARK, "armor", HULL_UV))
	parts.append(_star_plate(star, 0.7, Vector3(0.0, 2.44, 0.0), Vector3.ZERO, true))
	for z in [-1.0, 1.0]:
		parts.append(_star_plate(star, 0.45, Vector3(-0.9, 1.9, z * 1.14)))
	# falochron, błotniki, skrzynie
	parts.append(_part_box(Vector3(1.7, 0.1, 2.35), Vector3(3.15, 1.32, 0.0), Vector3(0.0, 0.0, -0.45), TONE_BODY, "armor", HULL_UV))
	for s in [-1.0, 1.0]:
		for seg in range(3):
			parts.append(_part_box(Vector3(1.85, 0.10, 0.8),
				Vector3(1.95 - float(seg) * 1.95, 1.3, s * 1.22), Vector3.ZERO, TONE_DARK, "armor", HULL_UV))
		_add_stowage_box(parts, Vector3(0.7, 0.4, 0.6), Vector3(-2.3, 1.6, s * 0.8))
		_add_bolt_row(parts, Vector3(2.6, 1.16, s * 1.28), Vector3(-0.32, 0.0, 0.0), 8)
		_add_cable_run(parts, Vector3(2.7, 1.35, s * 1.26), Vector3(-1.6, 1.35, s * 1.26), 7)
		_add_tool_row(parts, Vector3(0.2, 1.45, s * 1.2), Vector3.ZERO, true)
	_add_grille(parts, Vector3(-1.4, 1.64, 0.62), 1.3, 0.95, 7)
	_add_grille(parts, Vector3(-1.4, 1.64, -0.62), 1.3, 0.95, 7)
	parts.append(_part_cyl(0.12, 0.12, 0.42, 10, Vector3(-2.25, 1.5, 0.95), Vector3(0.0, 0.0, -PI * 0.5), TONE_METAL, ""))
	parts.append(_part_cyl(0.12, 0.12, 0.42, 10, Vector3(-2.25, 1.5, -0.95), Vector3(0.0, 0.0, -PI * 0.5), TONE_METAL, ""))
	_add_periscope(parts, Vector3(2.65, 1.72, -0.5))
	_add_periscope(parts, Vector3(2.65, 1.72, 0.5))
	for s in [-1.0, 1.0]:
		_add_light(parts, Vector3(3.1, 0.9, s * 1.0), s, 0.12)
	# wieża odlewana, działo 152 mm
	parts.append(_part_sphere(1.3, 0.8, 24, 10, true, Vector3(0.0, 1.62, 0.0), Vector3.ZERO, TONE_BODY, "armor", HULL_UV))
	parts.append(_part_cyl(1.34, 1.36, 0.14, 18, Vector3(0.0, 1.63, 0.0), Vector3.ZERO, TONE_DARK, "armor", HULL_UV))
	parts.append(_part_cyl(0.42, 0.42, 0.6, 16, Vector3(1.25, 2.15, 0.0), Vector3(0.0, 0.0, -PI * 0.5), TONE_BODY, "armor"))
	parts.append(_part_cyl(0.13, 0.14, 3.0, 14, Vector3(3.05, 2.15, 0.0), Vector3(0.0, 0.0, -PI * 0.5), TONE_DEEP, "armor", Vector3(2.5, 1.0, 1.0)))
	parts.append(_part_cyl(0.21, 0.21, 0.7, 14, Vector3(3.4, 2.15, 0.0), Vector3(0.0, 0.0, -PI * 0.5), TONE_DEEP, "armor"))
	parts.append(_part_cyl(0.16, 0.16, 0.3, 12, Vector3(4.6, 2.15, 0.0), Vector3(0.0, 0.0, -PI * 0.5), TONE_METAL, ""))
	_add_cupola(parts, Vector3(-0.35, 2.32, 0.55), 0.34)
	parts.append(_part_cyl(0.34, 0.34, 0.28, 14, Vector3(0.45, 2.28, -0.55), Vector3.ZERO, TONE_DEEP, "armor"))
	parts.append(_part_box(Vector3(0.28, 0.24, 0.26), Vector3(0.45, 2.46, -0.55), Vector3.ZERO, TONE_METAL, ""))
	_add_smoke_bank(parts, 0.75, 2.32, 1.02, 1.0, 3)
	_add_smoke_bank(parts, 0.75, 2.32, -1.02, -1.0, 3)
	for s in [-1.0, 1.0]:
		_add_antenna(parts, Vector3(-0.9, 2.45, s * 0.7), 1.5)
		_add_rail(parts, Vector3(0.7, 2.32, s * 1.1), Vector3(-1.3, 2.22, s * 1.1), 3)
		for link in range(5):
			parts.append(_part_box(Vector3(0.2, 0.07, 0.5),
				Vector3(0.5 - float(link) * 0.24, 2.26, s * 1.14), Vector3(0.0, 0.0, -0.72),
				TONE_TRACK, "track", TRACK_UV, false))
	# podwozie: pięć kół, napęd z przodu
	for s in [-1.0, 1.0]:
		_add_running_gear(parts, s * 1.22, 5, 0.34, 0.55, 3.2, 2.95, -2.95, 0.06, 0.92, 3, true, 0.36, 0.32)
	var per_belt: int = maxi(30, (VEHICLE_PARTS - parts.size() - 24) >> 1)
	for s in [-1.0, 1.0]:
		_add_track_links(parts, per_belt, s * 1.22, 0.55, 2.95, -2.95, 0.06, 0.92)
	return _fit_parts(parts, VEHICLE_PARTS, Vector3(2.3, 1.6, -1.0), Vector3(-0.22, 0.07, 0.0), "links")


## MBT-70 (KPz 70): wspólny projekt USA i RFN z lat 60. — kadłub 7,2 m, siedem
## kół, napęd z tyłu, a nad nim ogromna płaska wieża szersza od kadłuba z
## działem 152 mm i zdalnym działkiem 20 mm w kopułce dowódcy.
func _mbt70_parts(def_id: String) -> Array:
	var parts: Array = []
	var side: String = _side_of(def_id)
	var star: String = "star_su" if side == "su" else "star_us"
	# kadłub: bardzo niski, szeroki, ze spadzistym glacis
	parts.append(_part_box(Vector3(6.4, 0.55, 2.7), Vector3(0.0, 0.72, 0.0), Vector3.ZERO, TONE_DARK, "armor", HULL_UV))
	parts.append(_part_box(Vector3(6.8, 0.5, 2.78), Vector3(0.0, 1.18, 0.0), Vector3.ZERO, TONE_BODY, "armor", HULL_UV))
	parts.append(_part_box(Vector3(6.7, 0.12, 2.84), Vector3(0.0, 1.48, 0.0), Vector3.ZERO, TONE_DARK, "armor", HULL_UV))
	parts.append(_part_box(Vector3(2.2, 0.14, 2.84), Vector3(3.15, 1.12, 0.0), Vector3(0.0, 0.0, -0.5), TONE_BODY, "armor", HULL_UV))
	parts.append(_part_box(Vector3(1.1, 0.5, 2.7), Vector3(3.65, 0.85, 0.0), Vector3.ZERO, TONE_DARK, "armor", HULL_UV))
	parts.append(_part_box(Vector3(1.3, 0.85, 2.7), Vector3(-3.15, 1.05, 0.0), Vector3(0.0, 0.0, 0.45), TONE_DARK, "armor", HULL_UV))
	parts.append(_star_plate(star, 0.75, Vector3(-1.2, 2.28, 0.0), Vector3.ZERO, true))
	for z in [-1.0, 1.0]:
		parts.append(_star_plate(star, 0.5, Vector3(-2.2, 1.35, z * 1.36)))
	parts.append(_star_plate(star, 0.55, Vector3(-3.85, 1.05, 0.0), Vector3(0.0, PI * 0.5, 0.0)))
	# fartuchy boczne nad siedmioma kołami, błotniki
	for s in [-1.0, 1.0]:
		for seg in range(4):
			parts.append(_part_box(Vector3(1.65, 0.32, 0.14),
				Vector3(2.5 - float(seg) * 1.7, 1.28, s * 1.52), Vector3.ZERO, TONE_DEEP, "armor", HULL_UV))
		for seg in range(3):
			parts.append(_part_box(Vector3(2.2, 0.10, 0.8), Vector3(2.2 - float(seg) * 2.25, 1.5, s * 1.5), Vector3.ZERO, TONE_DARK, "armor", HULL_UV))
		_add_stowage_box(parts, Vector3(1.0, 0.5, 0.72), Vector3(-2.2, 1.85, s * 1.02))
		_add_bolt_row(parts, Vector3(3.0, 1.16, s * 1.6), Vector3(-0.34, 0.0, 0.0), 10)
		_add_cable_run(parts, Vector3(3.2, 1.42, s * 1.58), Vector3(-2.4, 1.42, s * 1.58), 8)
		_add_tool_row(parts, Vector3(0.4, 1.5, s * 1.5), Vector3.ZERO, true)
	for s in [-1.0, 1.0]:
		_add_grille(parts, Vector3(-1.5, 1.57, s * 0.78), 1.6, 1.1, 8)
		parts.append(_part_cyl(0.15, 0.15, 0.55, 10, Vector3(-2.75, 1.5, s * 1.1), Vector3(0.0, 0.0, -PI * 0.5), TONE_METAL, ""))
		parts.append(_part_box(Vector3(0.45, 0.22, 0.38), Vector3(-2.75, 1.66, s * 1.1), Vector3.ZERO, TONE_DEEP, "armor"))
	_add_periscope(parts, Vector3(2.9, 1.6, -0.6))
	_add_periscope(parts, Vector3(2.9, 1.6, 0.6))
	for s in [-1.0, 1.0]:
		_add_light(parts, Vector3(3.55, 1.25, s * 1.05), s)
	# wieża: szeroki, płaski blok o pochylonych burtach (znak rozpoznawczy MBT-70)
	parts.append(_part_box(Vector3(3.4, 0.95, 3.1), Vector3(0.25, 1.95, 0.0), Vector3.ZERO, TONE_BODY, "armor", HULL_UV))
	parts.append(_part_box(Vector3(3.2, 0.2, 3.18), Vector3(0.25, 2.5, 0.0), Vector3.ZERO, TONE_DARK, "armor", HULL_UV))
	for s in [-1.0, 1.0]:
		parts.append(_part_box(Vector3(3.3, 0.85, 0.22), Vector3(0.25, 1.98, s * 1.62), Vector3.ZERO, TONE_BODY, "armor", HULL_UV))
		parts.append(_part_box(Vector3(1.15, 0.42, 0.24), Vector3(0.35, 2.05, s * 1.72), Vector3.ZERO, TONE_DEEP, "armor"))
	parts.append(_part_box(Vector3(0.9, 0.85, 2.9), Vector3(2.05, 1.98, 0.0), Vector3(0.0, 0.0, -0.28), TONE_BODY, "armor", HULL_UV))
	parts.append(_part_box(Vector3(1.5, 0.75, 2.85), Vector3(-1.55, 1.92, 0.0), Vector3(0.0, 0.0, 0.12), TONE_DARK, "armor", HULL_UV))
	# jarzmo i działo 152 mm z przedmuchiwaczem
	parts.append(_part_cyl(0.5, 0.5, 0.8, 16, Vector3(2.15, 2.15, 0.0), Vector3(0.0, 0.0, -PI * 0.5), TONE_BODY, "armor"))
	parts.append(_part_cyl(0.13, 0.15, 3.9, 14, Vector3(4.5, 2.15, 0.0), Vector3(0.0, 0.0, -PI * 0.5), TONE_DEEP, "armor", Vector3(3.0, 1.0, 1.0)))
	parts.append(_part_cyl(0.19, 0.19, 1.1, 12, Vector3(3.85, 2.15, 0.0), Vector3(0.0, 0.0, -PI * 0.5), TONE_DEEP, "armor"))
	parts.append(_part_cyl(0.16, 0.16, 0.32, 12, Vector3(6.55, 2.15, 0.0), Vector3(0.0, 0.0, -PI * 0.5), TONE_METAL, ""))
	parts.append(_part_box(Vector3(0.55, 0.45, 0.55), Vector3(2.55, 2.15, 0.0), Vector3.ZERO, TONE_DARK, "armor"))
	# kopułka dowódcy z działkiem 20 mm (zdalnie sterowane)
	_add_cupola(parts, Vector3(-0.85, 2.55, 0.95), 0.45)
	parts.append(_part_box(Vector3(0.55, 0.42, 0.55), Vector3(-0.55, 2.85, 0.95), Vector3.ZERO, TONE_DEEP, "armor"))
	parts.append(_part_cyl(0.06, 0.07, 1.35, 8, Vector3(0.35, 2.95, 0.95), Vector3(0.0, 0.0, -PI * 0.5), TONE_METAL, ""))
	parts.append(_part_box(Vector3(0.3, 0.24, 0.3), Vector3(-0.25, 2.95, 0.95), Vector3.ZERO, TONE_METAL, ""))
	parts.append(_part_cyl(0.4, 0.4, 0.3, 14, Vector3(-0.55, 2.55, -0.95), Vector3.ZERO, TONE_DEEP, "armor"))
	parts.append(_part_box(Vector3(0.3, 0.24, 0.3), Vector3(-0.55, 2.73, -0.95), Vector3.ZERO, TONE_METAL, ""))
	_add_smoke_bank(parts, 1.35, 2.42, 1.32, 1.0, 3)
	_add_smoke_bank(parts, 1.35, 2.42, -1.32, -1.0, 3)
	for s in [-1.0, 1.0]:
		_add_antenna(parts, Vector3(-1.75, 2.45, s * 1.15), 1.6)
		_add_rail(parts, Vector3(1.7, 2.55, s * 1.66), Vector3(-1.2, 2.55, s * 1.66), 3)
		for link in range(6):
			parts.append(_part_box(Vector3(0.2, 0.07, 0.56),
				Vector3(-0.2 - float(link) * 0.26, 2.3, s * 1.66), Vector3(0.0, 0.0, -0.72),
				TONE_TRACK, "track", TRACK_UV, false))
	# podwozie: siedem kół, napęd z tyłu, zawieszenie hydropneumatyczne
	for s in [-1.0, 1.0]:
		_add_running_gear(parts, s * 1.5, 7, 0.31, 0.58, 4.1, 3.55, -3.55, 0.06, 1.02, 3, false, 0.36, 0.32)
	var per_belt: int = maxi(30, (VEHICLE_PARTS - parts.size() - 24) >> 1)
	for s in [-1.0, 1.0]:
		_add_track_links(parts, per_belt, s * 1.5, 0.58, 3.55, -3.55, 0.06, 1.02)
	return _fit_parts(parts, VEHICLE_PARTS, Vector3(2.2, 1.6, -1.2), Vector3(-0.24, 0.075, 0.0), "links")
## T-62 Obr. 1972: kadłub 6,6 m, pięć kół rozstawionych równo (po tym odróżnia
## się od T-55 z przerwą między pierwszą a drugą parą), wydłużona odlewana
## wieża, działo gładkolufowe 115 mm bez hamulca wylotowego i rura do brodzenia
## (OPVT) na dachu — dodatek z modernizacji 1972 roku.
func _t62_parts(def_id: String) -> Array:
	var parts: Array = []
	var side: String = _side_of(def_id)
	var star: String = "star_su" if side == "su" else "star_us"
	parts.append(_part_box(Vector3(6.1, 0.6, 2.45), Vector3(0.0, 0.72, 0.0), Vector3.ZERO, TONE_DARK, "armor", HULL_UV))
	parts.append(_part_box(Vector3(6.4, 0.5, 2.50), Vector3(0.0, 1.28, 0.0), Vector3.ZERO, TONE_BODY, "armor", HULL_UV))
	parts.append(_part_box(Vector3(6.3, 0.12, 2.55), Vector3(0.0, 1.60, 0.0), Vector3.ZERO, TONE_DARK, "armor", HULL_UV))
	parts.append(_part_box(Vector3(2.0, 0.13, 2.55), Vector3(2.85, 1.22, 0.0), Vector3(0.0, 0.0, -0.95), TONE_BODY, "armor", HULL_UV))
	parts.append(_part_box(Vector3(0.9, 0.5, 2.45), Vector3(3.2, 0.72, 0.0), Vector3(0.0, 0.0, -0.25), TONE_DARK, "armor", HULL_UV))
	parts.append(_part_box(Vector3(1.3, 1.0, 2.45), Vector3(-3.0, 1.10, 0.0), Vector3(0.0, 0.0, 0.55), TONE_DARK, "armor", HULL_UV))
	parts.append(_star_plate(star, 0.7, Vector3(0.2, 2.56, 0.0), Vector3.ZERO, true))
	for z in [-1.0, 1.0]:
		parts.append(_star_plate(star, 0.45, Vector3(-2.2, 1.35, z * 1.29)))
	parts.append(_star_plate(star, 0.5, Vector3(-3.72, 1.1, 0.0), Vector3(0.0, PI * 0.5, 0.0)))
	# błotniki, fartuchy, beczki paliwa z pasami
	for s in [-1.0, 1.0]:
		for seg in range(3):
			parts.append(_part_box(Vector3(2.05, 0.10, 0.7), Vector3(2.1 - float(seg) * 2.15, 1.32, s * 1.26), Vector3.ZERO, TONE_DARK, "armor", HULL_UV))
		parts.append(_part_box(Vector3(0.9, 0.42, 0.13), Vector3(2.55, 1.08, s * 1.26), Vector3.ZERO, TONE_DEEP, "armor"))
		parts.append(_part_box(Vector3(0.8, 0.4, 0.13), Vector3(-2.7, 1.08, s * 1.26), Vector3.ZERO, TONE_DEEP, "armor"))
		parts.append(_part_cyl(0.30, 0.30, 1.0, 14, Vector3(-3.55, 1.55, s * 0.6), Vector3(0.0, 0.0, -PI * 0.5), TONE_WHEEL, "armor", Vector3(1.5, 1.0, 1.0)))
		parts.append(_part_box(Vector3(0.1, 0.12, 0.66), Vector3(-3.55, 1.82, s * 0.6), Vector3.ZERO, TONE_METAL, ""))
		parts.append(_part_box(Vector3(0.22, 0.12, 0.1), Vector3(-3.55, 1.55, s * 1.12), Vector3.ZERO, TONE_METAL, ""))
		_add_bolt_row(parts, Vector3(3.0, 1.12, s * 1.32), Vector3(-0.32, 0.0, 0.0), 9)
		_add_cable_run(parts, Vector3(2.9, 1.4, s * 1.3), Vector3(-1.8, 1.4, s * 1.3), 7)
		_add_tool_row(parts, Vector3(0.3, 1.42, s * 1.26), Vector3.ZERO, true)
	for s in [-1.0, 1.0]:
		_add_grille(parts, Vector3(-1.35, 1.69, s * 0.7), 1.5, 1.0, 8)
		parts.append(_part_cyl(0.11, 0.11, 0.45, 10, Vector3(-2.4, 1.3, s * 1.12), Vector3(0.0, 0.0, -PI * 0.5), TONE_METAL, ""))
		parts.append(_part_box(Vector3(0.65, 0.18, 0.24), Vector3(-2.4, 1.42, s * 1.12), Vector3.ZERO, TONE_DEEP, "armor"))
	_add_periscope(parts, Vector3(2.95, 1.68, -0.55))
	_add_periscope(parts, Vector3(2.95, 1.68, 0.55))
	for s in [-1.0, 1.0]:
		_add_light(parts, Vector3(3.15, 1.4, s * 0.85), s)
	# wieża: wydłużona odlewana kopuła, jarzmo i działo 115 mm (bez hamulca)
	parts.append(_part_sphere(1.16, 0.92, 24, 10, true, Vector3(0.0, 1.62, 0.0), Vector3.ZERO, TONE_BODY, "armor", HULL_UV))
	parts.append(_part_sphere(1.05, 0.7, 20, 8, true, Vector3(-0.75, 1.62, 0.0), Vector3.ZERO, TONE_BODY, "armor", HULL_UV))
	parts.append(_part_cyl(1.24, 1.26, 0.15, 18, Vector3(0.0, 1.63, 0.0), Vector3.ZERO, TONE_DARK, "armor", HULL_UV))
	parts.append(_part_cyl(0.42, 0.42, 0.75, 16, Vector3(1.15, 2.08, 0.0), Vector3(0.0, 0.0, -PI * 0.5), TONE_BODY, "armor"))
	parts.append(_part_cyl(0.10, 0.11, 3.5, 14, Vector3(3.15, 2.08, 0.0), Vector3(0.0, 0.0, -PI * 0.5), TONE_DEEP, "armor", Vector3(3.0, 1.0, 1.0)))
	parts.append(_part_cyl(0.145, 0.145, 1.3, 12, Vector3(2.6, 2.08, 0.0), Vector3(0.0, 0.0, -PI * 0.5), TONE_DEEP, "armor"))
	parts.append(_part_cyl(0.125, 0.125, 0.28, 12, Vector3(4.95, 2.08, 0.0), Vector3(0.0, 0.0, -PI * 0.5), TONE_METAL, ""))
	# rura do brodzenia OPVT (modernizacja 1972) na prawej burcie wieży
	parts.append(_part_cyl(0.14, 0.14, 1.6, 10, Vector3(-0.2, 2.35, 1.02), Vector3(0.0, 0.0, -PI * 0.5), TONE_DEEP, "armor"))
	parts.append(_part_cyl(0.12, 0.12, 0.5, 10, Vector3(-1.15, 2.35, 1.02), Vector3(0.0, 0.0, -PI * 0.5), TONE_DEEP, "armor"))
	parts.append(_part_box(Vector3(1.2, 0.12, 0.16), Vector3(-0.2, 2.2, 1.02), Vector3.ZERO, TONE_DEEP, "armor"))
	_add_cupola(parts, Vector3(0.32, 2.42, 0.5), 0.32)
	parts.append(_part_cyl(0.28, 0.28, 0.22, 14, Vector3(-0.32, 2.42, -0.5), Vector3.ZERO, TONE_DEEP, "armor"))
	parts.append(_part_box(Vector3(0.3, 0.24, 0.26), Vector3(-0.45, 2.6, -0.4), Vector3.ZERO, TONE_METAL, ""))
	_add_smoke_bank(parts, 0.85, 2.3, 0.95, 1.0, 3)
	_add_smoke_bank(parts, 0.85, 2.3, -0.95, -1.0, 3)
	for s in [-1.0, 1.0]:
		_add_antenna(parts, Vector3(-0.85, 2.62, s * 0.75), 1.6)
		_add_rail(parts, Vector3(0.95, 2.36, s * 1.12), Vector3(-1.25, 2.26, s * 1.12), 3)
		for link in range(5):
			parts.append(_part_box(Vector3(0.2, 0.07, 0.52),
				Vector3(0.15 - float(link) * 0.25, 2.22, s * 1.16), Vector3(0.0, 0.0, -0.72),
				TONE_TRACK, "track", TRACK_UV, false))
	# podwozie: pięć kół równo rozstawionych, napęd z tyłu
	for s in [-1.0, 1.0]:
		_add_running_gear(parts, s * 1.26, 5, 0.40, 0.58, 3.3, 3.15, -3.15, 0.04, 1.0, 3, false, 0.38, 0.36)
	var per_belt: int = maxi(30, (VEHICLE_PARTS - parts.size() - 24) >> 1)
	for s in [-1.0, 1.0]:
		_add_track_links(parts, per_belt, s * 1.26, 0.58, 3.15, -3.15, 0.04, 1.0)
	return _fit_parts(parts, VEHICLE_PARTS, Vector3(2.35, 1.68, -1.05), Vector3(-0.24, 0.07, 0.0), "links")


## T-72 „Ural”: kadłub 6,9 m, sześć kół, bardzo niska kopuła z klinami pancerza,
## działo 125 mm z koszulką termiczną i rura do brodzenia na tyle wieży.
func _t72_parts(def_id: String) -> Array:
	var parts: Array = []
	var side: String = _side_of(def_id)
	var star: String = "star_su" if side == "su" else "star_us"
	parts.append(_part_box(Vector3(6.5, 0.6, 2.5), Vector3(0.0, 0.72, 0.0), Vector3.ZERO, TONE_DARK, "armor", HULL_UV))
	parts.append(_part_box(Vector3(6.9, 0.5, 2.55), Vector3(0.0, 1.28, 0.0), Vector3.ZERO, TONE_BODY, "armor", HULL_UV))
	parts.append(_part_box(Vector3(6.8, 0.12, 2.6), Vector3(0.0, 1.60, 0.0), Vector3.ZERO, TONE_DARK, "armor", HULL_UV))
	parts.append(_part_box(Vector3(2.6, 0.13, 2.6), Vector3(3.0, 1.2, 0.0), Vector3(0.0, 0.0, -0.72), TONE_BODY, "armor", HULL_UV))
	parts.append(_part_box(Vector3(1.0, 0.5, 2.5), Vector3(3.5, 0.8, 0.0), Vector3(0.0, 0.0, -0.2), TONE_DARK, "armor", HULL_UV))
	parts.append(_part_box(Vector3(1.4, 1.0, 2.5), Vector3(-3.0, 1.10, 0.0), Vector3(0.0, 0.0, 0.5), TONE_DARK, "armor", HULL_UV))
	parts.append(_star_plate(star, 0.7, Vector3(0.0, 2.32, 0.0), Vector3.ZERO, true))
	for z in [-1.0, 1.0]:
		parts.append(_star_plate(star, 0.45, Vector3(-2.0, 1.35, z * 1.31)))
	parts.append(_star_plate(star, 0.5, Vector3(-3.82, 1.1, 0.0), Vector3(0.0, PI * 0.5, 0.0)))
	# fartuchy gumowe w panelach, błotniki, beczki
	for s in [-1.0, 1.0]:
		for seg in range(4):
			parts.append(_part_box(Vector3(1.62, 0.34, 0.13),
				Vector3(2.4 - float(seg) * 1.66, 1.16, s * 1.34), Vector3.ZERO, TONE_DEEP, "armor", HULL_UV))
		for seg in range(3):
			parts.append(_part_box(Vector3(2.15, 0.10, 0.75), Vector3(2.1 - float(seg) * 2.2, 1.32, s * 1.3), Vector3.ZERO, TONE_DARK, "armor", HULL_UV))
		parts.append(_part_cyl(0.30, 0.30, 1.0, 14, Vector3(-3.75, 1.55, s * 0.6), Vector3(0.0, 0.0, -PI * 0.5), TONE_WHEEL, "armor", Vector3(1.5, 1.0, 1.0)))
		parts.append(_part_box(Vector3(0.1, 0.12, 0.66), Vector3(-3.75, 1.82, s * 0.6), Vector3.ZERO, TONE_METAL, ""))
		parts.append(_part_box(Vector3(1.0, 0.45, 0.13), Vector3(2.7, 1.06, s * 1.3), Vector3.ZERO, TONE_DEEP, "armor"))
		parts.append(_part_box(Vector3(0.9, 0.45, 0.13), Vector3(-3.0, 1.06, s * 1.3), Vector3.ZERO, TONE_DEEP, "armor"))
		_add_bolt_row(parts, Vector3(3.1, 1.06, s * 1.42), Vector3(-0.34, 0.0, 0.0), 10)
		_add_cable_run(parts, Vector3(3.1, 1.38, s * 1.38), Vector3(-1.9, 1.38, s * 1.38), 8)
		_add_tool_row(parts, Vector3(0.5, 1.4, s * 1.3), Vector3.ZERO, true)
	for s in [-1.0, 1.0]:
		_add_grille(parts, Vector3(-1.3, 1.69, s * 0.72), 1.55, 1.05, 8)
	# wydech na lewym błotniku tylnym
	parts.append(_part_cyl(0.13, 0.13, 0.6, 10, Vector3(-2.45, 1.28, 1.38), Vector3(0.0, 0.0, -PI * 0.5), TONE_METAL, ""))
	parts.append(_part_box(Vector3(0.7, 0.2, 0.3), Vector3(-2.45, 1.38, 1.38), Vector3.ZERO, TONE_DEEP, "armor"))
	_add_periscope(parts, Vector3(3.05, 1.66, -0.55))
	_add_periscope(parts, Vector3(3.05, 1.66, 0.55))
	for s in [-1.0, 1.0]:
		_add_light(parts, Vector3(3.25, 1.4, s * 0.85), s)
	# wieża: niska kopuła z klinami, działo 125 mm, rura do brodzenia
	parts.append(_part_sphere(1.28, 0.78, 24, 10, true, Vector3(0.0, 1.52, 0.0), Vector3.ZERO, TONE_BODY, "armor", HULL_UV))
	parts.append(_part_cyl(1.32, 1.34, 0.15, 18, Vector3(0.0, 1.53, 0.0), Vector3.ZERO, TONE_DARK, "armor", HULL_UV))
	for s in [-1.0, 1.0]:
		parts.append(_part_box(Vector3(0.9, 0.5, 0.55), Vector3(0.55, 1.72, s * 0.72), Vector3(0.0, 0.0, -0.35), TONE_BODY, "armor", HULL_UV))
	parts.append(_part_cyl(0.44, 0.44, 0.7, 16, Vector3(1.3, 1.95, 0.0), Vector3(0.0, 0.0, -PI * 0.5), TONE_BODY, "armor"))
	parts.append(_part_cyl(0.11, 0.12, 4.0, 14, Vector3(3.5, 1.95, 0.0), Vector3(0.0, 0.0, -PI * 0.5), TONE_DEEP, "armor", Vector3(3.0, 1.0, 1.0)))
	parts.append(_part_cyl(0.15, 0.15, 1.2, 12, Vector3(2.6, 1.95, 0.0), Vector3(0.0, 0.0, -PI * 0.5), TONE_DEEP, "armor"))
	parts.append(_part_cyl(0.19, 0.19, 0.6, 12, Vector3(4.6, 1.95, 0.0), Vector3(0.0, 0.0, -PI * 0.5), TONE_DEEP, "armor"))
	parts.append(_part_cyl(0.13, 0.13, 0.3, 12, Vector3(5.5, 1.95, 0.0), Vector3(0.0, 0.0, -PI * 0.5), TONE_METAL, ""))
	parts.append(_part_cyl(0.15, 0.15, 1.3, 10, Vector3(-1.5, 2.05, 0.0), Vector3(0.0, 0.0, -PI * 0.5), TONE_DEEP, "armor"))
	parts.append(_part_box(Vector3(1.0, 0.12, 0.18), Vector3(-1.5, 1.9, 0.0), Vector3.ZERO, TONE_DEEP, "armor"))
	_add_cupola(parts, Vector3(-0.3, 2.22, 0.5), 0.32)
	parts.append(_part_cyl(0.28, 0.28, 0.22, 14, Vector3(0.35, 2.2, -0.5), Vector3.ZERO, TONE_DEEP, "armor"))
	parts.append(_part_box(Vector3(0.3, 0.24, 0.26), Vector3(0.35, 2.38, -0.5), Vector3.ZERO, TONE_METAL, ""))
	_add_smoke_bank(parts, 0.9, 1.95, 1.0, 1.0, 3)
	_add_smoke_bank(parts, 0.9, 1.95, -1.0, -1.0, 3)
	for s in [-1.0, 1.0]:
		_add_antenna(parts, Vector3(-0.8, 2.42, s * 0.8), 1.7)
		_add_rail(parts, Vector3(1.05, 2.12, s * 1.16), Vector3(-1.15, 2.06, s * 1.16), 3)
		for link in range(5):
			parts.append(_part_box(Vector3(0.2, 0.07, 0.54),
				Vector3(0.3 - float(link) * 0.25, 2.02, s * 1.2), Vector3(0.0, 0.0, -0.72),
				TONE_TRACK, "track", TRACK_UV, false))
	# podwozie: sześć kół, napęd z tyłu
	for s in [-1.0, 1.0]:
		_add_running_gear(parts, s * 1.3, 6, 0.375, 0.58, 3.5, 3.2, -3.3, 0.04, 1.0, 3, false, 0.40, 0.34)
	var per_belt: int = maxi(30, (VEHICLE_PARTS - parts.size() - 24) >> 1)
	for s in [-1.0, 1.0]:
		_add_track_links(parts, per_belt, s * 1.3, 0.58, 3.2, -3.3, 0.04, 1.0)
	return _fit_parts(parts, VEHICLE_PARTS, Vector3(2.45, 1.68, -1.05), Vector3(-0.24, 0.07, 0.0), "links")


## Obiekt 775: radziecki czołg rakietowy z 1964 roku na podwoziu T-64 —
## kadłub 6,1 m, sześć małych kół, a nad nim płaska, owalna wieża-dysk
## szersza od kadłuba z cienkim działem 125 mm D-126. Wysokość 1,8 m!
## Z przodu złożony lemiesz, po bokach fartuchy zasłaniające gąsienice.
func _obj775_parts(def_id: String) -> Array:
	var parts: Array = []
	var side: String = _side_of(def_id)
	var star: String = "star_su" if side == "su" else "star_us"
	# kadłub: niski i szeroki, z sponsonami
	parts.append(_part_box(Vector3(5.6, 0.5, 2.6), Vector3(0.0, 0.62, 0.0), Vector3.ZERO, TONE_DARK, "armor", HULL_UV))
	parts.append(_part_box(Vector3(6.1, 0.42, 2.75), Vector3(0.0, 1.02, 0.0), Vector3.ZERO, TONE_BODY, "armor", HULL_UV))
	parts.append(_part_box(Vector3(6.0, 0.12, 2.9), Vector3(0.0, 1.28, 0.0), Vector3.ZERO, TONE_DARK, "armor", HULL_UV))
	parts.append(_part_box(Vector3(2.2, 0.12, 2.9), Vector3(2.65, 0.98, 0.0), Vector3(0.0, 0.0, -0.62), TONE_BODY, "armor", HULL_UV))
	parts.append(_part_box(Vector3(0.9, 0.45, 2.7), Vector3(3.05, 0.72, 0.0), Vector3.ZERO, TONE_DARK, "armor", HULL_UV))
	parts.append(_part_box(Vector3(1.1, 0.8, 2.7), Vector3(-2.75, 0.95, 0.0), Vector3(0.0, 0.0, 0.45), TONE_DARK, "armor", HULL_UV))
	# lemiesz do spychania ziemi (składany na glacis)
	parts.append(_part_box(Vector3(0.18, 0.62, 2.75), Vector3(3.45, 0.85, 0.0), Vector3(0.0, 0.0, -0.55), TONE_DEEP, "armor", HULL_UV))
	parts.append(_part_box(Vector3(0.12, 0.5, 2.75), Vector3(3.62, 0.62, 0.0), Vector3(0.0, 0.0, -0.55), TONE_DARK, "armor"))
	for s in [-1.0, 1.0]:
		parts.append(_part_box(Vector3(0.7, 0.14, 0.14), Vector3(3.1, 1.12, s * 0.95), Vector3(0.0, 0.0, -0.4), TONE_METAL, ""))
	parts.append(_star_plate(star, 0.65, Vector3(-0.35, 1.4, 0.0), Vector3.ZERO, true))
	for z in [-1.0, 1.0]:
		parts.append(_star_plate(star, 0.42, Vector3(-1.9, 1.02, z * 1.42)))
	parts.append(_star_plate(star, 0.5, Vector3(-3.32, 0.95, 0.0), Vector3(0.0, PI * 0.5, 0.0)))
	# fartuchy zasłaniające gąsienice (znak rozpoznawczy Obiektu 775)
	for s in [-1.0, 1.0]:
		for seg in range(5):
			parts.append(_part_box(Vector3(1.18, 0.42, 0.12),
				Vector3(2.4 - float(seg) * 1.24, 0.98, s * 1.5), Vector3.ZERO, TONE_DEEP, "armor", HULL_UV))
		for seg in range(3):
			parts.append(_part_box(Vector3(1.95, 0.10, 0.72), Vector3(1.95 - float(seg) * 2.0, 1.22, s * 1.46), Vector3.ZERO, TONE_DARK, "armor", HULL_UV))
		_add_bolt_row(parts, Vector3(2.8, 0.86, s * 1.58), Vector3(-0.3, 0.0, 0.0), 9)
		_add_cable_run(parts, Vector3(2.7, 1.16, s * 1.52), Vector3(-1.7, 1.16, s * 1.52), 7)
		_add_stowage_box(parts, Vector3(0.8, 0.36, 0.55), Vector3(-1.9, 1.32, s * 1.0))
	for s in [-1.0, 1.0]:
		_add_grille(parts, Vector3(-1.2, 1.37, s * 0.72), 1.35, 1.0, 8)
		parts.append(_part_cyl(0.11, 0.11, 0.42, 10, Vector3(-2.3, 1.1, s * 1.15), Vector3(0.0, 0.0, -PI * 0.5), TONE_METAL, ""))
	_add_periscope(parts, Vector3(2.7, 1.36, -0.5))
	_add_periscope(parts, Vector3(2.7, 1.36, 0.5))
	for s in [-1.0, 1.0]:
		_add_light(parts, Vector3(2.95, 1.15, s * 0.95), s, 0.12)
	# wieża-dysk: szeroki, płaski owal (dwa walce + środek), działa 125 mm
	parts.append(_part_cyl(1.72, 1.78, 0.42, 22, Vector3(0.15, 1.52, 0.0), Vector3.ZERO, TONE_BODY, "armor", HULL_UV))
	parts.append(_part_cyl(1.35, 1.42, 0.14, 18, Vector3(0.15, 1.78, 0.0), Vector3.ZERO, TONE_DARK, "armor", HULL_UV))
	parts.append(_part_box(Vector3(1.5, 0.3, 2.4), Vector3(0.15, 1.52, 0.0), Vector3.ZERO, TONE_BODY, "armor", HULL_UV))
	parts.append(_part_cyl(0.62, 0.68, 0.3, 14, Vector3(-0.35, 1.86, 0.0), Vector3.ZERO, TONE_BODY, "armor", HULL_UV))
	parts.append(_part_box(Vector3(0.75, 0.22, 0.62), Vector3(0.75, 1.86, 0.0), Vector3.ZERO, TONE_DEEP, "armor"))
	# jarzmo i cienkie działo-pocisk rakietowy Rubin
	parts.append(_part_cyl(0.3, 0.3, 0.55, 14, Vector3(1.75, 1.62, 0.0), Vector3(0.0, 0.0, -PI * 0.5), TONE_BODY, "armor"))
	parts.append(_part_cyl(0.085, 0.095, 3.9, 12, Vector3(3.85, 1.62, 0.0), Vector3(0.0, 0.0, -PI * 0.5), TONE_DEEP, "armor", Vector3(3.0, 1.0, 1.0)))
	parts.append(_part_cyl(0.13, 0.13, 0.9, 10, Vector3(2.85, 1.62, 0.0), Vector3(0.0, 0.0, -PI * 0.5), TONE_DEEP, "armor"))
	parts.append(_part_cyl(0.105, 0.105, 0.26, 10, Vector3(5.85, 1.62, 0.0), Vector3(0.0, 0.0, -PI * 0.5), TONE_METAL, ""))
	# włazy załogi, przyrządy obserwacyjne, celownik
	parts.append(_part_cyl(0.3, 0.3, 0.16, 12, Vector3(-0.55, 1.98, 0.55), Vector3.ZERO, TONE_DEEP, "armor"))
	parts.append(_part_box(Vector3(0.32, 0.1, 0.28), Vector3(-0.55, 2.08, 0.55), Vector3.ZERO, TONE_DARK, "armor"))
	parts.append(_part_cyl(0.26, 0.26, 0.14, 12, Vector3(-0.25, 1.98, -0.6), Vector3.ZERO, TONE_DEEP, "armor"))
	parts.append(_part_box(Vector3(0.22, 0.22, 0.22), Vector3(0.35, 1.98, -0.42), Vector3.ZERO, TONE_METAL, ""))
	_add_smoke_bank(parts, 0.55, 1.78, 1.24, 1.0, 3)
	_add_smoke_bank(parts, 0.55, 1.78, -1.24, -1.0, 3)
	for s in [-1.0, 1.0]:
		_add_antenna(parts, Vector3(-1.05, 1.86, s * 0.92), 1.5)
		_add_rail(parts, Vector3(1.15, 1.72, s * 1.5), Vector3(-1.15, 1.72, s * 1.5), 3)
		for link in range(5):
			parts.append(_part_box(Vector3(0.19, 0.07, 0.5),
				Vector3(0.2 - float(link) * 0.24, 1.66, s * 1.52), Vector3(0.0, 0.0, -0.72),
				TONE_TRACK, "track", TRACK_UV, false))
	# podwozie T-64: sześć małych kół, napęd z tyłu
	for s in [-1.0, 1.0]:
		_add_running_gear(parts, s * 1.34, 6, 0.31, 0.52, 3.3, 3.05, -3.05, 0.06, 0.92, 3, false, 0.34, 0.3)
	var per_belt: int = maxi(30, (VEHICLE_PARTS - parts.size() - 24) >> 1)
	for s in [-1.0, 1.0]:
		_add_track_links(parts, per_belt, s * 1.34, 0.52, 3.05, -3.05, 0.06, 0.92)
	return _fit_parts(parts, VEHICLE_PARTS, Vector3(2.1, 1.4, -1.15), Vector3(-0.22, 0.07, 0.0), "links")
# --- wozy bojowe --------------------------------------------------------------


## Sylwetka wozu bojowego: 1024 bryły, kształt zależny od jednostki.
func _mech_parts(def_id: String) -> Array:
	var shape: String = str(MECH_SHAPES.get(def_id, "m113"))
	match shape:
		"btr60":
			return _btr60_parts(def_id)
		"bmp1":
			return _bmp1_parts(def_id)
		"mtlb", "mtu":
			return _mtlb_parts(def_id, shape == "mtu")
		"m60cev":
			return _m60a1_parts(def_id, true)
		"m113tow":
			return _m113_parts(def_id, true)
		_:
			return _m113_parts(def_id, false)


## M113: aluminiowe pudełko ze ściętym przodem, pięć kół, napęd z przodu,
## brak rolek podtrzymujących i falochron na glacis. Wariant TOW dostaje
## wyrzutnię pocisków kierowanych na dachu.
func _m113_parts(def_id: String, tow: bool) -> Array:
	var parts: Array = []
	var side: String = _side_of(def_id)
	var star: String = "star_su" if side == "su" else "star_us"
	# kadłub: wanna, burty, pokład, skosy, rufa z rampą
	parts.append(_part_box(Vector3(4.1, 0.6, 2.2), Vector3(0.0, 0.78, 0.0), Vector3.ZERO, TONE_DARK, "armor", HULL_UV))
	parts.append(_part_box(Vector3(4.4, 0.6, 2.3), Vector3(0.0, 1.44, 0.0), Vector3.ZERO, TONE_BODY, "armor", HULL_UV))
	parts.append(_part_box(Vector3(4.35, 0.12, 2.35), Vector3(0.0, 1.80, 0.0), Vector3.ZERO, TONE_DARK, "armor", HULL_UV))
	parts.append(_part_box(Vector3(1.7, 0.12, 2.35), Vector3(1.55, 1.55, 0.0), Vector3(0.0, 0.0, -0.62), TONE_BODY, "armor", HULL_UV))
	parts.append(_part_box(Vector3(0.9, 0.6, 2.2), Vector3(1.95, 1.1, 0.0), Vector3.ZERO, TONE_DARK, "armor", HULL_UV))
	parts.append(_part_box(Vector3(1.3, 1.1, 2.2), Vector3(-2.05, 1.1, 0.0), Vector3.ZERO, TONE_DARK, "armor", HULL_UV))
	parts.append(_part_box(Vector3(1.15, 0.95, 2.05), Vector3(-2.15, 1.02, 0.0), Vector3(0.0, 0.0, -0.12), TONE_DEEP, "armor", HULL_UV))
	parts.append(_star_plate(star, 0.7, Vector3(-0.4, 1.9, 0.0), Vector3.ZERO, true))
	for z in [-1.0, 1.0]:
		parts.append(_star_plate(star, 0.45, Vector3(-0.4, 1.44, z * 1.19)))
	parts.append(_star_plate(star, 0.5, Vector3(-2.71, 1.1, 0.0), Vector3(0.0, PI * 0.5, 0.0)))
	# falochron, błotniki w segmentach, uchwyty
	parts.append(_part_box(Vector3(1.6, 0.1, 2.2), Vector3(1.8, 1.95, 0.0), Vector3(0.0, 0.0, -0.4), TONE_DEEP, "armor"))
	parts.append(_part_box(Vector3(1.35, 0.08, 1.9), Vector3(2.35, 1.72, 0.0), Vector3(0.0, 0.0, -0.4), TONE_DARK, "armor"))
	for s in [-1.0, 1.0]:
		for seg in range(2):
			parts.append(_part_box(Vector3(2.05, 0.10, 0.8), Vector3(1.05 - float(seg) * 2.15, 1.5, s * 1.0), Vector3.ZERO, TONE_DARK, "armor", HULL_UV))
		parts.append(_part_box(Vector3(0.9, 0.4, 0.13), Vector3(1.95, 1.2, s * 1.0), Vector3.ZERO, TONE_DEEP, "armor"))
		_add_bolt_row(parts, Vector3(1.75, 1.36, s * 1.16), Vector3(-0.3, 0.0, 0.0), 7)
		_add_bolt_row(parts, Vector3(1.6, 1.22, s * 1.16), Vector3(-0.3, 0.0, 0.0), 6)
		_add_cable_run(parts, Vector3(1.7, 1.58, s * 1.12), Vector3(-1.5, 1.58, s * 1.12), 6)
		_add_tool_row(parts, Vector3(-0.1, 1.62, s * 1.05), Vector3.ZERO, true)
		_add_stowage_box(parts, Vector3(0.7, 0.4, 0.6), Vector3(-2.5, 1.6, s * 0.7))
	# wieżyczka dowódcy z tarczą km-u (charakterystyczna dla M113)
	parts.append(_part_cyl(0.42, 0.46, 0.34, 16, Vector3(0.4, 2.0, 0.55), Vector3.ZERO, TONE_BODY, "armor", HULL_UV))
	parts.append(_part_cyl(0.36, 0.36, 0.1, 12, Vector3(0.4, 2.22, 0.55), Vector3.ZERO, TONE_DEEP, "armor"))
	parts.append(_part_box(Vector3(0.6, 0.45, 0.08), Vector3(1.05, 2.03, 0.55), Vector3.ZERO, TONE_DEEP, "armor"))
	parts.append(_part_box(Vector3(0.26, 0.22, 0.24), Vector3(1.2, 2.25, 0.55), Vector3.ZERO, TONE_METAL, ""))
	parts.append(_part_cyl(0.05, 0.05, 0.9, 8, Vector3(1.2, 2.35, 1.0), Vector3(0.0, 0.0, -PI * 0.5), TONE_METAL, ""))
	parts.append(_part_cyl(0.36, 0.36, 0.26, 14, Vector3(-0.5, 1.95, -0.5), Vector3.ZERO, TONE_DEEP, "armor"))
	parts.append(_part_box(Vector3(0.5, 0.14, 0.5), Vector3(-1.3, 1.9, 0.4), Vector3.ZERO, TONE_DEEP, "armor"))
	parts.append(_part_box(Vector3(0.42, 0.12, 0.42), Vector3(-1.3, 2.0, 0.4), Vector3.ZERO, TONE_DARK, "armor"))
	if tow:
		# M113 TOW: dwururowa wyrzutnia na obrotnicy
		parts.append(_part_cyl(0.3, 0.34, 0.22, 12, Vector3(-0.75, 2.02, -0.55), Vector3.ZERO, TONE_DEEP, "armor"))
		parts.append(_part_box(Vector3(0.85, 0.3, 0.34), Vector3(-0.75, 2.3, -0.55), Vector3.ZERO, TONE_BODY, "armor"))
		for s2 in [-1.0, 1.0]:
			parts.append(_part_cyl(0.11, 0.11, 1.05, 10, Vector3(-0.25, 2.3, -0.55 + s2 * 0.12), Vector3(0.0, 0.0, -PI * 0.5), TONE_DEEP, "armor"))
			parts.append(_part_cyl(0.13, 0.13, 0.12, 10, Vector3(0.32, 2.3, -0.55 + s2 * 0.12), Vector3(0.0, 0.0, -PI * 0.5), TONE_METAL, ""))
		parts.append(_part_box(Vector3(0.22, 0.22, 0.22), Vector3(-0.75, 2.52, -0.55), Vector3.ZERO, TONE_METAL, ""))
	# włazy, peryskopy, reflektory, anteny
	_add_periscope(parts, Vector3(1.55, 1.92, -0.55))
	_add_periscope(parts, Vector3(1.55, 1.92, 0.55))
	for s in [-1.0, 1.0]:
		_add_light(parts, Vector3(2.2, 1.55, s * 0.8), s, 0.12)
		_add_antenna(parts, Vector3(-1.3, 2.4, s * 0.75), 1.3)
		_add_rail(parts, Vector3(1.2, 1.88, s * 1.08), Vector3(-1.6, 1.88, s * 1.08), 3)
	parts.append(_part_box(Vector3(0.9, 0.08, 0.14), Vector3(-1.4, 1.62, 1.05), Vector3.ZERO, TONE_DEEP, "armor"))
	# podwozie: pięć kół, bez rolek, napęd z przodu
	for s in [-1.0, 1.0]:
		_add_running_gear(parts, s * 1.0, 5, 0.32, 0.5, 2.6, 2.05, -2.05, 0.06, 1.0, 0, true, 0.36, 0.32)
	var per_belt: int = 72
	for s in [-1.0, 1.0]:
		_add_track_links(parts, per_belt, s * 1.0, 0.5, 2.05, -2.05, 0.06, 1.0)
	return _fit_parts(parts, VEHICLE_PARTS, Vector3(1.6, 1.42, -1.0), Vector3(-0.2, 0.075, 0.0), "links")


## BTR-60PB: ośmiokołowy wóz bojowy — łódkowy kadłub, cztery osie i mała
## stożkowa wieżyczka z km-em 14,5 mm na przodzie. Wypełnienie: łby śrub.
func _btr60_parts(def_id: String) -> Array:
	var parts: Array = []
	var side: String = _side_of(def_id)
	var star: String = "star_su" if side == "su" else "star_us"
	# kadłub łódkowy: wąskie dno, szersza góra („skrzydła mewy”)
	parts.append(_part_box(Vector3(6.6, 0.4, 1.8), Vector3(0.0, 0.55, 0.0), Vector3.ZERO, TONE_DEEP, "armor", HULL_UV))
	parts.append(_part_box(Vector3(7.2, 0.6, 2.4), Vector3(0.0, 1.0, 0.0), Vector3.ZERO, TONE_DARK, "armor", HULL_UV))
	parts.append(_part_box(Vector3(7.3, 0.5, 2.75), Vector3(0.0, 1.45, 0.0), Vector3.ZERO, TONE_BODY, "armor", HULL_UV))
	parts.append(_part_box(Vector3(7.0, 0.12, 2.8), Vector3(0.0, 1.72, 0.0), Vector3.ZERO, TONE_DARK, "armor", HULL_UV))
	parts.append(_part_box(Vector3(1.9, 0.14, 2.7), Vector3(2.95, 1.2, 0.0), Vector3(0.0, 0.0, -0.85), TONE_BODY, "armor", HULL_UV))
	parts.append(_part_box(Vector3(1.8, 0.1, 2.2), Vector3(3.3, 1.5, 0.0), Vector3(0.0, 0.0, -0.5), TONE_DEEP, "armor"))
	parts.append(_part_box(Vector3(1.0, 1.1, 2.4), Vector3(-3.4, 1.2, 0.0), Vector3(0.0, 0.0, 0.4), TONE_DARK, "armor", HULL_UV))
	parts.append(_star_plate(star, 0.6, Vector3(-1.2, 1.80, 0.0), Vector3.ZERO, true))
	for z in [-1.0, 1.0]:
		parts.append(_star_plate(star, 0.45, Vector3(-1.2, 1.45, z * 1.39)))
	parts.append(_star_plate(star, 0.5, Vector3(-4.0, 1.2, 0.0), Vector3(0.0, PI * 0.5, 0.0)))
	# falochron, półki, klamry, uchwyty
	for s in [-1.0, 1.0]:
		parts.append(_part_box(Vector3(6.4, 0.1, 0.55), Vector3(-0.2, 1.55, s * 1.42), Vector3.ZERO, TONE_DEEP, "armor", HULL_UV))
		parts.append(_part_box(Vector3(0.9, 0.4, 0.13), Vector3(2.95, 1.22, s * 1.42), Vector3.ZERO, TONE_DEEP, "armor"))
		_add_bolt_row(parts, Vector3(2.9, 1.32, s * 1.52), Vector3(-0.32, 0.0, 0.0), 10)
		_add_bolt_row(parts, Vector3(2.75, 1.18, s * 1.52), Vector3(-0.32, 0.0, 0.0), 9)
		_add_bolt_row(parts, Vector3(2.6, 0.88, s * 1.18), Vector3(-0.32, 0.0, 0.0), 8)
		_add_cable_run(parts, Vector3(2.9, 1.5, s * 1.5), Vector3(-2.2, 1.5, s * 1.5), 8)
		_add_tool_row(parts, Vector3(0.4, 1.58, s * 1.35), Vector3.ZERO, true)
		_add_stowage_box(parts, Vector3(0.6, 0.3, 0.5), Vector3(-3.6, 1.7, s * 0.8))
	# wieżyczka z km-em 14,5 mm (BTR-60PB)
	parts.append(_part_cyl(0.42, 0.55, 0.45, 16, Vector3(1.2, 1.95, 0.0), Vector3.ZERO, TONE_BODY, "armor", HULL_UV))
	parts.append(_part_cyl(0.34, 0.34, 0.1, 14, Vector3(1.2, 2.2, 0.0), Vector3.ZERO, TONE_DEEP, "armor"))
	parts.append(_part_cyl(0.07, 0.08, 1.3, 12, Vector3(2.3, 1.95, 0.0), Vector3(0.0, 0.0, -PI * 0.5), TONE_DEEP, "armor"))
	parts.append(_part_cyl(0.1, 0.1, 0.24, 12, Vector3(3.0, 1.95, 0.0), Vector3(0.0, 0.0, -PI * 0.5), TONE_METAL, ""))
	parts.append(_part_cyl(0.05, 0.05, 0.7, 8, Vector3(2.0, 1.85, 0.32), Vector3(0.0, 0.0, -PI * 0.5), TONE_METAL, ""))
	parts.append(_part_box(Vector3(0.26, 0.22, 0.26), Vector3(1.2, 2.36, 0.0), Vector3.ZERO, TONE_METAL, ""))
	# włazy, peryskopy, reflektory, anteny
	for pos in [Vector3(2.05, 1.86, -0.55), Vector3(0.0, 1.86, 0.9), Vector3(-2.2, 1.86, 0.6), Vector3(-2.2, 1.86, -0.6)]:
		parts.append(_part_cyl(0.22, 0.22, 0.16, 12, pos, Vector3.ZERO, TONE_DEEP, "armor"))
		parts.append(_part_box(Vector3(0.28, 0.08, 0.28), pos + Vector3(0.0, 0.12, 0.0), Vector3.ZERO, TONE_DARK, "armor"))
	_add_periscope(parts, Vector3(3.15, 1.52, -0.72))
	_add_periscope(parts, Vector3(3.15, 1.52, 0.72))
	for s in [-1.0, 1.0]:
		_add_light(parts, Vector3(3.25, 1.3, s * 0.75), s, 0.12)
		_add_antenna(parts, Vector3(-2.0, 2.2, s * 1.0), 1.3)
		_add_rail(parts, Vector3(1.6, 1.78, s * 1.32), Vector3(-1.8, 1.78, s * 1.32), 3)
	# śruby mocowania kół i osłony
	for s in [-1.0, 1.0]:
		for x in [2.85, 1.45, -1.35, -2.75]:
			_add_vehicle_wheel(parts, x, s * 1.35, 0.62, 0.42, 14)
			parts.append(_part_box(Vector3(0.9, 0.16, 0.14), Vector3(x - 0.35, 0.85, s * 1.2), Vector3.ZERO, TONE_DEEP, "armor", PLAIN_UV, false))
	return _fit_parts(parts, VEHICLE_PARTS, Vector3(1.6, 1.32, 1.44), Vector3(-0.28, 0.1, 0.0), "bolts")


## BMP-1: bardzo niska, ostro ścięta sylwetka, sześć kół, napęd z przodu,
## mała wieżyczka z działkiem 73 mm i wyrzutnią pocisków kierowanych na dachu.
func _bmp1_parts(def_id: String) -> Array:
	var parts: Array = []
	var side: String = _side_of(def_id)
	var star: String = "star_su" if side == "su" else "star_us"
	parts.append(_part_box(Vector3(5.6, 0.45, 2.2), Vector3(0.0, 0.68, 0.0), Vector3.ZERO, TONE_DEEP, "armor", HULL_UV))
	parts.append(_part_box(Vector3(6.1, 0.5, 2.4), Vector3(0.0, 1.2, 0.0), Vector3.ZERO, TONE_DARK, "armor", HULL_UV))
	parts.append(_part_box(Vector3(5.9, 0.12, 2.45), Vector3(0.0, 1.52, 0.0), Vector3.ZERO, TONE_BODY, "armor", HULL_UV))
	parts.append(_part_box(Vector3(2.8, 0.12, 2.45), Vector3(2.4, 1.1, 0.0), Vector3(0.0, 0.0, -1.0), TONE_BODY, "armor", HULL_UV))
	parts.append(_part_box(Vector3(0.8, 0.4, 2.3), Vector3(2.85, 0.72, 0.0), Vector3(0.0, 0.0, -0.4), TONE_DARK, "armor", HULL_UV))
	parts.append(_part_box(Vector3(1.2, 1.0, 2.3), Vector3(-2.6, 1.15, 0.0), Vector3.ZERO, TONE_DARK, "armor", HULL_UV))
	parts.append(_star_plate(star, 0.6, Vector3(-0.9, 1.60, 0.0), Vector3.ZERO, true))
	for z in [-1.0, 1.0]:
		parts.append(_star_plate(star, 0.42, Vector3(-0.9, 1.2, z * 1.24)))
	parts.append(_star_plate(star, 0.45, Vector3(-3.22, 1.15, 0.0), Vector3(0.0, PI * 0.5, 0.0)))
	# błotniki, uchwyty, skrzynie, drzwi desantowe z okienkami
	for s in [-1.0, 1.0]:
		for seg in range(2):
			parts.append(_part_box(Vector3(2.85, 0.10, 0.75), Vector3(1.4 - float(seg) * 2.9, 1.42, s * 1.15), Vector3.ZERO, TONE_DARK, "armor", HULL_UV))
		parts.append(_part_box(Vector3(0.9, 0.4, 0.13), Vector3(2.6, 1.18, s * 1.15), Vector3.ZERO, TONE_DEEP, "armor"))
		parts.append(_part_box(Vector3(1.0, 0.22, 0.1), Vector3(-2.65, 1.28, s * 0.72), Vector3.ZERO, TONE_DEEP, "armor"))
		_add_bolt_row(parts, Vector3(2.5, 1.3, s * 1.25), Vector3(-0.3, 0.0, 0.0), 8)
		_add_bolt_row(parts, Vector3(2.35, 1.16, s * 1.25), Vector3(-0.3, 0.0, 0.0), 7)
		_add_cable_run(parts, Vector3(2.5, 1.48, s * 1.2), Vector3(-1.6, 1.48, s * 1.2), 7)
		_add_tool_row(parts, Vector3(-0.2, 1.5, s * 1.1), Vector3.ZERO, true)
		_add_stowage_box(parts, Vector3(0.65, 0.35, 0.55), Vector3(-2.85, 1.55, s * 0.78))
	# wieżyczka z działkiem 73 mm i wyrzutnią 9M14 na dachu
	parts.append(_part_cyl(0.5, 0.6, 0.42, 16, Vector3(0.9, 1.78, 0.0), Vector3.ZERO, TONE_BODY, "armor", HULL_UV))
	parts.append(_part_cyl(0.52, 0.52, 0.08, 14, Vector3(0.9, 2.05, 0.0), Vector3.ZERO, TONE_DEEP, "armor"))
	parts.append(_part_cyl(0.11, 0.12, 1.5, 12, Vector3(2.2, 1.8, 0.0), Vector3(0.0, 0.0, -PI * 0.5), TONE_DEEP, "armor"))
	parts.append(_part_cyl(0.14, 0.14, 0.2, 12, Vector3(3.0, 1.8, 0.0), Vector3(0.0, 0.0, -PI * 0.5), TONE_METAL, ""))
	parts.append(_part_box(Vector3(1.1, 0.12, 0.16), Vector3(1.35, 2.18, 0.0), Vector3.ZERO, TONE_DEEP, "armor"))
	parts.append(_part_cyl(0.07, 0.07, 0.9, 10, Vector3(1.9, 2.22, 0.0), Vector3(0.0, 0.0, -PI * 0.5), TONE_METAL, ""))
	parts.append(_part_cyl(0.085, 0.085, 0.22, 10, Vector3(2.42, 2.22, 0.0), Vector3(0.0, 0.0, -PI * 0.5), TONE_METAL, ""))
	parts.append(_part_cyl(0.3, 0.3, 0.2, 14, Vector3(0.35, 1.95, -0.5), Vector3.ZERO, TONE_DEEP, "armor"))
	parts.append(_part_cyl(0.3, 0.3, 0.2, 14, Vector3(-0.5, 1.85, 0.55), Vector3.ZERO, TONE_DEEP, "armor"))
	parts.append(_part_box(Vector3(0.3, 0.1, 0.3), Vector3(0.35, 2.08, -0.5), Vector3.ZERO, TONE_DARK, "armor"))
	_add_smoke_bank(parts, 0.55, 1.95, 0.95, 1.0, 3)
	_add_smoke_bank(parts, 0.55, 1.95, -0.95, -1.0, 3)
	_add_periscope(parts, Vector3(2.85, 1.52, -0.6))
	_add_periscope(parts, Vector3(2.85, 1.52, 0.6))
	for s in [-1.0, 1.0]:
		_add_light(parts, Vector3(2.75, 1.38, s * 0.8), s, 0.12)
		_add_antenna(parts, Vector3(-1.4, 2.05, s * 0.8), 1.3)
		_add_rail(parts, Vector3(1.3, 1.68, s * 1.12), Vector3(-1.9, 1.68, s * 1.12), 3)
	parts.append(_part_box(Vector3(0.8, 0.08, 0.14), Vector3(-1.3, 1.55, 1.1), Vector3.ZERO, TONE_DEEP, "armor"))
	# podwozie: sześć kół, napęd z przodu
	for s in [-1.0, 1.0]:
		_add_running_gear(parts, s * 1.15, 6, 0.30, 0.48, 2.8, 2.6, -2.6, 0.06, 0.92, 3, true, 0.32, 0.30)
	var per_belt: int = 72
	for s in [-1.0, 1.0]:
		_add_track_links(parts, per_belt, s * 1.15, 0.48, 2.6, -2.6, 0.06, 0.92)
	return _fit_parts(parts, VEHICLE_PARTS, Vector3(2.3, 1.6, -1.0), Vector3(-0.22, 0.075, 0.0), "links")


## MT-LB: bardzo niski ciągnik opancerzony — sześć kół, brak rolek, mała
## wieżyczka z km-em na przedzie. MTU-20 nosi na dachu składany most.
func _mtlb_parts(def_id: String, bridgelayer: bool) -> Array:
	var parts: Array = []
	var side: String = _side_of(def_id)
	var star: String = "star_su" if side == "su" else "star_us"
	parts.append(_part_box(Vector3(5.8, 0.4, 2.2), Vector3(0.0, 0.62, 0.0), Vector3.ZERO, TONE_DEEP, "armor", HULL_UV))
	parts.append(_part_box(Vector3(6.1, 0.45, 2.35), Vector3(0.0, 1.1, 0.0), Vector3.ZERO, TONE_DARK, "armor", HULL_UV))
	parts.append(_part_box(Vector3(5.9, 0.12, 2.4), Vector3(0.0, 1.42, 0.0), Vector3.ZERO, TONE_BODY, "armor", HULL_UV))
	parts.append(_part_box(Vector3(1.5, 0.1, 2.4), Vector3(2.7, 1.2, 0.0), Vector3(0.0, 0.0, -0.5), TONE_BODY, "armor", HULL_UV))
	parts.append(_part_box(Vector3(0.7, 0.5, 2.3), Vector3(2.95, 0.8, 0.0), Vector3.ZERO, TONE_DARK, "armor", HULL_UV))
	parts.append(_part_box(Vector3(1.1, 0.9, 2.3), Vector3(-2.6, 1.05, 0.0), Vector3.ZERO, TONE_DARK, "armor", HULL_UV))
	parts.append(_star_plate(star, 0.55, Vector3(-1.0, 1.50, 0.0), Vector3.ZERO, true))
	for z in [-1.0, 1.0]:
		parts.append(_star_plate(star, 0.4, Vector3(-1.0, 1.1, z * 1.19)))
	parts.append(_star_plate(star, 0.45, Vector3(-3.17, 1.05, 0.0), Vector3(0.0, PI * 0.5, 0.0)))
	if bridgelayer:
		# MTU-20: składany most na dachu
		parts.append(_part_box(Vector3(5.4, 0.3, 2.3), Vector3(0.0, 1.7, 0.0), Vector3.ZERO, TONE_BODY, "armor", HULL_UV))
		parts.append(_part_box(Vector3(5.2, 0.12, 0.2), Vector3(0.0, 1.88, 1.05), Vector3.ZERO, TONE_DEEP, "armor"))
		parts.append(_part_box(Vector3(5.2, 0.12, 0.2), Vector3(0.0, 1.88, -1.05), Vector3.ZERO, TONE_DEEP, "armor"))
		for seg in range(4):
			parts.append(_part_box(Vector3(1.15, 0.08, 2.15),
				Vector3(1.9 - float(seg) * 1.28, 1.87, 0.0), Vector3.ZERO, TONE_DARK, "armor"))
	for s in [-1.0, 1.0]:
		for seg in range(2):
			parts.append(_part_box(Vector3(2.85, 0.1, 0.7), Vector3(1.45 - float(seg) * 2.95, 1.3, s * 1.15), Vector3.ZERO, TONE_DARK, "armor", HULL_UV))
		parts.append(_part_box(Vector3(0.8, 0.36, 0.13), Vector3(2.6, 1.08, s * 1.15), Vector3.ZERO, TONE_DEEP, "armor"))
		_add_bolt_row(parts, Vector3(2.55, 1.16, s * 1.25), Vector3(-0.3, 0.0, 0.0), 8)
		_add_bolt_row(parts, Vector3(2.4, 1.02, s * 1.25), Vector3(-0.3, 0.0, 0.0), 7)
		_add_cable_run(parts, Vector3(2.5, 1.36, s * 1.22), Vector3(-1.7, 1.36, s * 1.22), 7)
		_add_tool_row(parts, Vector3(-0.15, 1.38, s * 1.1), Vector3.ZERO, true)
		_add_stowage_box(parts, Vector3(0.6, 0.3, 0.5), Vector3(-2.9, 1.5, s * 0.7))
	# mała wieżyczka z km-em
	parts.append(_part_cyl(0.26, 0.32, 0.28, 14, Vector3(1.5, 1.62, 0.45), Vector3.ZERO, TONE_BODY, "armor", HULL_UV))
	parts.append(_part_cyl(0.22, 0.22, 0.08, 12, Vector3(1.5, 1.8, 0.45), Vector3.ZERO, TONE_DEEP, "armor"))
	parts.append(_part_cyl(0.05, 0.05, 0.7, 8, Vector3(1.5, 1.78, 0.85), Vector3(0.0, 0.0, -PI * 0.5), TONE_METAL, ""))
	parts.append(_part_cyl(0.3, 0.3, 0.18, 14, Vector3(-0.4, 1.52, -0.5), Vector3.ZERO, TONE_DEEP, "armor"))
	parts.append(_part_cyl(0.28, 0.28, 0.18, 14, Vector3(0.5, 1.52, 0.5), Vector3.ZERO, TONE_DEEP, "armor"))
	parts.append(_part_box(Vector3(0.34, 0.08, 0.34), Vector3(-0.4, 1.65, -0.5), Vector3.ZERO, TONE_DARK, "armor"))
	_add_periscope(parts, Vector3(2.75, 1.36, -0.55))
	_add_periscope(parts, Vector3(2.75, 1.36, 0.55))
	for s in [-1.0, 1.0]:
		_add_light(parts, Vector3(2.85, 1.25, s * 0.75), s, 0.12)
		_add_antenna(parts, Vector3(-1.6, 1.95, s * 0.8), 1.2)
		_add_rail(parts, Vector3(1.25, 1.52, s * 1.12), Vector3(-1.85, 1.52, s * 1.12), 3)
	parts.append(_part_box(Vector3(0.7, 0.08, 0.14), Vector3(-1.2, 1.45, 1.05), Vector3.ZERO, TONE_DEEP, "armor"))
	# podwozie: sześć kół, bez rolek, napęd z przodu
	for s in [-1.0, 1.0]:
		_add_running_gear(parts, s * 1.15, 6, 0.32, 0.46, 3.1, 2.9, -2.9, 0.06, 1.0, 0, true, 0.32, 0.32)
	var per_belt: int = 72
	for s in [-1.0, 1.0]:
		_add_track_links(parts, per_belt, s * 1.15, 0.46, 2.9, -2.9, 0.06, 1.0)
	return _fit_parts(parts, VEHICLE_PARTS, Vector3(2.25, 1.5, -1.0), Vector3(-0.22, 0.075, 0.0), "links")


# --- wyrównanie liczby brył ---------------------------------------------------


## Domyka liczbę brył do `target`: brakujące dokłada jako zapasowe ogniwa
## ułożone w siatce na obu burtach (`links`) albo łby śrub / uchwyty
## (`bolts` — dla wozów kołowych). Siatka zawija się w rzędach i warstwach,
## więc wypełnienie nie wychodzi poza kadłub; nadmiar ucina z końca listy.
func _fit_parts(parts: Array, target: int, mount: Vector3 = Vector3.ZERO,
		pitch: Vector3 = Vector3(-0.24, 0.07, 0.0), kind: String = "links") -> Array:
	while parts.size() > target:
		parts.remove_at(parts.size() - 1)
	var index: int = 0
	while parts.size() < target:
		var side_i: int = index % 2
		var col: int = (index >> 1) % 8
		var row: int = (index >> 4) % 3
		var layer: int = index / 48
		var pos: Vector3 = mount
		pos.x += pitch.x * float(col) + pitch.x * 0.5 * float(layer % 2)
		pos.y += pitch.y * float(row) + pitch.y * 3.0 * float((layer >> 1) % 2)
		pos.z = mount.z if side_i == 0 else -mount.z
		if kind == "bolts":
			parts.append(_part_box(Vector3(0.16, 0.06, 0.12), pos, Vector3.ZERO, TONE_DEEP, "armor", PLAIN_UV, false))
		else:
			parts.append(_part_box(Vector3(0.2, 0.07, 0.56), pos, Vector3(0.0, 0.0, -0.72),
				TONE_TRACK, "track", TRACK_UV))
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
