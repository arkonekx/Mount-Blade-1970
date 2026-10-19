extends SceneTree
## Test widoków: składa obie sceny tak, jak robi to gra, i sprawdza, czy
## zbudowany świat ma sens — bez okna graficznego.
##
## Sprawdza:
##   * bitwę: liczbę jednostek i brył w sylwetkach (piechur, wóz bojowy, czołg)
##     oraz to, że materiały naprawdę mają tekstury AI,
##   * kampanię: komplet etykiet interfejsu.
##
## Uruchomienie:
##   godot --headless --path . -s res://tests/test_views.gd

const UnitsData = preload("res://scripts/logic/units_data.gd")

# Dokładne liczby brył, z których battle_view.gd składa sylwetki
# (patrz stałe VEHICLE_PARTS / INFANTRY_PARTS w battle_view.gd).
const VEHICLE_PARTS := 1024
const INFANTRY_PARTS := 10

var failures: Array = []


func _initialize() -> void:
	print("== test_views ==")
	# Sceny dodajemy do drzewa w _initialize, ale ich `_ready` (i zbudowanie
	# świata) odpala się dopiero w pierwszej klatce — stąd awaits.
	_run()


func _run() -> void:
	await process_frame
	await _test_battle_view()
	await _test_campaign_view()
	_report()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		print("  BŁĄD: %s" % message)


func _test_battle_view() -> void:
	var scene: PackedScene = load("res://scenes/battle.tscn")
	_check(scene != null, "Nie wczytano sceny bitwy")
	if scene == null:
		return
	var view = scene.instantiate()
	root.add_child(view)
	await process_frame

	var sim = view.sim
	_check(sim != null, "Widok bitwy nie zbudował symulacji")
	_check(view.unit_nodes.size() == sim.units.size(),
		"Liczba węzłów jednostek (%d) różni się od liczby jednostek w symulacji (%d)"
		% [view.unit_nodes.size(), sim.units.size()])

	var counts: Dictionary = {}
	for i in range(sim.units.size()):
		var unit: Dictionary = sim.units[i]
		var cls: String = str(unit["cls"])
		var node: Node3D = view.unit_nodes[i]
		var meshes: int = _count_meshes(node)
		counts[cls] = mini(int(counts.get(cls, 1 << 30)), meshes)
		if cls == UnitsData.CLS_INFANTRY:
			_check(meshes == INFANTRY_PARTS,
				"Piechur ma %d brył (oczekiwane dokładnie %d: ciało, hełm, plecak, kończyny, broń)"
				% [meshes, INFANTRY_PARTS])
		else:
			_check(meshes == VEHICLE_PARTS,
				"Pojazd ma %d brył (oczekiwane dokładnie %d: kadłub, podwozie, koła, wieża, lufa)"
				% [meshes, VEHICLE_PARTS])

	# Materiały: co najmniej część świata musi mieć tekstury AI (nie same kolory).
	var textured: int = 0
	var unique_materials: Dictionary = {}
	for mesh_node in _all_meshes(view):
		var material = mesh_node.material_override
		if material is StandardMaterial3D and material.albedo_texture != null:
			textured += 1
		if material != null:
			unique_materials[material.get_instance_id()] = true
	_check(textured >= 10, "Tylko %d brył ma teksturę AI — tekstury chyba się nie wczytały" % textured)
	# Sylwetki mają po 1024 bryły; gdyby każda dostawała własny materiał,
	# w bitwie powstałyby tysiące identycznych materiałów. Cache musi działać.
	_check(unique_materials.size() <= 64,
		"Materiały nie są dzielone: %d unikalnych materiałów w scenie bitwy" % unique_materials.size())

	print("  jednostek: %d, sylwetki: %s, brył z teksturą: %d, unikalnych materiałów: %d"
		% [sim.units.size(), str(counts), textured, unique_materials.size()])
	await _test_shapes(view)

	view.free()


func _test_shapes(view) -> void:
	# Każda rodzina wozów ma inny kształt, więc mierzymy je i porównujemy:
	# dwie sylwetki o tej samej długości, wysokości i liczbie kół byłyby błędem.
	var stats: Dictionary = {}
	for def_id in ["us_arm_m60a1", "us_arm_m551", "us_proto_mbt70", "su_arm_t62", "su_arm_t72", "su_proto_775"]:
		stats[def_id] = _shape_stats(view, str(def_id), true)
	for def_id in ["us_mech_m113", "su_mech_btr60", "su_mech_bmp1", "su_mech_mtlb"]:
		stats[def_id] = _shape_stats(view, str(def_id), false)
	var seen: Dictionary = {}
	for def_id in stats:
		var st: Dictionary = stats[def_id]
		var key: String = "%d|%.1f|%.1f" % [st["wheels"], st["length"], st["height"]]
		_check(not seen.has(key), "Sylwetki %s i %s są identyczne (%s)" % [def_id, seen.get(key, "?"), key])
		seen[key] = def_id
		print("  %-14s brył %d · dł. %.1f m · wys. %.1f m · kół i ogniw %d"
			% [def_id, st["meshes"], st["length"], st["height"], st["wheels"]])
	# Czołgi obu stron muszą mieć różną wysokość sylwetki (T-62/T-72 są niższe
	# od M60), a wozy bojowe — różną liczbę kół (BTR-60 jest ośmiokołowy).
	_check(float(stats["su_arm_t72"]["height"]) < float(stats["us_arm_m60a1"]["height"]),
		"T-72 nie jest niższy od M60A1 — sylwetki nie trzymają się prawdziwych proporcji")
	_check(float(stats["us_arm_m551"]["height"]) < float(stats["us_arm_m60a1"]["height"]),
		"M551 Sheridan nie jest niższy od M60A1")
	_check(str(stats["su_mech_btr60"]["tracked"]) == "0",
		"BTR-60 nie powinien mieć gąsienic")


## Miary sylwetki: liczba brył, obrys (długość i wysokość) oraz liczba brył
## podwozia (tekstura gąsienic albo kół).
func _shape_stats(view, def_id: String, armor: bool) -> Dictionary:
	var parts: Array = view._armor_parts(def_id) if armor else view._mech_parts(def_id)
	var x_min: float = 1e9
	var x_max: float = -1e9
	var y_max: float = 0.0
	var tracked: int = 0
	for part in parts:
		var pos: Vector3 = part["pos"]
		var size := Vector3(0.1, 0.1, 0.1)
		match str(part["prim"]):
			"box":
				size = part["size"]
			"cyl":
				size = Vector3(float(part["bottom"]) * 2.0, float(part["height"]), float(part["bottom"]) * 2.0)
			"sphere":
				size = Vector3(float(part["radius"]) * 2.0, float(part["height"]), float(part["radius"]) * 2.0)
		x_min = minf(x_min, pos.x - size.x * 0.5)
		x_max = maxf(x_max, pos.x + size.x * 0.5)
		if minf(size.x, minf(size.y, size.z)) >= 0.4:
			# wysokość bez anten i prętów — inaczej mierzymy czubek anteny
			y_max = maxf(y_max, pos.y + size.y * 0.5)
		if str(part["tex"]) == "track" and str(part["prim"]) == "box":
			tracked += 1  # ogniwo gąsienicy (koła są walcami)
	return {"meshes": parts.size(), "length": x_max - x_min, "height": y_max,
		"wheels": tracked, "tracked": tracked}


func _test_campaign_view() -> void:
	var scene: PackedScene = load("res://scenes/campaign.tscn")
	_check(scene != null, "Nie wczytano sceny kampanii")
	if scene == null:
		return
	var view = scene.instantiate()
	root.add_child(view)
	await process_frame
	for field in ["campaign", "status_label", "journal_label", "objectives_label", "help_label"]:
		_check(view.get(field) != null, "Widok kampanii nie ma %s" % field)
	if view.campaign != null:
		_check(view.campaign.map["tiles"].size() == 60 * 40, "Mapa kampanii ma zły rozmiar")
	view.free()


## Liczy bryły pojazdu; pierścień strony to znacznik interfejsu, nie część
## sylwetki, więc go pomijamy.
func _count_meshes(node: Node) -> int:
	var total: int = 1 if node is MeshInstance3D and node.name != "side_ring" else 0
	for child in node.get_children():
		total += _count_meshes(child)
	return total


func _all_meshes(node: Node) -> Array:
	var found: Array = []
	if node is MeshInstance3D:
		found.append(node)
	for child in node.get_children():
		found.append_array(_all_meshes(child))
	return found


func _report() -> void:
	if failures.is_empty():
		print("Widoki zbudowały się poprawnie.")
		print("RESULT: PASS")
		quit(0)
		return
	print("Niepowodzenia: %d" % failures.size())
	print("RESULT: FAIL")
	quit(1)
