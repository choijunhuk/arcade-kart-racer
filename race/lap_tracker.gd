class_name LapTracker
extends Node

## Sequential-only checkpoint/lap judgement per kart (spec §14.3). Reads
## Track's Checkpoint/RacingLine API and Kart's small read-only surface only;
## never reaches into either's internals.

signal kart_finished(kart: KartController, race_time_seconds: float)

const WRONG_WAY_DOT_THRESHOLD: float = -0.3
const WRONG_WAY_DWELL_SECONDS: float = 1.5

class KartRecord extends RefCounted:
	var kart: KartController
	var next_checkpoint_index: int = 1
	var last_checkpoint_index: int = 0
	var lap: int = 0
	var checkpoints_hit: PackedByteArray = PackedByteArray()
	var wrong_way_timer: float = 0.0
	var wrong_way_active: bool = false
	var finished: bool = false
	var finish_time: float = 0.0
	var cached_offset: float = -1.0


@export var total_laps: int = 3

var _checkpoints: Array[Checkpoint] = []
var _racing_line: RacingLine
var _records: Dictionary[int, KartRecord] = {}
var _race_time: float = 0.0
var _race_active: bool = true


func _physics_process(delta: float) -> void:
	if not _race_active:
		return
	_race_time += delta
	for key: int in _records.keys():
		var record: KartRecord = _records[key]
		if not is_instance_valid(record.kart) or record.finished:
			continue
		_update_wrong_way(record, delta)


## Binds this tracker to a track's Checkpoints + RacingLine. Call once before
## `register_kart()`.
func setup(track: TrackRoot) -> void:
	_checkpoints = track.get_checkpoints()
	_racing_line = track.get_racing_line()
	for checkpoint: Checkpoint in _checkpoints:
		if not checkpoint.body_passed.is_connected(_on_body_passed):
			checkpoint.body_passed.connect(_on_body_passed)


## Registers a kart for lap/checkpoint tracking. Idempotent.
func register_kart(kart: KartController) -> void:
	if _records.has(kart.get_instance_id()):
		return
	var record: KartRecord = KartRecord.new()
	record.kart = kart
	record.checkpoints_hit.resize(_checkpoints.size())
	record.next_checkpoint_index = 1 if _checkpoints.size() > 1 else 0
	_records[kart.get_instance_id()] = record


func unregister_kart(kart: KartController) -> void:
	_records.erase(kart.get_instance_id())


## Clears every registration and resets the race clock for an in-place restart.
func reset() -> void:
	_records.clear()
	_race_time = 0.0


## Enables checkpoint timing/wrong-way updates only while the race is live.
func set_race_active(active: bool) -> void:
	_race_active = active


func get_lap(kart: KartController) -> int:
	var record: KartRecord = _get_record(kart)
	return record.lap if record != null else 0


func get_next_checkpoint_index(kart: KartController) -> int:
	var record: KartRecord = _get_record(kart)
	return record.next_checkpoint_index if record != null else 0


func get_last_checkpoint_index(kart: KartController) -> int:
	var record: KartRecord = _get_record(kart)
	return record.last_checkpoint_index if record != null else 0


func get_checkpoints_hit(kart: KartController) -> int:
	var record: KartRecord = _get_record(kart)
	if record == null:
		return 0
	var hit: int = 0
	for value: int in record.checkpoints_hit:
		hit += value
	return hit


func is_wrong_way(kart: KartController) -> bool:
	var record: KartRecord = _get_record(kart)
	return record.wrong_way_active if record != null else false


func is_finished(kart: KartController) -> bool:
	var record: KartRecord = _get_record(kart)
	return record.finished if record != null else false


func get_finish_time(kart: KartController) -> float:
	var record: KartRecord = _get_record(kart)
	return record.finish_time if record != null else 0.0


## Returns the RespawnPoint marker of the last checkpoint this kart passed.
func get_respawn_point(kart: KartController) -> Marker3D:
	var record: KartRecord = _get_record(kart)
	if record == null or _checkpoints.is_empty():
		return null
	var index: int = clampi(record.last_checkpoint_index, 0, _checkpoints.size() - 1)
	return _checkpoints[index].get_respawn_point()


## Pure sequential-checkpoint state machine (spec §14.3): `index == next` ->
## pass and advance; re-entering the previous checkpoint is ignored; any
## other index is ignored (missing state persists, no lap awarded). Passing
## checkpoint 0 completes a lap only once `next` has wrapped back to 0 (i.e.
## every other checkpoint was already hit this lap).
static func evaluate_checkpoint_transition(index: int, next_checkpoint_index: int, checkpoint_count: int) -> Dictionary:
	var result: Dictionary = {"passed": false, "next_index": next_checkpoint_index, "lap_completed": false}
	if checkpoint_count <= 0:
		return result
	if index == next_checkpoint_index:
		result["passed"] = true
		result["lap_completed"] = index == 0
		result["next_index"] = (next_checkpoint_index + 1) % checkpoint_count
	return result


func _on_body_passed(body: Node3D, index: int) -> void:
	if body is KartController and (body as KartController).network_replica:
		return # Replicas consume server lap records only.
	var kart: KartController = body as KartController
	if kart == null:
		return
	var record: KartRecord = _get_record(kart)
	if record == null:
		return
	var checkpoint_count: int = _checkpoints.size()
	var transition: Dictionary = evaluate_checkpoint_transition(index, record.next_checkpoint_index, checkpoint_count)
	if not bool(transition["passed"]):
		return
	record.last_checkpoint_index = index
	record.next_checkpoint_index = int(transition["next_index"])
	if index < record.checkpoints_hit.size():
		record.checkpoints_hit[index] = 1
	if bool(transition["lap_completed"]):
		_complete_lap(record)


func _complete_lap(record: KartRecord) -> void:
	record.lap += 1
	record.checkpoints_hit.fill(0)
	EventBus.lap_completed.emit(record.kart, record.lap, _race_time)
	if record.lap >= total_laps and not record.finished:
		record.finished = true
		record.finish_time = _race_time
		kart_finished.emit(record.kart, _race_time)


func _update_wrong_way(record: KartRecord, delta: float) -> void:
	if _racing_line == null:
		return
	var offset: float = _racing_line.offset_at(record.kart.global_position, record.cached_offset)
	record.cached_offset = offset
	var tangent: Vector3 = _racing_line.tangent_at(offset)
	var facing_backward: bool = record.kart.get_forward().dot(tangent) < WRONG_WAY_DOT_THRESHOLD
	record.wrong_way_timer = record.wrong_way_timer + delta if facing_backward else 0.0
	var should_be_active: bool = record.wrong_way_timer >= WRONG_WAY_DWELL_SECONDS
	if should_be_active != record.wrong_way_active:
		record.wrong_way_active = should_be_active
		EventBus.wrong_way.emit(record.kart, should_be_active)


func _get_record(kart: KartController) -> KartRecord:
	return _records.get(kart.get_instance_id()) as KartRecord

## Returns the authoritative fixed-tick race clock for snapshots.
func network_race_seconds() -> float:
	return _race_time

## Applies an authoritative row without emitting duplicate lap/finish events.
func apply_network_row(kart: KartController, row: Dictionary, seconds: float) -> void:
	var record: KartRecord = _get_record(kart)
	if record == null:
		return # Unregistered bodies have no network identity.
	record.lap = int(row["lap"])
	record.next_checkpoint_index = int(row["checkpoint"])
	record.last_checkpoint_index = posmod(record.next_checkpoint_index - 1, _checkpoints.size())
	record.finished = float(row["finish"]) >= 0.0
	record.finish_time = float(row["finish"])
	_race_time = seconds
