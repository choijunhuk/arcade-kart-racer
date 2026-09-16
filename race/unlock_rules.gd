class_name UnlockRules
extends RefCounted

## Content unlock rule table and evaluator (spec 18e-3). Every rule reads only
## SaveManager data, so the truth of "is X unlocked" is re-evaluated from records
## on demand; the save's `unlocks` array is merely the "already announced" cache.
## Content without a rule is open from the start.

const KEY_SEPARATOR: String = ":"
const RULES: Array[Dictionary] = [
	{
		"kind": "track", "id": "track_03_glacier_crown", "name": "Glacier Crown",
		"condition": {"type": "track_position", "track": "track_02_lumen_underpass", "max_position": 3},
		"hint": "Finish top 3 on Lumen Underpass",
	},
	{
		"kind": "track", "id": "track_04_ochre_rift", "name": "Ochre Rift",
		"condition": {"type": "track_position", "track": "track_03_glacier_crown", "max_position": 3},
		"hint": "Finish top 3 on Glacier Crown",
	},
	{
		"kind": "kart", "id": "basalt_crown", "name": "Basalt Crown",
		"condition": {"type": "gp_position", "max_position": 3},
		"hint": "Finish top 3 in the Horizon Cup",
	},
	{
		"kind": "kart", "id": "zephyr_needle", "name": "Zephyr Needle",
		"condition": {"type": "gp_position", "max_position": 1},
		"hint": "Win the Horizon Cup",
	},
	{
		"kind": "driver", "id": "nyx_calder", "name": "Nyx Calder",
		"condition": {"type": "wins", "count": 5},
		"hint": "Win 5 races",
	},
	{
		"kind": "driver", "id": "echo_meridian", "name": "Echo Meridian",
		"condition": {
			"type": "best_laps_all",
			"tracks": ["track_01_ridgeline_circuit", "track_02_lumen_underpass", "track_03_glacier_crown", "track_04_ochre_rift"],
		},
		"hint": "Set a best lap on every track",
	},
	{
		"kind": "speed_class", "id": "turbo", "name": "Turbo class",
		"condition": {"type": "gp_position", "max_position": 3, "speed_class": "standard"},
		"hint": "Finish top 3 in a STANDARD Horizon Cup",
	},
	{
		"kind": "mode", "id": "mirror", "name": "Mirror mode",
		"condition": {"type": "gp_position", "max_position": 1},
		"hint": "Win the Horizon Cup in any class",
	},
]


## True when every lock is bypassed: automated harnesses (sim/tests) and the
## settings-only `gameplay.unlock_all` switch. Never consulted by `evaluate_new`
## so a bypass session cannot pollute the announced-unlock cache.
static func bypass_active() -> bool:
	return GameState.automation_mode or bool(SettingsManager.get_setting(&"gameplay", &"unlock_all", false))


## True when `kind:id` is usable now: no rule, bypass active, or condition met.
static func is_unlocked(kind: String, id: String, save_data: Dictionary) -> bool:
	return bypass_active() or condition_met(kind, id, save_data)


## Pure rule evaluation against save data; content without a rule is open.
static func condition_met(kind: String, id: String, save_data: Dictionary) -> bool:
	var rule: Dictionary = _rule_for(kind, id)
	return rule.is_empty() or _evaluate(rule["condition"], save_data)


## Player-facing requirement for a locked item, or "" when it has no rule.
static func locked_hint(kind: String, id: String) -> String:
	return String(_rule_for(kind, id).get("hint", ""))


## Display name used by the results screen's UNLOCKED line.
static func display_name(kind: String, id: String) -> String:
	return String(_rule_for(kind, id).get("name", id))


## Returns rule keys (`kind:id`) whose condition now holds but are absent from
## `already` (the save's `unlocks` cache). Pure: ignores the bypass switch.
static func evaluate_new(save_data: Dictionary, already: Array) -> Array[String]:
	var fresh: Array[String] = []
	for rule: Dictionary in RULES:
		var key: String = make_key(String(rule["kind"]), String(rule["id"]))
		if already.has(key) or fresh.has(key):
			continue
		if _evaluate(rule["condition"], save_data):
			fresh.append(key)
	return fresh


## Evaluates against `save_manager`'s data, stores new keys, returns them.
static func claim_new(save_manager: SaveManagerService) -> Array[String]:
	if save_manager == null:
		return []
	var data: Dictionary = save_manager.load_data()
	var fresh: Array[String] = evaluate_new(data, data.get("unlocks", []))
	if not fresh.is_empty():
		save_manager.add_unlocks(fresh)
	return fresh


## Formats one announcement line ("UNLOCKED: A, B") from rule keys.
static func announcement(keys: Array[String]) -> String:
	if keys.is_empty():
		return ""
	var names: PackedStringArray = PackedStringArray()
	for key: String in keys:
		names.append(display_name(key.get_slice(KEY_SEPARATOR, 0), key.get_slice(KEY_SEPARATOR, 1)))
	return "UNLOCKED: %s" % ", ".join(names)


## Replaces locked driver/kart/track ids in a saved `last_selection` with the
## SaveManager defaults so a remembered pick can never start a locked race.
static func sanitized_selection(selection: Dictionary, save_data: Dictionary) -> Dictionary:
	var defaults: Dictionary = SaveManager.default_data()["last_selection"]
	var result: Dictionary = selection.duplicate()
	for kind: String in ["driver", "kart", "track"]:
		var id: String = String(result.get(kind, ""))
		if not is_unlocked(kind, id, save_data):
			result[kind] = defaults[kind]
	return result


static func make_key(kind: String, id: String) -> String:
	return "%s%s%s" % [kind, KEY_SEPARATOR, id]


static func _rule_for(kind: String, id: String) -> Dictionary:
	for rule: Dictionary in RULES:
		if String(rule["kind"]) == kind and String(rule["id"]) == id:
			return rule
	return {}


static func _evaluate(condition: Dictionary, data: Dictionary) -> bool:
	match String(condition.get("type", "")):
		"track_position":
			var track: String = String(condition["track"])
			return _best_position(data, track) <= int(condition["max_position"])
		"gp_position":
			return _best_gp_position(data, String(condition.get("speed_class", ""))) <= int(condition["max_position"])
		"wins":
			var stats: Dictionary = data.get("stats", {}) as Dictionary
			return int(stats.get("wins", 0)) >= int(condition["count"])
		"best_laps_all":
			var laps: Dictionary = _records(data, "best_laps")
			for track: Variant in condition["tracks"]:
				if int(laps.get(String(track), -1)) <= 0:
					return false
			return true
	push_error("Unknown unlock condition type: %s" % String(condition.get("type", "")))
	return false


## Merges the top-level section with profile P1's copy (P1 mirrors top-level,
## but an old save may only carry one of the two).
static func _records(data: Dictionary, section: String) -> Dictionary:
	var merged: Dictionary = (data.get(section, {}) as Dictionary).duplicate()
	var profiles: Dictionary = data.get("player_profiles", {}) as Dictionary
	var primary: Dictionary = profiles.get("P1", {}) as Dictionary
	for track: Variant in primary.get(section, {}) as Dictionary:
		var value: int = int(primary[section][track])
		merged[track] = mini(int(merged.get(track, value)), value)
	return merged


static func _best_position(data: Dictionary, track: String) -> int:
	var value: int = int(_records(data, "best_positions").get(track, 0))
	return value if value > 0 else 1_000_000


## Lowest saved cup position across matching `grand_prix_bests` keys; a
## speed class filter matches only that class's key prefix (STANDARD has none).
static func _best_gp_position(data: Dictionary, speed_class: String) -> int:
	var expected_cup: String = String(GrandPrix.CUP_ID)
	if not speed_class.is_empty() and speed_class != "standard":
		expected_cup += "_" + speed_class
	var best: int = 1_000_000
	var bests: Dictionary = data.get("grand_prix_bests", {}) as Dictionary
	for key: Variant in bests:
		# Mirror runs of a class count for that class: "horizon_cup_mirror" and
		# "horizon_cup_turbo_mirror" are still STANDARD / TURBO cup results.
		var cup: String = String(key).get_slice("/", 0).trim_suffix("_mirror")
		if not speed_class.is_empty() and cup != expected_cup:
			continue
		var position: int = int((bests[key] as Dictionary).get("position", 0))
		if position > 0:
			best = mini(best, position)
	return best
