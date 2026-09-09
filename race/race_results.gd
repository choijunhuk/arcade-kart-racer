class_name RaceResults
extends Node

## Aggregates per-kart race metrics from EventBus and persists player bests.

class Entry extends RefCounted:
	var kart: KartController
	var kart_name: String = ""
	var kart_display_name: String = ""
	var driver_name: String = ""
	var rank: int = 0
	var grid_slot: int = -1
	var total_time_seconds: float = -1.0
	var best_lap_seconds: float = -1.0
	var is_new_record: bool = false
	var hit_count: int = 0
	var item_use_count: int = 0


var _track_id: StringName = &""
var _registered_ids: Dictionary[int, bool] = {}
var _grid_slots: Dictionary[int, int] = {}
var _player_kart: KartController
var _save_manager: SaveManagerService
var _last_lap_total: Dictionary[int, float] = {}
var _best_laps: Dictionary[int, float] = {}
var _hit_counts: Dictionary[int, int] = {}
var _item_counts: Dictionary[int, int] = {}
var _entries: Array[Entry] = []


## Registers race participants and the save boundary used at finalization.
func setup(
	track_id: StringName, karts: Array[KartController], player_kart: KartController,
	save_manager: SaveManagerService = null,
) -> void:
	_track_id = track_id
	_player_kart = player_kart
	_save_manager = save_manager if save_manager != null else SaveManager
	_registered_ids.clear()
	_grid_slots.clear()
	_last_lap_total.clear()
	_best_laps.clear()
	_hit_counts.clear()
	_item_counts.clear()
	_entries.clear()
	for kart: KartController in karts:
		_registered_ids[kart.get_instance_id()] = true
		_grid_slots[kart.get_instance_id()] = _grid_slots.size()
	_connect_events()


## Builds ordered immutable-style result entries and writes player bests once.
func finalize(ranking: Array[KartController], finish_times: Dictionary) -> Array[Entry]:
	_entries.clear()
	var previous_player_best_ms: int = _save_manager.get_best_lap_ms(_track_id) if _save_manager != null else -1
	for index: int in range(ranking.size()):
		var kart: KartController = ranking[index]
		var id: int = kart.get_instance_id()
		var entry: Entry = Entry.new()
		entry.kart = kart
		entry.kart_name = String(kart.name)
		var kart_data: KartData = kart.get_kart_data()
		var driver_data: DriverData = kart.get_driver_data()
		entry.kart_display_name = kart_data.display_name if kart_data != null else entry.kart_name
		entry.driver_name = driver_data.display_name if driver_data != null else "Unknown Driver"
		entry.rank = index + 1
		entry.grid_slot = _grid_slots.get(id, -1)
		entry.total_time_seconds = float(finish_times.get(id, -1.0))
		entry.best_lap_seconds = float(_best_laps.get(id, -1.0))
		var best_lap_ms: int = roundi(entry.best_lap_seconds * 1000.0)
		entry.is_new_record = (
			kart == _player_kart and best_lap_ms > 0
			and (previous_player_best_ms < 0 or best_lap_ms < previous_player_best_ms)
		)
		entry.hit_count = int(_hit_counts.get(id, 0))
		entry.item_use_count = int(_item_counts.get(id, 0))
		_entries.append(entry)
	_persist_player_result()
	return _entries.duplicate()


## Returns the finalized entries in rank order.
func get_entries() -> Array[Entry]:
	return _entries.duplicate()


func _connect_events() -> void:
	if not EventBus.lap_completed.is_connected(_on_lap_completed):
		EventBus.lap_completed.connect(_on_lap_completed)
	if not EventBus.kart_hit.is_connected(_on_kart_hit):
		EventBus.kart_hit.connect(_on_kart_hit)
	if not EventBus.item_used.is_connected(_on_item_used):
		EventBus.item_used.connect(_on_item_used)


func _exit_tree() -> void:
	if EventBus.lap_completed.is_connected(_on_lap_completed):
		EventBus.lap_completed.disconnect(_on_lap_completed)
	if EventBus.kart_hit.is_connected(_on_kart_hit):
		EventBus.kart_hit.disconnect(_on_kart_hit)
	if EventBus.item_used.is_connected(_on_item_used):
		EventBus.item_used.disconnect(_on_item_used)


func _on_lap_completed(kart: Node, _lap: int, cumulative_time_seconds: float) -> void:
	var id: int = kart.get_instance_id()
	if not _registered_ids.has(id):
		return
	var previous_total: float = float(_last_lap_total.get(id, 0.0))
	var lap_time: float = cumulative_time_seconds - previous_total
	_last_lap_total[id] = cumulative_time_seconds
	var current_best: float = float(_best_laps.get(id, INF))
	_best_laps[id] = minf(current_best, lap_time)


func _on_kart_hit(kart: Node, _hit_type: int) -> void:
	var id: int = kart.get_instance_id()
	if _registered_ids.has(id):
		_hit_counts[id] = int(_hit_counts.get(id, 0)) + 1


func _on_item_used(kart: Node, _item_id: StringName) -> void:
	var id: int = kart.get_instance_id()
	if _registered_ids.has(id):
		_item_counts[id] = int(_item_counts.get(id, 0)) + 1


func _persist_player_result() -> void:
	if _player_kart == null or _save_manager == null:
		return
	var player_id: int = _player_kart.get_instance_id()
	for entry: Entry in _entries:
		if entry.kart != _player_kart:
			continue
		var best_lap_ms: int = roundi(float(_best_laps.get(player_id, -1.0)) * 1000.0)
		_save_manager.record_race_result(_track_id, best_lap_ms, entry.rank)
		return
