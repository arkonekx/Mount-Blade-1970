extends SceneTree
## Test tekstur gry: wszystkie 13 kafli terenu musi istnieć i mieć rozmiar 16×16,
## materiały terenu 512×512, a tekstury otoczenia bitwy (drzewa, skały, budynki)
## 256×256. Pilnuje też nazw plików, powiązanych z `Terrain.Kind` i z obiektami
## budowanymi w `battle_view.gd`.

const Terrain = preload("res://scripts/logic/terrain.gd")
const GameTextures = preload("res://scripts/logic/game_textures.gd")

var failures: Array = []


func _initialize() -> void:
	print("== test_textures ==")
	_check(GameTextures.KEYS.size() == 13, "Powinno być 13 kluczy terenu (jest %d)" % GameTextures.KEYS.size())
	for kind in range(Terrain.Kind.SNOW + 1):
		var name: String = Terrain.terrain_name(kind)
		if kind >= GameTextures.KEYS.size():
			_check(false, "Brak klucza tekstury dla terenu %s" % name)
			continue
		var tile: Texture2D = GameTextures.tile(kind)
		_check(tile != null, "Brak kafla mapy dla terenu %s (%s)" % [name, GameTextures.KEYS[kind]])
		if tile != null:
			_check(tile.get_width() == 16 and tile.get_height() == 16,
				"Kafel %s ma rozmiar %d×%d, a mapa rysuje 16×16" % [name, tile.get_width(), tile.get_height()])
		var master: Texture2D = GameTextures.master(kind)
		_check(master != null, "Brak tekstury 3D dla terenu %s" % name)
		if master != null:
			_check(master.get_width() == 512 and master.get_height() == 512,
				"Tekstura %s ma rozmiar %d×%d, a materiały używają 512×512" % [name, master.get_width(), master.get_height()])
	_check(GameTextures.all_tiles_available(), "Nie wszystkie kafle terenu są dostępne")
	for key in GameTextures.PROP_KEYS:
		var prop_texture: Texture2D = GameTextures.prop(str(key))
		_check(prop_texture != null, "Brak tekstury otoczenia %s" % str(key))
		if prop_texture != null:
			_check(prop_texture.get_width() == 256 and prop_texture.get_height() == 256,
				"Tekstura otoczenia %s ma rozmiar %d×%d, a materiały używają 256×256"
				% [str(key), prop_texture.get_width(), prop_texture.get_height()])
	_check(GameTextures.all_props_available(), "Nie wszystkie tekstury otoczenia są dostępne")
	_check(GameTextures.load_error() == "", "Loader tekstur zgłosił błąd: %s" % GameTextures.load_error())
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
