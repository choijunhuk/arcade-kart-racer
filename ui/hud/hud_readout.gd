class_name HudReadout
extends RefCounted

## Race readout formatting and the player's lap split bookkeeping (last/best
## lap from EventBus.lap_completed race-clock stamps). Pure; owned by RaceHud.

const GOLD: Color = Color(1.0, 0.82, 0.12)
const SILVER: Color = Color(0.82, 0.9, 1.0)
const BRONZE: Color = Color(1.0, 0.58, 0.28)
const FIELD: Color = Color(1.0, 1.0, 1.0)

var last_lap_seconds: float = -1.0
var best_lap_seconds: float = -1.0
var _previous_stamp: float = 0.0


## "st"/"nd"/"rd"/"th" for a 1-based race position (11-13 take "th").
static func ordinal_suffix(race_position: int) -> String:
	var tens: int = race_position % 100
	if tens >= 11 and tens <= 13:
		return "TH"
	match race_position % 10:
		1:
			return "ST"
		2:
			return "ND"
		3:
			return "RD"
	return "TH"


static func position_color(race_position: int) -> Color:
	match race_position:
		1:
			return GOLD
		2:
			return SILVER
		3:
			return BRONZE
	return FIELD


## m:ss.mmm race clock; "-:--.---" before any value exists.
static func format_time(seconds: float) -> String:
	if seconds < 0.0:
		return "-:--.---"
	var milliseconds: int = roundi(seconds * 1000.0)
	return "%d:%02d.%03d" % [milliseconds / 60_000, (milliseconds / 1000) % 60, milliseconds % 1000]


func reset() -> void:
	last_lap_seconds = -1.0
	best_lap_seconds = -1.0
	_previous_stamp = 0.0


## `race_seconds` is the race clock stamp LapTracker emits with lap_completed.
func record_lap(race_seconds: float) -> void:
	last_lap_seconds = maxf(0.0, race_seconds - _previous_stamp)
	_previous_stamp = race_seconds
	if best_lap_seconds < 0.0 or last_lap_seconds < best_lap_seconds:
		best_lap_seconds = last_lap_seconds


func split_text() -> String:
	if last_lap_seconds < 0.0:
		return ""
	return "LAST %s   BEST %s" % [format_time(last_lap_seconds), format_time(best_lap_seconds)]
