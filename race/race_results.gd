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
	var is_human: bool = false
	var player_number: int = 0
	var hit_count: int = 0
	var item_use_count: int = 0


var _track_id: StringName = &""
var _registered_ids: Dictionary[int, bool] = {}
var _grid_slots: Dictionary[int, int] = {}
var _player_karts: Array[KartController] = []
var _player_indices: Dictionary[int, int] = {}
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
	var players: Array[KartController] = []
	if player_kart != null:
		players.append(player_kart)
	setup_players(track_id, karts, players, save_manager)


## Registers all local humans so results and saves retain P1-P4 identity.
func setup_players(
	track_id: StringName, karts: Array[KartController], player_karts: Array[KartController],
	save_manager: SaveManagerService = null,
) -> void:
	_track_id = track_id
	_player_karts = player_karts.duplicate()
	_save_manager = save_manager if save_manager != null else SaveManager
	_registered_ids.clear()
	_grid_slots.clear()
	_last_lap_total.clear()
	_best_laps.clear()
	_hit_counts.clear()
	_item_counts.clear()
	_entries.clear()
	_player_indices.clear()
	for index: int in range(_player_karts.size()):
		_player_indices[_player_karts[index].get_instance_id()] = index
	for kart: KartController in karts:
		_registered_ids[kart.get_instance_id()] = true
		_grid_slots[kart.get_instance_id()] = _grid_slots.size()
	_connect_events()


## Builds ordered immutable-style result entries and writes player bests once.
func finalize(ranking: Array[KartController], finish_times: Dictionary) -> Array[Entry]:
	_entries.clear()
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
		entry.is_human = _player_indices.has(id)
		entry.player_number = int(_player_indices.get(id, -1)) + 1 if entry.is_human else 0
		var best_lap_ms: int = roundi(entry.best_lap_seconds * 1000.0)
		var previous_player_best_ms: int = (
			_save_manager.get_player_best_lap_ms(entry.player_number - 1, _track_id)
			if entry.is_human and _save_manager != null else -1
		)
		entry.is_new_record = (
			entry.is_human and best_lap_ms > 0
			and (previous_player_best_ms < 0 or best_lap_ms < previous_player_best_ms)
		)
		entry.hit_count = int(_hit_counts.get(id, 0))
		entry.item_use_count = int(_item_counts.get(id, 0))
		_entries.append(entry)
	_persist_player_results()
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


func _persist_player_results() -> void:
	if _player_karts.is_empty() or _save_manager == null:
		return
	for entry: Entry in _entries:
		if not entry.is_human:
			continue
		var player_id: int = entry.kart.get_instance_id()
		var best_lap_ms: int = roundi(float(_best_laps.get(player_id, -1.0)) * 1000.0)
		_save_manager.record_player_race_result(entry.player_number - 1, _track_id, best_lap_ms, entry.rank)
