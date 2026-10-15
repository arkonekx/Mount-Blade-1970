extends SceneTree
## Test tekstur terenu: wszystkie 13 kafli musi istnieć i mieć rozmiar 16×16,
## a materiały 3D rozmiar 512×512. Pilnuje też nazw plików, które są powiązane
## z kolejnością `Terrain.Kind`.

const Terrain = preload("res://scripts/logic/terrain.gd")
const TerrainTextures = preload("res://scripts/logic/terrain_textures.gd")

var failures: Array = []


func _initialize() -> void:
	print("== test_terrain_textures ==")
	_check(TerrainTextures.KEYS.size() == 13, "Powinno być 13 kluczy terenu (jest %d)" % TerrainTextures.KEYS.size())
	for kind in range(Terrain.Kind.SNOW + 1):
		var name: String = Terrain.terrain_name(kind)
		if kind >= TerrainTextures.KEYS.size():
			_check(false, "Brak klucza tekstury dla terenu %s" % name)
			continue
		var tile: Texture2D = TerrainTextures.tile(kind)
		_check(tile != null, "Brak kafla mapy dla terenu %s (%s)" % [name, TerrainTextures.KEYS[kind]])
		if tile != null:
			_check(tile.get_width() == 16 and tile.get_height() == 16,
				"Kafel %s ma rozmiar %d×%d, a mapa rysuje 16×16" % [name, tile.get_width(), tile.get_height()])
		var master: Texture2D = TerrainTextures.master(kind)
		_check(master != null, "Brak tekstury 3D dla terenu %s" % name)
		if master != null:
			_check(master.get_width() == 512 and master.get_height() == 512,
				"Tekstura %s ma rozmiar %d×%d, a materiały używają 512×512" % [name, master.get_width(), master.get_height()])
	_check(TerrainTextures.all_tiles_available(), "Nie wszystkie kafle terenu są dostępne")
	_check(TerrainTextures.load_error() == "", "Loader tekstur zgłosił błąd: %s" % TerrainTextures.load_error())
	_report()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		print("  BŁĄD: %s" % message)


func _report() -> void:
	if failures.is_empty():
		print("Wszystkie sprawdzenia tekstur przeszły.")
		print("RESULT: PASS")
		quit(0)
		return
	print("Niepowodzenia: %d" % failures.size())
	print("RESULT: FAIL")
	quit(1)
