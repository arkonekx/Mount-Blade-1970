extends RefCounted
## Cykl dnia i nocy: światło, widoczność, przygaszenie obrazu.

const DAWN := 6.0
const DUSK := 20.0
const NIGHT_SIGHT_FACTOR := 0.6


## Godzina w cyklu dobowym (0-24).
static func hour_of_day(hours: int) -> float:
	var value: float = float(hours) - 24.0 * floor(float(hours) / 24.0)
	return value


## Ile jest dnia (0 = noc, 1 = pełny dzień).
static func daylight(hours: int) -> float:
	var h: float = hour_of_day(hours)
	if h < DAWN or h >= DUSK:
		return 0.0
	if h < DAWN + 1.0:
		return h - DAWN
	if h > DUSK - 1.0:
		return DUSK - h
	return 1.0


static func is_night(hours: int) -> bool:
	var h: float = hour_of_day(hours)
	return h < DAWN or h >= DUSK


## Zasięg widzenia oddziału o danej godzinie (nocą krótszy).
static func sight_at(base: float, hours: int) -> float:
	if is_night(hours):
		return maxf(1.0, base * NIGHT_SIGHT_FACTOR)
	return base


## Krycie ekranu nocą (0 = dzień, ~0.45 = środek nocy).
static func night_tint_alpha(hours: int) -> float:
	var day: float = daylight(hours)
	return (1.0 - day) * 0.45


## Godzina w formacie "Dzień 2, 07:00".
static func format_time(day: int, hours: int) -> String:
	var h: float = hour_of_day(hours)
	var hh: int = int(floor(h))
	var mm: int = int(floor((h - float(hh)) * 60.0))
	return "Dzień %d, %02d:%02d" % [day, hh, mm]
