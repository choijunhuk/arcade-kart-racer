class_name PositionTracker
extends Node

## Progress-scalar computation + ranking (spec §14.4). Updates at 5Hz via a
## physics-tick counter (never a coroutine timer, spec §29 rule 7) and only
## re-sorts on that cadence.

const UPDATE_INTERVAL_TICKS: int = 12 ## 60 Hz / 5 Hz
const HYSTERESIS_METERS: float = 0.5

class KartRecord extends RefCounted:
	var kart: KartController
	var progress: float = 0.0
	var cached_offset: float = -1.0
	var position: int = 0
	var active_shortcut: TrackShortcut = null


var _lap_tracker: LapTracker
var _racing_line: RacingLine
var _checkpoints: Array[Checkpoint] = []
var _lap_length: float = 0.0
var _records: Dictionary[int, KartRecord] = {}
var _order: Array[KartRecord] = []
var _previous_ranking: Array[int] = []
var _tick: int = 0


func _physics_process(_delta: float) -> void:
	_tick += 1
	if _tick % UPDATE_INTERVAL_TICKS != 0:
		return
	_update_all()


## Binds this tracker to a track's Checkpoints/RacingLine/Shortcuts and the
## LapTracker that owns lap/checkpoint-window state. Call once before
## `register_kart()`.
func setup(track: TrackRoot, lap_tracker: LapTracker) -> void:
	_lap_tracker = lap_tracker
	_racing_line = track.get_racing_line()
	_checkpoints = track.get_checkpoints()
	_lap_length = track.get_lap_length()
	var shortcuts: Node = track.get_node_or_null("Shortcuts")
	if shortcuts == null:
		return
	for child: Node in shortcuts.get_children():
		if child is TrackShortcut:
			var shortcut: TrackShortcut = child as TrackShortcut
			shortcut.kart_entered.connect(_on_shortcut_entered.bind(shortcut))
			shortcut.kart_exited.connect(_on_shortcut_exited.bind(shortcut))


## Registers a kart for progress/ranking. Idempotent.
func register_kart(kart: KartController) -> void:
	if _records.has(kart.get_instance_id()):
		return
	var record: KartRecord = KartRecord.new()
	record.kart = kart
	_records[kart.get_instance_id()] = record
	_order.append(record)


func unregister_kart(kart: KartController) -> void:
	var record: KartRecord = _records.get(kart.get_instance_id())
	if record != null:
		_order.erase(record)
	_records.erase(kart.get_instance_id())


func get_position(kart: KartController) -> int:
	var record: KartRecord = _records.get(kart.get_instance_id())
	return record.position if record != null else 0


func get_progress(kart: KartController) -> float:
	var record: KartRecord = _records.get(kart.get_instance_id())
	return record.progress if record != null else 0.0


## Returns karts ordered by current rank (1st first).
func get_ranking() -> Array[KartController]:
	var result: Array[KartController] = []
	for id: int in _previous_ranking:
		var record: KartRecord = _records.get(id)
		if record != null and is_instance_valid(record.kart):
			result.append(record.kart)
	return result


## Pure ranking (spec §14.4): finished karts first, ordered by finish time
## ascending; then unfinished karts by progress descending, reordered against
## `previous_order` with `hysteresis` metres of slack so near-equal progress
## does not flip the HUD every update. Keyed by plain ids so it is testable
## with fake progress providers instead of real KartController instances.
static func rank_karts(
	previous_order: Array[int], ids: Array[int], progress_by_id: Dictionary,
	finished_by_id: Dictionary, finish_time_by_id: Dictionary, hysteresis: float,
) -> Array[int]:
	var finished_ids: Array[int] = []
	var unfinished_ids: Array[int] = []
	for id: int in ids:
		if finished_by_id.get(id, false):
			finished_ids.append(id)
		else:
			unfinished_ids.append(id)
	finished_ids.sort_custom(func(a: int, b: int) -> bool:
		return float(finish_time_by_id.get(a, 0.0)) < float(finish_time_by_id.get(b, 0.0)))
	var previous_unfinished: Array[int] = []
	for id: int in previous_order:
		if unfinished_ids.has(id):
			previous_unfinished.append(id)
	for id: int in unfinished_ids:
		if not previous_unfinished.has(id):
			previous_unfinished.append(id)
	var result: Array[int] = []
	result.append_array(finished_ids)
	result.append_array(_reorder_with_hysteresis(previous_unfinished, progress_by_id, hysteresis))
	return result


## Bubbles adjacent unfinished karts past each other only when the trailing
## kart's progress exceeds the leading kart's by more than `hysteresis`.
static func _reorder_with_hysteresis(previous_order: Array[int], progress_by_id: Dictionary, hysteresis: float) -> Array[int]:
	var order: Array[int] = previous_order.duplicate()
	var changed: bool = true
	while changed:
		changed = false
		for index: int in range(order.size() - 1):
			var leader_progress: float = float(progress_by_id.get(order[index], 0.0))
			var follower_progress: float = float(progress_by_id.get(order[index + 1], 0.0))
			if follower_progress - leader_progress > hysteresis:
				var swap: int = order[index]
				order[index] = order[index + 1]
				order[index + 1] = swap
				changed = true
	return order


func _update_all() -> void:
	var ids: Array[int] = []
	var progress_by_id: Dictionary = {}
	var finished_by_id: Dictionary = {}
	var finish_time_by_id: Dictionary = {}
	for record: KartRecord in _order:
		if not is_instance_valid(record.kart):
			continue
		record.progress = _compute_progress(record)
		var id: int = record.kart.get_instance_id()
		ids.append(id)
		progress_by_id[id] = record.progress
		finished_by_id[id] = _lap_tracker.is_finished(record.kart) if _lap_tracker != null else false
		finish_time_by_id[id] = _lap_tracker.get_finish_time(record.kart) if _lap_tracker != null else 0.0
	var new_ranking: Array[int] = rank_karts(_previous_ranking, ids, progress_by_id, finished_by_id, finish_time_by_id, HYSTERESIS_METERS)
	_apply_ranking(new_ranking)
	_previous_ranking = new_ranking


func _compute_progress(record: KartRecord) -> float:
	var lap_index: int = _lap_tracker.get_lap(record.kart) if _lap_tracker != null else 0
	if record.active_shortcut != null:
		return float(lap_index) * _lap_length + record.active_shortcut.progress_at(record.kart.global_position, _lap_length)
	var next_index: int = _lap_tracker.get_next_checkpoint_index(record.kart) if _lap_tracker != null else 0
	var window: Vector2 = _checkpoint_window(next_index)
	var offset: float = _racing_line.offset_at(record.kart.global_position, record.cached_offset) if _racing_line != null else 0.0
	record.cached_offset = offset
	return float(lap_index) * _lap_length + clampf(offset, window.x, window.y)


func _checkpoint_window(next_index: int) -> Vector2:
	if _checkpoints.is_empty():
		return Vector2(0.0, _lap_length)
	var count: int = _checkpoints.size()
	var previous_index: int = (next_index - 1 + count) % count
	var lo: float = _checkpoints[previous_index].offset
	var hi: float = _lap_length if next_index == 0 else _checkpoints[next_index].offset
	return Vector2(lo, hi)


func _apply_ranking(new_ranking: Array[int]) -> void:
	for index: int in range(new_ranking.size()):
		var record: KartRecord = _records.get(new_ranking[index])
		if record == null:
			continue
		var new_position: int = index + 1
		if record.position != 0 and record.position != new_position:
			EventBus.position_changed.emit(record.kart, record.position, new_position)
		record.position = new_position


func _on_shortcut_entered(body: Node3D, shortcut: TrackShortcut) -> void:
	var kart: KartController = body as KartController
	if kart == null:
		return
	var record: KartRecord = _records.get(kart.get_instance_id())
	if record != null:
		record.active_shortcut = shortcut


func _on_shortcut_exited(body: Node3D, shortcut: TrackShortcut) -> void:
	var kart: KartController = body as KartController
	if kart == null:
		return
	var record: KartRecord = _records.get(kart.get_instance_id())
	if record != null and record.active_shortcut == shortcut:
		record.active_shortcut = null
		# `cached_offset` was never touched while riding the shortcut (the
		# active-shortcut branch of `_compute_progress` bypasses the racing
		# line entirely), so it is stale relative to where the kart rejoins
		# the main line. Reseed it from the shortcut's known exit point so
		# the next `offset_at` hinted search looks in the right place
		# instead of anchoring on the pre-shortcut position and potentially
		# resolving to a bogus, backward-jumping offset.
		record.cached_offset = shortcut.exit_offset
