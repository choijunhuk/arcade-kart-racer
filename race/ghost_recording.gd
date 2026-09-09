class_name GhostRecording
extends RefCounted

## Versioned best-lap input stream. Progress is timing metadata, never a pose replay.

## Phase 13 changes hills geometry; reject recordings from older content.
const VERSION: int = 3
const TICK_RATE: int = 60
const MAX_TICKS: int = TICK_RATE * 600
const DEFAULT_DIRECTORY: String = "user://ghosts"
const MAX_MOVERS: int = 64

var track_id: StringName = &""
var initial_state: Dictionary = {}
var frames: Array[Dictionary] = []
var progress: Array[float] = []
var lap_ticks: int = 0
var start_offset: float = 0.0


## Returns a deep JSON-safe copy, allowing callers to retain a completed lap.
func to_dict() -> Dictionary:
	return {"version": VERSION, "tick_rate": TICK_RATE, "track_id": String(track_id),
		"initial_state": initial_state.duplicate(true), "frames": frames.duplicate(true),
		"progress": progress.duplicate(), "lap_ticks": lap_ticks, "start_offset": start_offset}


## Validates saved data before constructing any replay objects or applying state.
static func from_dict(data: Dictionary) -> GhostRecording:
	if data.get("version") != VERSION or data.get("tick_rate") != TICK_RATE:
		return null
	if not data.get("track_id") is String or not data.get("initial_state") is Dictionary:
		return null
	if not data.get("frames") is Array or not data.get("progress") is Array:
		return null
	var raw_frames: Array = data["frames"]
	var raw_progress: Array = data["progress"]
	if raw_frames.is_empty() or raw_frames.size() > MAX_TICKS or raw_frames.size() != raw_progress.size():
		return null
	var ticks: Variant = data.get("lap_ticks")
	if not (ticks is int or ticks is float) or not is_finite(float(ticks)):
		return null
	if float(ticks) != floorf(float(ticks)) or int(ticks) <= 0 or absf(float(ticks) - raw_frames.size()) > 1.0:
		return null
	if not KartReplayState.is_valid(data["initial_state"]):
		return null
	var recording: GhostRecording = GhostRecording.new()
	recording.track_id = StringName(data["track_id"])
	recording.initial_state = KartReplayState.normalize_json(data["initial_state"])
	recording.lap_ticks = int(ticks)
	var start: Variant = data.get("start_offset", 0.0)
	var count: Variant = recording.initial_state.get("mover_count", 0)
	if not (start is int or start is float) or not is_finite(float(start)):
		return null
	if not (count is int or count is float) or not is_finite(float(count)):
		return null
	if float(count) != floorf(float(count)) or float(count) < 0.0 or float(count) > MAX_MOVERS:
		return null
	recording.start_offset = float(start)
	var mover_count: int = int(count)
	for index: int in range(raw_frames.size()):
		if not raw_frames[index] is Dictionary or not _valid_frame(raw_frames[index]):
			return null
		if not GhostWorldReplay.valid_poses(raw_frames[index].get("movers", []), mover_count):
			return null
		var distance: Variant = raw_progress[index]
		if not (distance is float or distance is int) or not is_finite(float(distance)):
			return null
		var frame: Dictionary = InputFrame.from_dict(raw_frames[index]).to_dict()
		if raw_frames[index].has("events"):
			frame["events"] = raw_frames[index]["events"].duplicate(true)
		if raw_frames[index].has("movers"):
			frame["movers"] = raw_frames[index]["movers"].duplicate(true)
		recording.frames.append(frame)
		recording.progress.append(float(distance))
	return recording


## Replaces a track's ghost only when this lap beats its existing input recording.
func save_best(directory: String = DEFAULT_DIRECTORY) -> Error:
	if String(track_id).is_empty() or not String(track_id).is_valid_filename() or from_dict(to_dict()) == null:
		return ERR_INVALID_DATA
	var previous: GhostRecording = load_best(track_id, directory)
	if previous != null and previous.lap_ticks <= lap_ticks:
		return ERR_ALREADY_EXISTS
	var error: Error = DirAccess.make_dir_recursive_absolute(directory)
	if error != OK:
		return error
	var path: String = directory.path_join("%s.json" % track_id)
	var file: FileAccess = FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(to_dict()))
	file.close()
	return DirAccess.rename_absolute(path + ".tmp", path)


## Returns a validated best ghost, or null for absent/incompatible/corrupt data.
static func load_best(id: StringName, directory: String = DEFAULT_DIRECTORY) -> GhostRecording:
	if not String(id).is_valid_filename():
		return null
	var path: String = directory.path_join("%s.json" % id)
	if not FileAccess.file_exists(path):
		return null
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not value is Dictionary:
		return null
	var result: GhostRecording = from_dict(value)
	return result if result != null and result.track_id == id else null


## Finds recorded elapsed time at the same forward progress for the HUD delta.
func seconds_at_progress(distance: float) -> float:
	for index: int in range(progress.size()):
		if progress[index] >= distance:
			return float(index) / float(TICK_RATE)
	return float(lap_ticks) / float(TICK_RATE)


static func _valid_frame(frame: Dictionary) -> bool:
	for key: String in ["throttle", "brake", "steer", "tick"]:
		var value: Variant = frame.get(key)
		if not (value is float or value is int) or not is_finite(float(value)):
			return false
		if key != "tick" and absf(float(value)) > 1.0:
			return false
	for key: String in ["drift", "drift_pressed", "item", "look_back"]:
		if not frame.get(key) is bool:
			return false
	if not frame.get("events", []) is Array:
		return false
	for event: Variant in frame.get("events", []):
		if not event is Dictionary or not KartReplayState.valid_event(event):
			return false
	return true
