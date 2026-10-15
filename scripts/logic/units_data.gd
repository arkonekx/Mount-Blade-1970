extends RefCounted
## Spis jednostek obu stron konfliktu (rok 1975) oraz limity oddziału.
##
## Jednostka w armii to słownik {id, def_id, cls, name}. Prototypy (pole
## `prototype`) nie trafiają do losowej rekrutacji.

const LIMIT_TOTAL := 30
const LIMIT_ARMOR := 2
const LIMIT_MECH := 5

const CLS_INFANTRY := "infantry"
const CLS_MECH := "mech"
const CLS_ARMOR := "armor"

## id, strona, klasa, nazwa, rok wejścia do służby, czy prototyp.
const UNIT_DEFS: Array = [
	# --- Siły Zbrojne USA ---
	{"id": "us_inf_m16", "side": "us", "cls": CLS_INFANTRY, "name": "Piechota (M16A1)", "year": 1967, "prototype": false},
	{"id": "us_inf_m60", "side": "us", "cls": CLS_INFANTRY, "name": "Drużyna wsparcia (M60)", "year": 1957, "prototype": false},
	{"id": "us_inf_law", "side": "us", "cls": CLS_INFANTRY, "name": "Drużyna ppanc (M72 LAW)", "year": 1963, "prototype": false},
	{"id": "us_inf_dragon", "side": "us", "cls": CLS_INFANTRY, "name": "Drużyna ppk (M47 Dragon)", "year": 1975, "prototype": false},
	{"id": "us_mech_m113", "side": "us", "cls": CLS_MECH, "name": "M113 ACAV", "year": 1960, "prototype": false},
	{"id": "us_mech_m113tow", "side": "us", "cls": CLS_MECH, "name": "M113 TOW", "year": 1970, "prototype": false},
	{"id": "us_mech_m577", "side": "us", "cls": CLS_MECH, "name": "M577 (dowodzenie)", "year": 1962, "prototype": false},
	{"id": "us_eng_cev", "side": "us", "cls": CLS_MECH, "name": "M728 CEV (inżynieryjny)", "year": 1965, "prototype": false},
	{"id": "us_arm_m48a5", "side": "us", "cls": CLS_ARMOR, "name": "M48A5 Patton", "year": 1975, "prototype": false},
	{"id": "us_arm_m60a1", "side": "us", "cls": CLS_ARMOR, "name": "M60A1", "year": 1962, "prototype": false},
	{"id": "us_arm_m551", "side": "us", "cls": CLS_ARMOR, "name": "M551 Sheridan", "year": 1966, "prototype": false},
	{"id": "us_proto_xm803", "side": "us", "cls": CLS_ARMOR, "name": "XM803 (prototyp)", "year": 1970, "prototype": true},

	# --- Siły Zbrojne ZSRR ---
	{"id": "su_inf_ak", "side": "su", "cls": CLS_INFANTRY, "name": "Piechota (AKM)", "year": 1959, "prototype": false},
	{"id": "su_inf_rpk", "side": "su", "cls": CLS_INFANTRY, "name": "Drużyna wsparcia (RPK)", "year": 1961, "prototype": false},
	{"id": "su_inf_rpg", "side": "su", "cls": CLS_INFANTRY, "name": "Drużyna ppanc (RPG-7)", "year": 1961, "prototype": false},
	{"id": "su_inf_ags", "side": "su", "cls": CLS_INFANTRY, "name": "Drużyna granatników (AGS-17)", "year": 1971, "prototype": false},
	{"id": "su_mech_btr60", "side": "su", "cls": CLS_MECH, "name": "BTR-60PB", "year": 1963, "prototype": false},
	{"id": "su_mech_bmp1", "side": "su", "cls": CLS_MECH, "name": "BMP-1", "year": 1966, "prototype": false},
	{"id": "su_mech_mtlb", "side": "su", "cls": CLS_MECH, "name": "MT-LB", "year": 1966, "prototype": false},
	{"id": "su_eng_mtu", "side": "su", "cls": CLS_MECH, "name": "MTU-20 (mostowiec)", "year": 1967, "prototype": false},
	{"id": "su_arm_t55", "side": "su", "cls": CLS_ARMOR, "name": "T-55", "year": 1958, "prototype": false},
	{"id": "su_arm_t62", "side": "su", "cls": CLS_ARMOR, "name": "T-62", "year": 1961, "prototype": false},
	{"id": "su_arm_t72", "side": "su", "cls": CLS_ARMOR, "name": "T-72 Ural", "year": 1973, "prototype": false},
	{"id": "su_proto_775", "side": "su", "cls": CLS_ARMOR, "name": "Obiekt 775 (prototyp)", "year": 1964, "prototype": true},
]


## Definicje danej strony i klasy (bez prototypów). Pusta klasa = wszystkie klasy.
static func defs_for(side: String, cls: String = "") -> Array:
	var out: Array = []
	for def in UNIT_DEFS:
		if str(def["side"]) != side:
			continue
		if bool(def["prototype"]):
			continue
		if cls != "" and str(def["cls"]) != cls:
			continue
		out.append(def)
	return out


## Definicja po identyfikatorze (również prototypy); pusty słownik, gdy brak.
static func get_def(def_id: String) -> Dictionary:
	for def in UNIT_DEFS:
		if str(def["id"]) == def_id:
			return def
	return {}


static func is_prototype(def_id: String) -> bool:
	var def: Dictionary = get_def(def_id)
	if def.is_empty():
		return false
	return bool(def["prototype"])


static func cls_of(def_id: String) -> String:
	var def: Dictionary = get_def(def_id)
	if def.is_empty():
		return ""
	return str(def["cls"])


static func name_of(def_id: String) -> String:
	var def: Dictionary = get_def(def_id)
	if def.is_empty():
		return "nieznana jednostka"
	return str(def["name"])


static func side_of(def_id: String) -> String:
	var def: Dictionary = get_def(def_id)
	if def.is_empty():
		return ""
	return str(def["side"])


## Czy jednostka jest pojazdem inżynieryjnym (potrafi stawiać mosty).
static func is_engineer(def_id: String) -> bool:
	return def_id.find("_eng_") >= 0


static func is_vehicle(cls: String) -> bool:
	return cls == CLS_MECH or cls == CLS_ARMOR
