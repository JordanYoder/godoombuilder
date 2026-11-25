@tool
class_name DMUnits
extends RefCounted
## Display units for sector maps. Everything is stored in meters; Doom map
## units are only a way of showing and typing values.


enum Units { METERS, DOOM }

## Doom map units per meter (a 56-unit-tall Doom player is 1.75 m).
const DOOM_PER_METER := 32.0

## Grid steps offered, in meters. In Doom units: 1, 2, 4, 8, 16, 32, 64, 128.
const GRID_STEPS: Array[float] = [0.03125, 0.0625, 0.125, 0.25, 0.5, 1.0, 2.0, 4.0]


static func to_display(meters: float, units: int) -> float:
	return meters * DOOM_PER_METER if units == Units.DOOM else meters


static func from_display(value: float, units: int) -> float:
	return value / DOOM_PER_METER if units == Units.DOOM else value


static func suffix(units: int) -> String:
	return "du" if units == Units.DOOM else "m"


## "1.5 m" or "48 du".
static func format(meters: float, units: int) -> String:
	var v := to_display(meters, units)
	var text := String.num(v, 0 if units == Units.DOOM and is_equal_approx(v, roundf(v)) else 3)
	if text.contains("."):
		text = text.rstrip("0").rstrip(".")
	return "%s %s" % [text, suffix(units)]


## The nearest offered grid step at or above `meters`, shifted `by` steps.
static func step_index(meters: float) -> int:
	for i in GRID_STEPS.size():
		if GRID_STEPS[i] >= meters - 1e-6:
			return i
	return GRID_STEPS.size() - 1
