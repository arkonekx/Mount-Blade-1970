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
const UNIT_DIR := "res://assets/textures/units"
const ICON_DIR := "res://assets/textures/icons"

## Klucze w kolejności `Terrain.Kind` z scripts/logic/terrain.gd.
const KEYS: Array = [
	"plains", "forest", "hills", "mountain", "marsh", "river", "ford",
	"lake", "city", "road", "bridge", "sand", "snow",
]

## Klucze tekstur otoczenia bitwy (drzewa, skały, budynki) — kolejność jak w
## tools/art/process_props.py.
const PROP_KEYS: Array = ["tree_bark", "tree_canopy", "rock", "wall", "roof"]

## Klucze tekstur sprzętu (są jasne i neutralne, bo w grze mnoży je kolor strony).
const UNIT_KEYS: Array = ["uniform", "armor", "track"]

## Klucze ikon interfejsu — kolejność jak w tools/art/process_icons.py.
const ICON_KEYS: Array = ["player", "enemy", "objective", "city", "boat", "scout"]

static var _masters: Dictionary = {}
static var _tiles: Dictionary = {}
static var _props: Dictionary = {}
static var _units: Dictionary = {}
static var _icons: Dictionary = {}


## Tekstura 512×512 dla materiału 3D (albo null, gdy pliku brak).
static func master(kind: int) -> Texture2D:
	return _load(_masters, TERRAIN_DIR, kind)


## Kafel 16×16 dla mapy kampanii (albo null, gdy pliku brak).
static func tile(kind: int) -> Texture2D:
	return _load(_tiles, TILE_DIR, kind)


## Tekstura otoczenia bitwy (albo null, gdy pliku brak).
static func prop(key: String) -> Texture2D:
	return _load_named(_props, PROP_DIR, key)


## Wspólne wczytywanie nazwanej tekstury (z pamięcią podręczną i ostrzeżeniem).
static func _load_named(cache: Dictionary, directory: String, key: String) -> Texture2D:
	if cache.has(key):
		return cache[key]
	var path: String = "%s/%s.png" % [directory, key]
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	if image == null:
		_last_error = "Nie wczytano tekstury %s" % path
		push_warning(_last_error)
		cache[key] = null
		return null
	var texture := ImageTexture.create_from_image(image)
	cache[key] = texture
	return texture


## Tekstura sprzętu (mundur piechoty, pancerz pojazdu) albo null.
static func unit(key: String) -> Texture2D:
	return _load_named(_units, UNIT_DIR, key)


## Ikona interfejsu (RGBA, wycięta z tła) albo null.
static func icon(key: String) -> Texture2D:
	return _load_named(_icons, ICON_DIR, key)


static func all_units_available() -> bool:
	for key in UNIT_KEYS:
		if unit(str(key)) == null:
			return false
	return true


static func all_icons_available() -> bool:
	for key in ICON_KEYS:
		if icon(str(key)) == null:
			return false
	return true


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
