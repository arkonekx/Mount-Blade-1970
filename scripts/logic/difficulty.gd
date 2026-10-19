extends RefCounted
## Poziom trudności kampanii: rośnie z dniami, wyrównuje się po zwycięstwach.

const CEILING := 2.5
const FLOOR := 0.5
const STEP := 0.15
const GROWTH_PER_DAY := 0.06


## Trudność bazowa: 1.0 pierwszego dnia, dalej rośnie z czasem.
static func base_difficulty(day: int) -> float:
	var d: int = maxi(1, day)
	return 1.0 + float(d - 1) * GROWTH_PER_DAY


## Trudność po uwzględnieniu ulgi (relief) z poprzednich bitew; sufit 2.5.
static func effective_difficulty(day: int, relief: float) -> float:
	return clampf(base_difficulty(day) * relief, FLOOR, CEILING)


## Zmiana ulgi po bitwie: zwycięstwo ułatwia, porażka zaostrza (min 0.5).
static func update_relief(relief: float, outcome: String) -> float:
	if outcome == "win":
		return maxf(FLOOR, relief - STEP)
	if outcome == "loss":
		return minf(2.0, relief + STEP)
	return clampf(relief, FLOOR, 2.0)


## Ile jednostek wystawia przeciwnik przy danej trudności.
static func enemy_army_size(difficulty: float) -> int:
	return clampi(int(round(2.0 + difficulty * 1.8)), 2, 12)


## Co ile godzin dowódca wroga podejmuje nową decyzję (umiejętność 1-5).
static func think_interval(skill: int) -> int:
	return maxi(1, 10 - clampi(skill, 1, 5))
