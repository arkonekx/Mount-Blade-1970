extends RefCounted
## Mgła wojny: stan każdego pola mapy (nieznane / zbadane / widoczne).

const UNKNOWN := 0
const EXPLORED := 1
const VISIBLE := 2

var w: int = 0
var h: int = 0
## Stan pól w kolejności wierszami: state[y * w + x].
var state: PackedByteArray


func _init(p_w: int, p_h: int) -> void:
	w = p_w
	h = p_h
	state = PackedByteArray()
	state.resize(w * h)  # domyślnie same zera, czyli UNKNOWN


func get_state(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= w or y >= h:
		return UNKNOWN
	return state[y * w + x]


func is_visible(x: int, y: int) -> bool:
	return get_state(x, y) == VISIBLE


func is_known(x: int, y: int) -> bool:
	return get_state(x, y) != UNKNOWN


## Oznacza pola w promieniu jako widoczne (aktualny widok oddziału).
func reveal(cx: int, cy: int, r: float) -> void:
	var radius: int = int(ceil(r))
	var r2: float = r * r
	for y in range(max(0, cy - radius), min(h - 1, cy + radius) + 1):
		for x in range(max(0, cx - radius), min(w - 1, cx + radius) + 1):
			var dx: float = float(x - cx)
			var dy: float = float(y - cy)
			if dx * dx + dy * dy <= r2:
				state[y * w + x] = VISIBLE


## Trwale oznacza pola jako zbadane (zwiad, trasa przemarszu).
func explore(cx: int, cy: int, r: float) -> void:
	var radius: int = int(ceil(r))
	var r2: float = r * r
	for y in range(max(0, cy - radius), min(h - 1, cy + radius) + 1):
		for x in range(max(0, cx - radius), min(w - 1, cx + radius) + 1):
			var dx: float = float(x - cx)
			var dy: float = float(y - cy)
			if dx * dx + dy * dy <= r2:
				var idx: int = y * w + x
				if state[idx] == UNKNOWN:
					state[idx] = EXPLORED


## Nowa godzina: to, co widać, staje się tylko zbadane, po czym rysujemy aktualny widok.
func refresh(cx: int, cy: int, r: float) -> void:
	for i in range(state.size()):
		if state[i] == VISIBLE:
			state[i] = EXPLORED
	reveal(cx, cy, r)


## Udział zbadanych pól (do HUD i statystyk kampanii).
func known_fraction() -> float:
	if state.is_empty():
		return 0.0
	var known: int = 0
	for i in range(state.size()):
		if state[i] != UNKNOWN:
			known += 1
	return float(known) / float(state.size())


func to_dict() -> Dictionary:
	return {"w": w, "h": h, "state": Marshalls.raw_to_base64(state)}


static func from_dict(d: Dictionary) -> RefCounted:
	var f = load("res://scripts/logic/fog.gd").new(int(d["w"]), int(d["h"]))
	var raw: PackedByteArray = Marshalls.base64_to_raw(str(d["state"]))
	if raw.size() == f.state.size():
		f.state = raw
	return f
