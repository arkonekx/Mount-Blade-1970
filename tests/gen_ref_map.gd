extends SceneTree
## Narzędzie: zapisuje tests/ref_map.json na podstawie generatora mapy.
##
## Uruchomienie:
##   godot --headless --path . -s res://tests/gen_ref_map.gd

const MapGen = preload("res://scripts/logic/map_gen.gd")
const SEEDS: Array = [1, 7, 19, 42, 123456]


func _initialize() -> void:
	var seeds: Dictionary = {}
	for seed_value in SEEDS:
		var m: Dictionary = MapGen.generate(int(seed_value), 60, 40)
		var start: Vector2i = m["start"]
		var cities: Array = []
		for c in m["cities"]:
			cities.append({"x": int(c["x"]), "y": int(c["y"]), "name": str(c["name"])})
		var tiles: PackedByteArray = m["tiles"]
		seeds[str(int(seed_value))] = {
			"w": int(m["w"]),
			"h": int(m["h"]),
			"start": [start.x, start.y],
			"cities": cities,
			"tiles": Marshalls.raw_to_base64(tiles),
		}
	var data: Dictionary = {"version": 1, "w": 60, "h": 40, "seeds": seeds}
	var file := FileAccess.open("res://tests/ref_map.json", FileAccess.WRITE)
	if file == null:
		print("Nie udało się zapisać tests/ref_map.json: %s" % error_string(FileAccess.get_open_error()))
		quit(1)
		return
	file.store_string(JSON.stringify(data, "  "))
	file.close()
	print("Zapisano tests/ref_map.json (%d seedów)." % SEEDS.size())
	quit(0)
