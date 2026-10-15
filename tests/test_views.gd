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

# Ile brył musi mieć sylwetka, żeby była „pojazdem z gąsienicami i lufą”.
const MECH_MIN_MESHES := 12
const ARMOR_MIN_MESHES := 14

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
		counts[cls] = mini(int(counts.get(cls, 99)), meshes)
		if cls == UnitsData.CLS_INFANTRY:
			_check(meshes >= 2, "Piechur ma %d brył (oczekiwane co najmniej 2: ciało + broń)" % meshes)
		elif cls == UnitsData.CLS_MECH:
			_check(meshes >= MECH_MIN_MESHES,
				"Wóz bojowy ma %d brył (oczekiwane co najmniej %d: kadłub, gąsienice, koła, wieża, lufa)"
				% [meshes, MECH_MIN_MESHES])
		else:
			_check(meshes >= ARMOR_MIN_MESHES,
				"Czołg ma %d brył (oczekiwane co najmniej %d)" % [meshes, ARMOR_MIN_MESHES])

	# Materiały: co najmniej część świata musi mieć tekstury AI (nie same kolory).
	var textured: int = 0
	for mesh_node in _all_meshes(view):
		var material = mesh_node.material_override
		if material is StandardMaterial3D and material.albedo_texture != null:
			textured += 1
	_check(textured >= 10, "Tylko %d brył ma teksturę AI — tekstury chyba się nie wczytały" % textured)

	print("  jednostek: %d, sylwetki: %s, brył z teksturą: %d"
		% [sim.units.size(), str(counts), textured])

	view.free()


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
