extends RefCounted
## Wczytywanie tekstur gry: terenu (`assets/textures/terrain/`) i otoczenia
## bitwy (`assets/textures/props/`).
##
## Tekstury ładujemy przez `Image.load_from_file` + `ImageTexture`, a nie przez
## `load("res://...")`. Powód: projekt bywa uruchamiany bez otwierania edytora
## (np. `--headless` w testach), a wtedy Godot nie ma jeszcze zaimportowanych
## zasobów i `load()` na pliku PNG kończy się błędem „No loader found”.
## Ten loader czyta pliki bezpośrednio z dysku, więc działa w każdym trybie.
##
## Uwaga do eksportu: przy eksporcie trzeba dodać `assets/textures/terrain/*.png`
## do filtra plików niezasobowych w presetcie (Resources → Filters to export
## non-resource files: `*.png`), inaczej pliki nie trafią do paczki.

const TERRAIN_DIR := "res://assets/textures/terrain"
const TILE_DIR := TERRAIN_DIR + "/tiles"
const PROP_DIR := "res://assets/textures/props"

## Klucze w kolejności `Terrain.Kind` z scripts/logic/terrain.gd.
const KEYS: Array = [
	"plains", "forest", "hills", "mountain", "marsh", "river", "ford",
	"lake", "city", "road", "bridge", "sand", "snow",
]

## Klucze tekstur otoczenia bitwy (drzewa, skały, budynki) — kolejność jak w
## tools/art/process_props.py.
const PROP_KEYS: Array = ["tree_bark", "tree_canopy", "rock", "wall", "roof"]

static var _masters: Dictionary = {}
static var _tiles: Dictionary = {}
static var _props: Dictionary = {}


## Tekstura 512×512 dla materiału 3D (albo null, gdy pliku brak).
static func master(kind: int) -> Texture2D:
	return _load(_masters, TERRAIN_DIR, kind)


## Kafel 16×16 dla mapy kampanii (albo null, gdy pliku brak).
static func tile(kind: int) -> Texture2D:
	return _load(_tiles, TILE_DIR, kind)


## Tekstura otoczenia bitwy (albo null, gdy pliku brak).
static func prop(key: String) -> Texture2D:
	if _props.has(key):
		return _props[key]
	var path: String = "%s/%s.png" % [PROP_DIR, key]
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	if image == null:
		_last_error = "Nie wczytano tekstury %s" % path
		push_warning(_last_error)
		_props[key] = null
		return null
	var texture := ImageTexture.create_from_image(image)
	_props[key] = texture
	return texture


## Czy wszystkie tekstury otoczenia są dostępne (używane przez testy).
static func all_props_available() -> bool:
	for key in PROP_KEYS:
		if prop(str(key)) == null:
			return false
	return true


## Czy wszystkie kafle terenu są dostępne (używane przez testy).
static func all_tiles_available() -> bool:
	for kind in range(KEYS.size()):
		if tile(kind) == null:
			return false
	return true


## Odczytuje stan zasobów z poprzedniego uruchomienia (tylko diagnostyka).
static func load_error() -> String:
	return _last_error


static var _last_error: String = ""


static func _load(cache: Dictionary, directory: String, kind: int) -> Texture2D:
	if kind < 0 or kind >= KEYS.size():
		return null
	if cache.has(kind):
		return cache[kind]
	var path: String = "%s/%s.png" % [directory, str(KEYS[kind])]
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	if image == null:
		_last_error = "Nie wczytano tekstury %s" % path
		push_warning(_last_error)
		cache[kind] = null
		return null
	var texture := ImageTexture.create_from_image(image)
	cache[kind] = texture
	return texture
