extends RefCounted
## Armia gracza i wroga: tworzenie, walidacja limitów, siła oddziału.

const RNG = preload("res://scripts/logic/rng.gd")
const UnitsData = preload("res://scripts/logic/units_data.gd")

## Waga jednej jednostki danej klasy (do porównywania sił).
const WEIGHT_INFANTRY := 1.0
const WEIGHT_MECH := 2.5
const WEIGHT_ARMOR := 4.0


static func weight_of(cls: String) -> float:
	if cls == UnitsData.CLS_ARMOR:
		return WEIGHT_ARMOR
	if cls == UnitsData.CLS_MECH:
		return WEIGHT_MECH
	return WEIGHT_INFANTRY


## Siła oddziału: piechota 1, zmechanizowane 2.5, pancerne 4.
static func strength(units: Array) -> float:
	var total: float = 0.0
	for unit in units:
		total += weight_of(str(unit["cls"]))
	return total


static func count_class(units: Array, cls: String) -> int:
	var count: int = 0
	for unit in units:
		if str(unit["cls"]) == cls:
			count += 1
	return count


## Lista błędów w składzie oddziału (pusta lista = wszystko w porządku).
static func validate(units: Array) -> Array:
	var errors: Array = []
	var seen: Dictionary = {}
	var armor: int = 0
	var mech: int = 0

	for unit in units:
		if typeof(unit) != TYPE_DICTIONARY:
			errors.append("Jednostka nie jest słownikiem.")
			continue
		var def_id: String = str(unit.get("def_id", ""))
		var def: Dictionary = UnitsData.get_def(def_id)
		if def.is_empty():
			errors.append("Nieznana jednostka: %s" % def_id)
			continue
		var cls: String = str(unit.get("cls", def["cls"]))
		if cls != str(def["cls"]):
			errors.append("Zła klasa jednostki %s: %s" % [def_id, cls])
		var unit_id: int = int(unit.get("id", -1))
		if seen.has(unit_id):
			errors.append("Zduplikowany identyfikator jednostki: %d" % unit_id)
		seen[unit_id] = true
		if cls == UnitsData.CLS_ARMOR:
			armor += 1
		elif cls == UnitsData.CLS_MECH:
			mech += 1

	if units.size() > UnitsData.LIMIT_TOTAL:
		errors.append("Za dużo jednostek: %d/%d" % [units.size(), UnitsData.LIMIT_TOTAL])
	if armor > UnitsData.LIMIT_ARMOR:
		errors.append("Za dużo jednostek pancernych: %d/%d" % [armor, UnitsData.LIMIT_ARMOR])
	if mech > UnitsData.LIMIT_MECH:
		errors.append("Za dużo jednostek zmechanizowanych: %d/%d" % [mech, UnitsData.LIMIT_MECH])
	return errors


## Nowa jednostka losowo wybranej definicji danej klasy.
static func make_unit(rng, side: String, cls: String, unit_id: int) -> Dictionary:
	var defs: Array = UnitsData.defs_for(side, cls)
	if defs.is_empty():
		defs = UnitsData.defs_for(side, "")
	var def: Dictionary = {}
	if not defs.is_empty():
		def = rng.pick(defs)
	return {
		"id": unit_id,
		"def_id": str(def.get("id", "")),
		"cls": str(def.get("cls", cls)),
		"name": str(def.get("name", "nieznana jednostka")),
	}


## Losowy oddział o losowym rozmiarze (na start kampanii).
static func random_army(side: String, rng, start_id: int) -> Array:
	var size: int = rng.int_range(4, 7)
	return random_army_sized(side, rng, size, start_id)


## Oddział o zadanym rozmiarze, z zachowaniem limitów pancernych i zmechanizowanych.
static func random_army_sized(side: String, rng, size: int, start_id: int) -> Array:
	var total: int = clampi(size, 1, UnitsData.LIMIT_TOTAL)
	var units: Array = []
	var armor: int = 0
	var mech: int = 0

	for i in range(total):
		var cls: String = UnitsData.CLS_INFANTRY
		if i > 0:
			var roll: float = rng.next()
			if roll < 0.18 and armor < UnitsData.LIMIT_ARMOR:
				cls = UnitsData.CLS_ARMOR
			elif roll < 0.48 and mech < UnitsData.LIMIT_MECH:
				cls = UnitsData.CLS_MECH
		var unit: Dictionary = make_unit(rng, side, cls, start_id + i)
		if str(unit["cls"]) == UnitsData.CLS_ARMOR:
			armor += 1
		elif str(unit["cls"]) == UnitsData.CLS_MECH:
			mech += 1
		units.append(unit)
	return units


## Pierwszy piechur w oddziale (dowódca, zwiadowca).
static func first_infantry(units: Array) -> Dictionary:
	for unit in units:
		if str(unit["cls"]) == UnitsData.CLS_INFANTRY:
			return unit
	return {}


## Jednostka inżynieryjna (potrafi budować mosty).
static func find_engineer(units: Array) -> Dictionary:
	for unit in units:
		if UnitsData.is_engineer(str(unit.get("def_id", ""))):
			return unit
	return {}


static func unit_ids(units: Array) -> Array:
	var ids: Array = []
	for unit in units:
		ids.append(int(unit.get("id", -1)))
	return ids
