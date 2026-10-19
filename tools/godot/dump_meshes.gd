extends SceneTree
## Narzędzie: zrzut geometrii jednostek z gry do JSON-a.
##
## Uruchomienie:
##   godot --headless --path . -s res://tools/godot/dump_meshes.gd -- /tmp/art/units.json
##
## Skrypt korzysta z tych samych funkcji, które budują świat bitwy
## (`_build_infantry`, `_mech_parts`, `_armor_parts` w battle_view.gd), więc
## w pliku ląduje dokładnie ta geometria, którą widzi gracz — bryła po bryle,
## z rozmiarami, pozycjami, obrotami, kolorami i teksturami. Zrzucamy po jednym
## przedstawicielu każdej rodziny wozów, żeby podgląd pokazywał cały park
## sprzętu, a nie trzy jednostki.

const BattleViewScene := "res://scenes/battle.tscn"
const UnitsData = preload("res://scripts/logic/units_data.gd")
const GameTextures = preload("res://scripts/logic/game_textures.gd")

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
	var uniform: Texture2D = GameTextures.unit("uniform")
	var armor: Texture2D = GameTextures.unit("armor")
	var track: Texture2D = GameTextures.unit("track")
	known_textures = {
		"uniform": uniform, "armor": armor, "track": track,
		"star_us": GameTextures.marking("star_us"), "star_su": GameTextures.marking("star_su"),
	}
	# Przedstawiciele parku sprzętu: wszystkie rodziny sylwetek obu stron.
	var samples: Array = [
		["Piechota USA (M16A1)", "us_inf_m16"],
		["Piechota ZSRR (AKM)", "su_inf_ak"],
		["M113", "us_mech_m113"],
		["BTR-60PB", "su_mech_btr60"],
		["BMP-1", "su_mech_bmp1"],
		["MT-LB", "su_mech_mtlb"],
		["M60A1", "us_arm_m60a1"],
		["M551 Sheridan", "us_arm_m551"],
		["MBT-70", "us_proto_mbt70"],
		["T-62 Obr. 1972", "su_arm_t62"],
		["T-72 Ural", "su_arm_t72"],
		["Obiekt 775", "su_proto_775"],
	]

	var units: Array = []
	for sample in samples:
		var label: String = str(sample[0])
		var def_id: String = str(sample[1])
		var cls: String = str(UnitsData.cls_of(def_id))
		var side: String = "su" if UnitsData.side_of(def_id) == "su" else "us"
		var holder: Node3D = Node3D.new()
		root.add_child(holder)
		if cls == "infantry":
			view._build_infantry(holder, view._uniform_color(side), uniform)
		elif cls == "mech":
			view._instantiate_parts(holder, view._mech_parts(def_id), view._factory_color(side), known_textures)
		else:
			view._instantiate_parts(holder, view._armor_parts(def_id), view._factory_color(side), known_textures)
		units.append({
			"def_id": def_id,
			"label": label,
			"cls": cls,
			"side": side,
			"color": _color_array(view._factory_color(side)),
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


## Zrzuca bryły pojazdu; pierścień strony (znacznik interfejsu) pomijamy,
## bo nie jest częścią sylwetki.
func _dump_node(node: Node) -> Array:
	var meshes: Array = []
	for child in node.get_children():
		if child is MeshInstance3D and child.name != "side_ring":
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
		entry["radial_segments"] = mesh.radial_segments
		entry["rings"] = mesh.rings
		entry["hemisphere"] = mesh.is_hemisphere
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
