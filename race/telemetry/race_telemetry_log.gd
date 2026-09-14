class_name RaceTelemetryLog
extends RefCounted

## Pure per-lap tuning-evidence aggregator (Phase 18d-3): drift release tiers,
## boost sources, item use, hit/recovery timing, wall impacts, and respawns
## bucketed by lap. No EventBus or scene-tree access; `core/autoload/
## race_telemetry.gd` owns the signal wiring and writes `to_dict()` to disk.

const VERSION: int = 1
const MAX_TIER: int = 3

var _laps: Array[Dictionary] = []
var _current_lap_number: int = 1
var _current: Dictionary = _new_lap_bucket()
## FIFO queue of {"lap_index": int, "hit_time": float}, paired by hit()/recovered().
var _pending_hits: Array[Dictionary] = []


## Records a drift hop entering its hold phase for the in-progress lap.
func drift_started() -> void:
	_current["drifts_started"] = int(_current["drifts_started"]) + 1


## Buckets a drift release by its rewarded mini-turbo tier (0 = no reward).
func drift_ended(released_tier: int) -> void:
	var key: String = str(clampi(released_tier, 0, MAX_TIER))
	var tiers: Dictionary = _current["drift_release_tiers"]
	tiers[key] = int(tiers.get(key, 0)) + 1


## Records a boost activation, grouped by its source label (mini_turbo_1, trick, boost_pad, ...).
func boost_started(source: StringName) -> void:
	var key: String = String(source) if not String(source).is_empty() else "unknown"
	var sources: Dictionary = _current["boosts_by_source"]
	sources[key] = int(sources.get(key, 0)) + 1


## Records one item activation for the in-progress lap.
func item_used() -> void:
	_current["items_used"] = int(_current["items_used"]) + 1


## Marks a hit's start time; pair with one later `recovered()` call.
func hit(t: float) -> void:
	_current["hits"] = int(_current["hits"]) + 1
	_pending_hits.append({"lap_index": _laps.size(), "hit_time": t})


## Closes the earliest still-open hit, crediting recovery seconds to the lap
## the hit started in (which may already have completed by now).
func recovered(t: float) -> void:
	if _pending_hits.is_empty():
		return
	var pending: Dictionary = _pending_hits.pop_front()
	var seconds: float = maxf(0.0, t - float(pending["hit_time"]))
	var lap_index: int = int(pending["lap_index"])
	var bucket: Dictionary = _laps[lap_index] if lap_index < _laps.size() else _current
	(bucket["hit_recovery_seconds"] as Array).append(seconds)


## Records a wall collision for the in-progress lap.
func wall_impact() -> void:
	_current["wall_impacts"] = int(_current["wall_impacts"]) + 1


## Records a checkpoint/kill-zone respawn for the in-progress lap.
func respawn() -> void:
	_current["respawns"] = int(_current["respawns"]) + 1


## Finalizes the in-progress lap bucket and opens the next one.
func lap_completed(lap: int, lap_time_seconds: float) -> void:
	_current["lap"] = lap
	_current["lap_time"] = lap_time_seconds
	_laps.append(_current)
	_current_lap_number = lap + 1
	_current = _new_lap_bucket()


## Returns a JSON-safe snapshot: completed laps plus an in-progress lap (only
## when it has recorded activity) and race totals summed across every lap.
func to_dict() -> Dictionary:
	var laps: Array = []
	for bucket: Dictionary in _laps:
		laps.append(_export_lap(bucket))
	if _lap_has_activity(_current):
		var unfinished: Dictionary = _export_lap(_current)
		unfinished["lap_time"] = null
		laps.append(unfinished)
	return {"version": VERSION, "laps": laps, "totals": _totals(laps)}


func _new_lap_bucket() -> Dictionary:
	return {
		"lap": _current_lap_number,
		"drifts_started": 0,
		"drift_release_tiers": {},
		"boosts_by_source": {},
		"items_used": 0,
		"hits": 0,
		"hit_recovery_seconds": [],
		"wall_impacts": 0,
		"respawns": 0,
		"lap_time": null,
	}


func _lap_has_activity(bucket: Dictionary) -> bool:
	return int(bucket["drifts_started"]) > 0 or not (bucket["drift_release_tiers"] as Dictionary).is_empty() \
		or not (bucket["boosts_by_source"] as Dictionary).is_empty() or int(bucket["items_used"]) > 0 \
		or int(bucket["hits"]) > 0 or int(bucket["wall_impacts"]) > 0 or int(bucket["respawns"]) > 0


func _export_lap(bucket: Dictionary) -> Dictionary:
	return {
		"lap": bucket["lap"],
		"drifts_started": bucket["drifts_started"],
		"drift_release_tiers": (bucket["drift_release_tiers"] as Dictionary).duplicate(),
		"boosts_by_source": (bucket["boosts_by_source"] as Dictionary).duplicate(),
		"items_used": bucket["items_used"],
		"hits": bucket["hits"],
		"hit_recovery_seconds": (bucket["hit_recovery_seconds"] as Array).duplicate(),
		"wall_impacts": bucket["wall_impacts"],
		"respawns": bucket["respawns"],
		"lap_time": bucket["lap_time"],
	}


func _totals(laps: Array) -> Dictionary:
	var totals: Dictionary = {
		"laps_completed": 0, "drifts_started": 0, "drift_release_tiers": {}, "boosts_by_source": {},
		"items_used": 0, "hits": 0, "hit_recovery_seconds": [], "wall_impacts": 0, "respawns": 0,
		"race_time": 0.0,
	}
	for entry: Variant in laps:
		var lap_entry: Dictionary = entry as Dictionary
		if lap_entry["lap_time"] != null:
			totals["laps_completed"] = int(totals["laps_completed"]) + 1
			totals["race_time"] = float(totals["race_time"]) + float(lap_entry["lap_time"])
		totals["drifts_started"] = int(totals["drifts_started"]) + int(lap_entry["drifts_started"])
		totals["items_used"] = int(totals["items_used"]) + int(lap_entry["items_used"])
		totals["hits"] = int(totals["hits"]) + int(lap_entry["hits"])
		totals["wall_impacts"] = int(totals["wall_impacts"]) + int(lap_entry["wall_impacts"])
		totals["respawns"] = int(totals["respawns"]) + int(lap_entry["respawns"])
		(totals["hit_recovery_seconds"] as Array).append_array(lap_entry["hit_recovery_seconds"])
		var lap_tiers: Dictionary = lap_entry["drift_release_tiers"]
		for tier_key: String in lap_tiers:
			var tiers: Dictionary = totals["drift_release_tiers"]
			tiers[tier_key] = int(tiers.get(tier_key, 0)) + int(lap_tiers[tier_key])
		var lap_sources: Dictionary = lap_entry["boosts_by_source"]
		for source_key: String in lap_sources:
			var sources: Dictionary = totals["boosts_by_source"]
			sources[source_key] = int(sources.get(source_key, 0)) + int(lap_sources[source_key])
	return totals
