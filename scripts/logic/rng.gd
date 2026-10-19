extends RefCounted
## Deterministyczny generator liczb losowych (mulberry32).
##
## To przeniesienie generatora z wersji TypeScript projektu: ten sam seed daje
## zawsze tę samą sekwencję liczb, a więc i tę samą mapę. Wszystkie operacje są
## 32-bitowe (jak Math.imul w JavaScript), dzięki czemu wyniki nie zależą od
## tego, czy GDScript liczy na 64-bitowych intach.

## Stan generatora (zawsze 32-bitowa liczba bez znaku).
var state: int = 0


func _init(seed_value: int = 0) -> void:
	state = seed_value & 0xFFFFFFFF


## Odpowiednik Math.imul(a, b) z JavaScript (mnożenie modulo 2^32).
##
## Rozbijamy `a` na dwie połówki, żeby iloczyny zmieściły się w 64-bitowym
## intcie GDScriptu. Wynik musi zgadzać się z Math.imul co do bitu — inaczej
## mapa z danego seeda nie byłaby zgodna z wersją TypeScript.
static func _imul32(a: int, b: int) -> int:
	var low: int = (a & 0xFFFF) * (b & 0xFFFFFFFF)
	var high: int = ((((a >> 16) & 0xFFFF) * (b & 0xFFFFFFFF)) & 0xFFFF) << 16
	return (low + high) & 0xFFFFFFFF


## Kolejna liczba z zakresu [0, 1).
func next() -> float:
	state = (state + 0x6D2B79F5) & 0xFFFFFFFF
	var t: int = state
	t = _imul32(t ^ (t >> 15), t | 1)
	t = t ^ ((t + _imul32(t ^ (t >> 7), t | 61)) & 0xFFFFFFFF)
	t = t & 0xFFFFFFFF
	return float((t ^ (t >> 14)) & 0xFFFFFFFF) / 4294967296.0


## Liczba całkowita z domkniętego zakresu [from_value, to_value].
func int_range(from_value: int, to_value: int) -> int:
	if to_value <= from_value:
		return from_value
	var span: int = to_value - from_value + 1
	return from_value + int(floor(next() * float(span)))


## Liczba zmiennoprzecinkowa z zakresu [from_value, to_value).
func float_range(from_value: float, to_value: float) -> float:
	return from_value + next() * (to_value - from_value)


## Losowy element tablicy (null, gdy tablica jest pusta).
func pick(items: Array) -> Variant:
	if items.is_empty():
		return null
	return items[int_range(0, items.size() - 1)]


## Czy losowy rzut jest mniejszy od podanego prawdopodobieństwa.
func chance(probability: float) -> bool:
	return next() < probability


## Tasowanie tablicy w miejscu (algorytm Fishera-Yatesa).
func shuffle(items: Array) -> Array:
	for i in range(items.size() - 1, 0, -1):
		var j: int = int_range(0, i)
		var tmp: Variant = items[i]
		items[i] = items[j]
		items[j] = tmp
	return items
