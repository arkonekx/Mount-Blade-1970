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
# (patrz stałe ARMOR_PARTS / MECH_PARTS / INFANTRY_PARTS w battle_view.gd).
const ARMOR_PARTS := 256
const MECH_PARTS := 128
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
		elif cls == UnitsData.CLS_MECH:
			_check(meshes == MECH_PARTS,
				"Wóz bojowy ma %d brył (oczekiwane dokładnie %d: kadłub, gąsienice z ogniwami, koła, wieża, lufa)"
				% [meshes, MECH_PARTS])
		else:
			_check(meshes == ARMOR_PARTS,
				"Czołg ma %d brył (oczekiwane dokładnie %d)" % [meshes, ARMOR_PARTS])

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
	# Sylwetki mają po 128–256 brył; gdyby każda dostawała własny materiał,
	# w bitwie powstałyby tysiące identycznych materiałów. Cache musi działać.
	_check(unique_materials.size() <= 64,
		"Materiały nie są dzielone: %d unikalnych materiałów w scenie bitwy" % unique_materials.size())

	print("  jednostek: %d, sylwetki: %s, brył z teksturą: %d, unikalnych materiałów: %d"
		% [sim.units.size(), str(counts), textured, unique_materials.size()])
	await _test_variants(view)

	view.free()


func _test_variants(view) -> void:
	# Sylwetka ma dwa warianty: NATO (wieża skrzynkowa) i ZSRR (kopuła).
	# Sprawdzamy, że warianty faktycznie różnią się geometrią, ale mają tę
	# samą, zadeklarowaną liczbę brył.
	for cls in [UnitsData.CLS_MECH, UnitsData.CLS_ARMOR]:
		var nato: Array = view._tank_parts("us") if cls == UnitsData.CLS_ARMOR else view._mech_parts("us")
		var su: Array = view._tank_parts("su") if cls == UnitsData.CLS_ARMOR else view._mech_parts("su")
		_check(nato.size() == su.size(), "%s: warianty mają różną liczbę brył (%d vs %d)"
			% [cls, nato.size(), su.size()])
		var gaps: int = 0
		for i in range(mini(nato.size(), su.size())):
			var a: Vector3 = nato[i]["pos"]
			var b: Vector3 = su[i]["pos"]
			if a.distance_to(b) > 0.02:
				gaps += 1
		_check(gaps >= 3, "%s: warianty NATO i ZSRR są prawie identyczne (%d różnic w położeniu)"
			% [cls, gaps])
		print("  %s: warianty NATO/ZSRR — %d brył, %d różnych detali" % [cls, nato.size(), gaps])


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


func _count_meshes(node: Node) -> int:
	var total: int = 1 if node is MeshInstance3D else 0
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
