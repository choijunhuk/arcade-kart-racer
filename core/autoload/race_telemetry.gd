class_name RaceTelemetryService
extends Node

## Phase 18d-3 glue: turns real EventBus signals from local human karts into a
## `RaceTelemetryLog` and writes it to disk on RESULTS. Gating, hit-recovery
## math, and identity checks are pure static functions below so they are
## testable without a scene tree; only signal wiring and file I/O are
## stateful here. `enabled_override`/`telemetry_directory`/`track_id_override`
## let tests drive a real instance without touching `user://`.

const DEFAULT_DIRECTORY: String = "user://telemetry"
const MAX_FILES: int = 20
const HIT_RECOVERY_CAP_SECONDS: float = 10.0
const RECOVERY_SPEED_RATIO: float = 0.8

var telemetry_directory: String = DEFAULT_DIRECTORY
## Test-only escape hatch: non-null replaces the full recording gate.
var enabled_override: Variant = null
## Test-only escape hatch: non-null replaces GameState.selected_track_id in the filename.
var track_id_override: Variant = null

var _log: RaceTelemetryLog
var _elapsed_seconds: float = 0.0
var _known_karts: Dictionary = {}
var _last_speed: Dictionary = {}
var _pending_recovery: Dictionary = {}


func _ready() -> void:
	EventBus.race_started.connect(_on_race_started)
	EventBus.race_state_changed.connect(_on_race_state_changed)
	EventBus.drift_started.connect(_on_drift_started)
	EventBus.drift_ended.connect(_on_drift_ended)
	EventBus.boost_started.connect(_on_boost_started)
	EventBus.item_used.connect(_on_item_used)
	EventBus.kart_hit.connect(_on_kart_hit)
	EventBus.wall_impacted.connect(_on_wall_impacted)
	EventBus.kart_respawned.connect(_on_kart_respawned)
	EventBus.lap_completed.connect(_on_lap_completed)


func _physics_process(delta: float) -> void:
	if _log == null:
		return
	_elapsed_seconds += delta
	for id: Variant in _known_karts:
		var kart: Node = _known_karts[id]
		if is_instance_valid(kart):
			_last_speed[id] = (kart as KartController).get_speed()
	_update_pending_recoveries()


func _on_race_started() -> void:
	_log = RaceTelemetryLog.new() if _should_record() else null
	_elapsed_seconds = 0.0
	_known_karts.clear()
	_last_speed.clear()
	_pending_recovery.clear()


func _on_race_state_changed(_old_state: int, new_state: int) -> void:
	if new_state != RaceState.RESULTS or _log == null:
		return
	_write_log()
	_log = null


func _on_drift_started(kart: Node, _direction: int) -> void:
	if _track(kart):
		_log.drift_started()


func _on_drift_ended(kart: Node, released_tier: int) -> void:
	if _track(kart):
		_log.drift_ended(released_tier)


func _on_boost_started(kart: Node, _spec: Resource) -> void:
	if not _track(kart):
		return
	_log.boost_started((kart as KartController).boost_controller.get_source())
	_finish_recovery(kart, _elapsed_seconds)


func _on_item_used(kart: Node, _item_id: StringName) -> void:
	if _track(kart):
		_log.item_used()


func _on_kart_hit(kart: Node, _hit_type: int) -> void:
	if not _track(kart):
		return
	_finish_recovery(kart, _elapsed_seconds)
	var id: int = kart.get_instance_id()
	_log.hit(_elapsed_seconds)
	_pending_recovery[id] = {
		"hit_time": _elapsed_seconds,
		"pre_hit_speed": float(_last_speed.get(id, (kart as KartController).get_speed())),
	}


func _on_wall_impacted(kart: Node) -> void:
	if _track(kart):
		_log.wall_impact()


func _on_kart_respawned(kart: Node) -> void:
	if _track(kart):
		_log.respawn()


func _on_lap_completed(kart: Node, lap: int, lap_time_seconds: float) -> void:
	if _track(kart):
		_log.lap_completed(lap, lap_time_seconds)


## Returns whether `kart` is a local human kart and, while recording, remembers
## it for per-frame speed sampling (hit recovery needs a pre-hit baseline).
func _track(kart: Node) -> bool:
	if _log == null or not is_local_human_kart(kart):
		return false
	var id: int = kart.get_instance_id()
	if not _known_karts.has(id):
		_known_karts[id] = kart
		_last_speed[id] = (kart as KartController).get_speed()
	return true


func _update_pending_recoveries() -> void:
	for id: Variant in _pending_recovery.keys().duplicate():
		var kart: Node = _known_karts.get(id)
		if not is_instance_valid(kart):
			_pending_recovery.erase(id)
			continue
		var pending: Dictionary = _pending_recovery[id]
		var elapsed_since_hit: float = _elapsed_seconds - float(pending["hit_time"])
		var current_speed: float = float(_last_speed.get(id, (kart as KartController).get_speed()))
		if is_recovered(current_speed, float(pending["pre_hit_speed"]), elapsed_since_hit):
			_log.recovered(minf(_elapsed_seconds, float(pending["hit_time"]) + HIT_RECOVERY_CAP_SECONDS))
			_pending_recovery.erase(id)


func _finish_recovery(kart: Node, t: float) -> void:
	var id: int = kart.get_instance_id()
	if _pending_recovery.has(id):
		_log.recovered(t)
		_pending_recovery.erase(id)


func _write_log() -> void:
	var track_id: String = String(track_id_override) if track_id_override != null else String(GameState.selected_track_id)
	if track_id.is_empty():
		track_id = "unknown"
	var stamp: String = Time.get_datetime_string_from_system(false, true).replace(":", "").replace("-", "").replace("T", "-")
	write_and_rotate(telemetry_directory, "%s-%s.json" % [stamp, track_id], _log.to_dict(), MAX_FILES)


func _should_record() -> bool:
	if enabled_override != null:
		return bool(enabled_override)
	return is_recording_enabled(
		bool(SettingsManager.get_setting(&"gameplay", &"telemetry_enabled", true)),
		DisplayServer.get_name() == "headless",
		GameState.automation_mode,
		GameState.tutorial_active,
	)


## Pure gate check mirroring `_should_record()`; safe to call without an autoload.
static func is_recording_enabled(setting_enabled: bool, is_headless: bool, automation_mode: bool, tutorial_active: bool) -> bool:
	return setting_enabled and not is_headless and not automation_mode and not tutorial_active


## Pure recovery check: recovered once the cap elapses or speed regains the ratio.
static func is_recovered(
	current_speed: float, pre_hit_speed: float, elapsed_since_hit: float,
	cap_seconds: float = HIT_RECOVERY_CAP_SECONDS, speed_ratio: float = RECOVERY_SPEED_RATIO,
) -> bool:
	if elapsed_since_hit >= cap_seconds:
		return true
	return absf(current_speed) >= speed_ratio * absf(pre_hit_speed)


## Pure identity gate: only real local human karts are recorded (spec 18d-3);
## AI/scripted/ghost/replay/remote-networked karts use other InputProviders.
static func is_local_human_kart(kart: Node) -> bool:
	return kart is KartController and (kart as KartController).input_provider is PlayerInputProvider


## Writes `data` as JSON to `directory/filename` (atomic tmp+rename, mirrors
## GhostRecording.save_best) then deletes the oldest `*.json` files beyond `keep`.
static func write_and_rotate(directory: String, filename: String, data: Dictionary, keep: int = MAX_FILES) -> Error:
	var make_error: Error = DirAccess.make_dir_recursive_absolute(directory)
	if make_error != OK:
		return make_error
	var path: String = directory.path_join(filename)
	var file: FileAccess = FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	var rename_error: Error = DirAccess.rename_absolute(path + ".tmp", path)
	if rename_error != OK:
		return rename_error
	_rotate(directory, keep)
	return OK


static func _rotate(directory: String, keep: int) -> void:
	var dir: DirAccess = DirAccess.open(directory)
	if dir == null:
		return
	var files: PackedStringArray = PackedStringArray()
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.ends_with(".json"):
			files.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	files.sort()
	while files.size() > keep:
		dir.remove(files[0])
		files.remove_at(0)
