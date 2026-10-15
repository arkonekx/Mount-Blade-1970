extends SceneTree
## Narzędzie: zrzut geometrii jednostek z gry do JSON-a.
##
## Uruchomienie:
##   godot --headless --path . -s res://tools/godot/dump_meshes.gd -- /tmp/art/units.json
##
## Skrypt korzysta z tych samych funkcji, które budują świat bitwy
## (`_build_infantry`, `_build_mech`, `_build_armor` w battle_view.gd), więc
## w pliku ląduje dokładnie ta geometria, którą widzi gracz — bryła po bryle,
## z rozmiarami, pozycjami, obrotami, kolorami i teksturami.

const BattleViewScene := "res://scenes/battle.tscn"

var output_path: String = "/tmp/art/units.json"

## Tekstury sprzętu rozpoznajemy po tożsamości obiektu — `ImageTexture`
## tworzony z obrazu (`ImageTexture.create_from_image`) nie ma `resource_path`,
## więc ze ścieżki nic nie odczytamy. Klucz wystarczy rendererowi: sam dobierze
## plik z assets/textures/units/<klucz>.png.
var known_textures: Dictionary = {}


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		output_path = args[0]

	var scene: PackedScene = load(BattleViewScene)
	if scene == null:
		push_error("Nie wczytano sceny bitwy")
		quit(1)
		return
	var view = scene.instantiate()
	root.add_child(view)
	await process_frame

	# Sprzęt jak w widoku bitwy: tekstury i barwy stron.
	var uniform: Texture2D = load("res://scripts/logic/game_textures.gd").unit("uniform")
	var armor: Texture2D = load("res://scripts/logic/game_textures.gd").unit("armor")
	var track: Texture2D = load("res://scripts/logic/game_textures.gd").unit("track")
	known_textures = {"uniform": uniform, "armor": armor, "track": track}
	var sides: Array = [
		{"name": "gracz", "color": view.COLOR_PLAYER},
		{"name": "sojusznik", "color": view.COLOR_FRIEND},
		{"name": "wróg", "color": view.COLOR_ENEMY},
	]

	var units: Array = []
	for side in sides:
		for cls in ["infantry", "mech", "armor"]:
			var holder: Node3D = Node3D.new()
			root.add_child(holder)
			match cls:
				"infantry":
					view._build_infantry(holder, side["color"], uniform)
				"mech":
					view._build_mech(holder, side["color"], armor, track)
				_:
					view._build_armor(holder, side["color"], armor, track)
			units.append({
				"cls": cls,
				"side": str(side["name"]),
				"color": _color_array(side["color"]),
				"meshes": _dump_node(holder),
			})
			holder.free()

	var data: Dictionary = {
		"note": "Geometria zbudowana przez battle_view.gd (bryły, pozycje, obroty, materiały).",
		"units": units,
	}
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		push_error("Nie mogę zapisać %s" % output_path)
		quit(1)
		return
	file.store_string(JSON.stringify(data, "  "))
	file.close()
	print("Zapisano %s: %d jednostek po %d/%d/%d brył."
		% [output_path, units.size(), _count(units, "infantry"), _count(units, "mech"), _count(units, "armor")])
	quit(0)


func _count(units: Array, cls: String) -> int:
	for unit in units:
		if str(unit["cls"]) == cls:
			return (unit["meshes"] as Array).size()
	return 0


func _color_array(color: Color) -> Array:
	return [color.r, color.g, color.b]


func _dump_node(node: Node) -> Array:
	var meshes: Array = []
	for child in node.get_children():
		if child is MeshInstance3D:
			var entry: Dictionary = _dump_mesh(child)
			if not entry.is_empty():
				meshes.append(entry)
		meshes.append_array(_dump_node(child))
	return meshes


func _dump_mesh(mesh_node: MeshInstance3D) -> Dictionary:
	var mesh: Mesh = mesh_node.mesh
	if mesh == null:
		return {}
	var entry: Dictionary = {
		"position": _vec3(mesh_node.position),
		"rotation": [mesh_node.rotation.x, mesh_node.rotation.y, mesh_node.rotation.z],
		"uv_scale": _vec3(_uv_scale(mesh_node)),
	}
	if mesh is BoxMesh:
		entry["prim"] = "box"
		entry["size"] = _vec3(mesh.size)
	elif mesh is CylinderMesh:
		entry["prim"] = "cylinder"
		entry["top_radius"] = mesh.top_radius
		entry["bottom_radius"] = mesh.bottom_radius
		entry["height"] = mesh.height
		entry["radial_segments"] = mesh.radial_segments
	elif mesh is SphereMesh:
		entry["prim"] = "sphere"
		entry["radius"] = mesh.radius
		entry["height"] = mesh.height
	elif mesh is CapsuleMesh:
		entry["prim"] = "capsule"
		entry["radius"] = mesh.radius
		entry["height"] = mesh.height
		entry["radial_segments"] = mesh.radial_segments
		entry["rings"] = mesh.rings
	else:
		return {}
	var material = mesh_node.material_override
	if material is StandardMaterial3D:
		entry["albedo"] = _color_array(material.albedo_color)
		entry["roughness"] = material.roughness
		entry["texture"] = _texture_key(material.albedo_texture)
		entry["texture_size"] = [
			material.albedo_texture.get_width() if material.albedo_texture != null else 0,
			material.albedo_texture.get_height() if material.albedo_texture != null else 0,
		]
	else:
		entry["albedo"] = [1.0, 1.0, 1.0]
		entry["texture"] = null
	return entry


## Klucz znanej tekstury („uniform” / „armor” / „track”) albo null.
func _texture_key(texture: Texture2D) -> Variant:
	if texture == null:
		return null
	for key in known_textures:
		if known_textures[key] == texture:
			return str(key)
	return "unknown"


func _uv_scale(mesh_node: MeshInstance3D) -> Vector3:
	var material = mesh_node.material_override
	if material is StandardMaterial3D:
		return material.uv1_scale
	return Vector3.ONE


func _vec3(value: Vector3) -> Array:
	return [value.x, value.y, value.z]
