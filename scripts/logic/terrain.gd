extends RefCounted
## Rodzaje terenu mapy kampanii, ich koszt ruchu i przechodniość.

enum Kind {PLAINS, FOREST, HILLS, MOUNTAIN, MARSH, RIVER, FORD, LAKE, CITY, ROAD, BRIDGE, SAND, SNOW}

## Nazwy terenu widoczne dla gracza.
const NAMES: Dictionary = {
	Kind.PLAINS: "równina",
	Kind.FOREST: "las",
	Kind.HILLS: "wzgórza",
	Kind.MOUNTAIN: "góry",
	Kind.MARSH: "bagno",
	Kind.RIVER: "rzeka",
	Kind.FORD: "bród",
	Kind.LAKE: "jezioro",
	Kind.CITY: "miasto",
	Kind.ROAD: "droga",
	Kind.BRIDGE: "most",
	Kind.SAND: "piasek",
	Kind.SNOW: "śnieg",
}

## Koszt przejścia jednego pola (1.0 = godzina marszu po równinie).
const COSTS: Dictionary = {
	Kind.PLAINS: 1.0,
	Kind.FOREST: 1.6,
	Kind.HILLS: 1.8,
	Kind.MOUNTAIN: 99.0,
	Kind.MARSH: 2.2,
	Kind.RIVER: 99.0,
	Kind.FORD: 1.4,
	Kind.LAKE: 99.0,
	Kind.CITY: 1.0,
	Kind.ROAD: 0.7,
	Kind.BRIDGE: 0.9,
	Kind.SAND: 1.2,
	Kind.SNOW: 2.0,
}


static func terrain_name(kind: int) -> String:
	return str(NAMES.get(kind, "nieznany"))


static func cost(kind: int) -> float:
	return float(COSTS.get(kind, 1.0))


## Czy po polu można się poruszać bez łodzi i mostu.
static func is_passable(kind: int) -> bool:
	return kind != Kind.MOUNTAIN and kind != Kind.LAKE and kind != Kind.RIVER


## Czy pole jest wodą (przeszkoda dla marszu, potrzebna do przeprawy/mostu).
static func is_water(kind: int) -> bool:
	return kind == Kind.RIVER or kind == Kind.LAKE


## Czy pole pozwala przejść przez wodę bez łodzi (bród jest płytki).
static func is_shallow(kind: int) -> bool:
	return kind == Kind.FORD or kind == Kind.BRIDGE


## Odwrotność terrain_name (przydatne przy wczytywaniu danych).
static func kind_from_name(value: String) -> int:
	for kind in NAMES.keys():
		if str(NAMES[kind]) == value:
			return int(kind)
	return Kind.PLAINS


## Czy teren daje osłonę w bitwie FPS.
static func is_cover(kind: int) -> bool:
	return kind == Kind.FOREST or kind == Kind.HILLS or kind == Kind.MOUNTAIN or kind == Kind.CITY
