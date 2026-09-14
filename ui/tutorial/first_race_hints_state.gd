class_name FirstRaceHintsState
extends RefCounted

## Pure one-shot tracking for the 3 contextual hints shown during a player's
## first real race (spec §1): drift before the first corner, use-item on the
## first pickup, trick off the first ramp. `core/autoload/first_race_hints.gd`
## owns the EventBus wiring, eligibility checks, and on-screen display; this
## class only decides whether a given hint should fire right now.

enum Hint { DRIFT, ITEM, RAMP }

const HINT_KEYS: Dictionary = {
	Hint.DRIFT: "drift",
	Hint.ITEM: "item",
	Hint.RAMP: "ramp",
}

var enabled: bool = true

var _seen: Dictionary = {}


func _init(hints_enabled: bool = true, seen: Dictionary = {}) -> void:
	enabled = hints_enabled
	_seen = seen.duplicate()


## Returns true exactly once per hint (while enabled), marking it seen.
## Returns false when hints are disabled or this hint already fired.
func consume(hint: Hint) -> bool:
	var key: String = HINT_KEYS[hint]
	if not enabled or bool(_seen.get(key, false)):
		return false
	_seen[key] = true
	return true


## Returns whether a hint has already been shown, without consuming it.
func has_seen(hint: Hint) -> bool:
	return bool(_seen.get(HINT_KEYS[hint], false))


## Returns a persistable copy suitable for `SettingsManager` storage.
func seen_snapshot() -> Dictionary:
	return _seen.duplicate()
