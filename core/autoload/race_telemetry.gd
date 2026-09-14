class_name RaceTelemetryService
extends Node

## Phase 18d-3 glue: turns real EventBus signals from local human karts into
## one `RaceTelemetryLog` per recorded local kart and writes one file per
## kart to disk on RESULTS (18d-3 review fix #1: split-screen must not merge
## every local kart's events into a single shared bucket). Gating,
## hit-recovery math, and identity checks are pure static functions below so
## they are testable without a scene tree; only signal wiring and file I/O
## are stateful here. `enabled_override`/`telemetry_directory`/
## `track_id_override` let tests drive a real instance without touching
## `user://`. `player_index` follows the active race's stable local-human
## roster (`RaceManager.get_human_karts()`, or `roster_override` in tests),
## not signal-arrival order (18d-4 review fix #1).

const DEFAULT_DIRECTORY: String = "user://telemetry"
## Number of RACES (not raw files) kept per telemetry directory (18d-4
## review fix #4). One race now writes one file per recorded local human
## kart (split-screen), so counting raw files would let a single newer race
## evict an older race's files one player at a time instead of rotating
## whole races out together. `_rotate()` groups files by their shared
## "<stamp>-<track_id>" prefix (everything before the trailing
## "-p<N>[-<suffix>].json") and keeps the newest `MAX_FILES` such groups.
const MAX_FILES: int = 20
## Sane upper bound on `<stem>-N.<ext>` collision-suffix attempts before
## `_resolve_collision_free_filename()` gives up (18d-4 review fix #3).
## Unrelated to `MAX_FILES`: this only guards the rare same-second-write
## retry loop, not how many files/races are kept on disk.
const MAX_COLLISION_SUFFIX: int = 20
const HIT_RECOVERY_CAP_SECONDS: float = 10.0
const RECOVERY_SPEED_RATIO: float = 0.8

var telemetry_directory: String = DEFAULT_DIRECTORY
## Test-only escape hatch: non-null replaces the full recording gate.
var enabled_override: Variant = null
## Test-only escape hatch: non-null replaces GameState.selected_track_id in the filename.
var track_id_override: Variant = null
## Test-only escape hatch: non-null Array replaces the stable local-human
## roster normally read from `RaceManager.get_human_karts()` on race_started
## (18d-4 review fix #1).
var roster_override: Variant = null

var _recording: bool = false
var _elapsed_seconds: float = 0.0
## kart instance id -> RaceTelemetryLog, one per recorded local kart.
var _logs: Dictionary = {}
## kart instance id -> stable 0-based player index (join order for this race).
var _player_index: Dictionary = {}
var _known_karts: Dictionary = {}
var _last_speed: Dictionary = {}
## kart instance id -> {"hit_time": float, "pre_hit_speed": float, "pending_hits": int}
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
	if not _recording:
		return
	_elapsed_seconds += delta
	for id: Variant in _known_karts:
		var kart: Node = _known_karts[id]
		if is_instance_valid(kart):
			_last_speed[id] = (kart as KartController).get_speed()
	_update_pending_recoveries()


func _on_race_started() -> void:
	_reset_state(_should_record())
	if _recording:
		_prime_roster(_resolve_roster())


func _on_race_state_changed(_old_state: int, new_state: int) -> void:
	if new_state != RaceState.RESULTS or not _recording:
		return
	_close_pending_recoveries_at_race_end()
	_write_logs()
	_reset_state(false)


func _on_drift_started(kart: Node, _direction: int) -> void:
	var log: RaceTelemetryLog = _track(kart)
	if log != null:
		log.drift_started()


func _on_drift_ended(kart: Node, released_tier: int) -> void:
	var log: RaceTelemetryLog = _track(kart)
	if log != null:
		log.drift_ended(released_tier)


func _on_boost_started(kart: Node, _spec: Resource) -> void:
	var log: RaceTelemetryLog = _track(kart)
	if log == null:
		return
	log.boost_started((kart as KartController).boost_controller.get_source())
	_finish_recovery(kart, _elapsed_seconds)


func _on_item_used(kart: Node, _item_id: StringName) -> void:
	var log: RaceTelemetryLog = _track(kart)
	if log != null:
		log.item_used()


func _on_kart_hit(kart: Node, _hit_type: int) -> void:
	var log: RaceTelemetryLog = _track(kart)
	if log == null:
		return
	var id: int = kart.get_instance_id()
	log.hit(_elapsed_seconds)
	if _pending_recovery.has(id):
		# 18d-3 review fix #3: a hit landing before the previous one resolved
		# must not force-close it with a fabricated value at the new hit's
		# time. Keep the original hit_time/pre_hit_speed for gating and just
		# count the extra hit; _close_pending_recovery() replays one
		# log.recovered() call per counted hit once the real criteria (80% of
		# pre-hit speed, a boost starting, or the 10s cap) resolves.
		var pending: Dictionary = _pending_recovery[id]
		pending["pending_hits"] = int(pending["pending_hits"]) + 1
	else:
		_pending_recovery[id] = {
			"hit_time": _elapsed_seconds,
			"pre_hit_speed": float(_last_speed.get(id, (kart as KartController).get_speed())),
			"pending_hits": 1,
		}


func _on_wall_impacted(kart: Node) -> void:
	var log: RaceTelemetryLog = _track(kart)
	if log != null:
		log.wall_impact()


func _on_kart_respawned(kart: Node) -> void:
	var log: RaceTelemetryLog = _track(kart)
	if log != null:
		log.respawn()


func _on_lap_completed(kart: Node, lap: int, lap_time_seconds: float) -> void:
	var log: RaceTelemetryLog = _track(kart)
	if log != null:
		log.lap_completed(lap, lap_time_seconds)


## Returns the local human karts in stable race/grid join order for the
## active race (18d-4 review fix #1; audit finding 3): the current scene's
## `RaceManager` (production always sets this via `GameState.change_scene` ->
## `change_scene_to_packed`, matching `race/race_manager.gd`'s own
## `get_local_human_karts()` — offline every human kart, online only this
## process's own roster slot) or `roster_override` in tests. Returns an
## empty roster when no RaceManager is reachable (e.g. isolated unit tests
## that drive EventBus directly), which leaves `_track()`'s lazy
## first-signal registration as the fallback.
func _resolve_roster() -> Array:
	if roster_override != null:
		return roster_override as Array
	var manager: RaceManager = get_tree().current_scene as RaceManager
	if manager == null:
		return []
	return manager.get_local_human_karts()


## Eagerly opens a log (and reserves its stable player_index) for every
## recorded local human kart in `roster`, in race/grid join order (18d-4
## review fix #2), so a kart that fires zero tracked signals all race still
## gets a file with empty totals instead of being silently absent from
## `_write_logs()`. This is also what makes player_index follow roster order
## rather than whichever kart's tracked EventBus signal arrives first
## (18d-4 review fix #1).
func _prime_roster(roster: Array) -> void:
	for entry: Variant in roster:
		var kart: Node = entry as Node
		if kart != null and is_local_human_kart(kart):
			_register_kart(kart)


## Opens `kart`'s log and reserves its stable 0-based player_index the first
## time it is seen, whether from `_prime_roster()`'s eager pass or lazily
## from its first tracked signal (fallback when no roster was available).
## Split-screen karts never share a bucket either way (18d-3 review fix #1).
func _register_kart(kart: Node) -> void:
	var id: int = kart.get_instance_id()
	if _logs.has(id):
		return
	_known_karts[id] = kart
	_last_speed[id] = (kart as KartController).get_speed()
	if not _player_index.has(id):
		_player_index[id] = _player_index.size()
	_logs[id] = RaceTelemetryLog.new()


## Returns whether `kart` is a local human kart currently being recorded and,
## the first time each kart is seen, opens its own `RaceTelemetryLog` via
## `_register_kart()` (fallback path for karts not covered by
## `_prime_roster()`, e.g. no RaceManager reachable).
func _track(kart: Node) -> RaceTelemetryLog:
	if not _recording or not is_local_human_kart(kart) or not _is_local(kart):
		return null
	_register_kart(kart)
	return _logs[kart.get_instance_id()]


## Excludes a remote-networked kart from this lazy fallback path (audit
## finding 3): `_prime_roster()` already limits eager registration to
## `_resolve_roster()`'s local-only roster, but EventBus signals fire for
## every human kart online too — a remote kart is replicated with the same
## `PlayerInputProvider` this machine's own kart uses, and `is_local_human_kart()`
## only checks that InputProvider type (kept pure/testable on its own), not
## network locality. Offline, `GameState.net_session` is null and every
## `PlayerInputProvider` kart still counts as local, matching prior behavior.
func _is_local(kart: Node) -> bool:
	if GameState.net_session == null:
		return true
	return _resolve_roster().has(kart)


func _update_pending_recoveries() -> void:
	if _pending_recovery.is_empty():
		return
	# `keys()` already returns a fresh Array snapshot (not a live view into the
	# Dictionary), so it is safe to erase from `_pending_recovery` below while
	# iterating it without an extra `.duplicate()` allocation (18d-3 review
	# fix #2: avoid a per-tick allocation when nothing is pending, and avoid
	# doubling it when something is).
	for id: Variant in _pending_recovery.keys():
		var kart: Node = _known_karts.get(id)
		if not is_instance_valid(kart):
			_pending_recovery.erase(id)
			continue
		var pending: Dictionary = _pending_recovery[id]
		var elapsed_since_hit: float = _elapsed_seconds - float(pending["hit_time"])
		var current_speed: float = float(_last_speed.get(id, (kart as KartController).get_speed()))
		if is_recovered(current_speed, float(pending["pre_hit_speed"]), elapsed_since_hit):
			_close_pending_recovery(id, minf(_elapsed_seconds, float(pending["hit_time"]) + HIT_RECOVERY_CAP_SECONDS))
			_pending_recovery.erase(id)


func _finish_recovery(kart: Node, t: float) -> void:
	var id: int = kart.get_instance_id()
	if _pending_recovery.has(id):
		_close_pending_recovery(id, t)
		_pending_recovery.erase(id)


## Closes every hit stacked on kart `id`'s pending recovery at time `t`,
## replaying one `log.recovered()` call per counted hit (see `_on_kart_hit`).
## Does not erase `_pending_recovery[id]`; callers own that.
func _close_pending_recovery(id: int, t: float) -> void:
	var log: RaceTelemetryLog = _logs.get(id)
	if log == null:
		return
	var pending_hits: int = int((_pending_recovery[id] as Dictionary).get("pending_hits", 1))
	for _i: int in range(pending_hits):
		log.recovered(t)


## 18d-3 review fix #3 decision: a recovery still pending when the race ends
## is recorded as CAPPED, not dropped. It is closed at the current elapsed
## time, which is always <= the 10s cap (a genuine cap-triggered close would
## already have resolved it in `_update_pending_recoveries` before now).
## Capping keeps `hits == hit_recovery_seconds.size()` and avoids silently
## excluding slow recoveries from the mean/median that
## `tools/telemetry_summary.gd` reports.
func _close_pending_recoveries_at_race_end() -> void:
	for id: int in _pending_recovery.keys():
		_close_pending_recovery(id, _elapsed_seconds)
	_pending_recovery.clear()


func _write_logs() -> void:
	if _logs.is_empty():
		return
	var track_id: String = String(track_id_override) if track_id_override != null else String(GameState.selected_track_id)
	if track_id.is_empty():
		track_id = "unknown"
	var stamp: String = Time.get_datetime_string_from_system(false, true).replace(":", "").replace("-", "").replace("T", "-")
	for id: int in _logs:
		var player_index: int = int(_player_index.get(id, 0))
		var data: Dictionary = _logs[id].to_dict()
		data["player_index"] = player_index
		_add_kart_identity(data, _known_karts.get(id))
		var filename: String = "%s-%s-p%d.json" % [stamp, track_id, player_index + 1]
		write_and_rotate(telemetry_directory, filename, data, MAX_FILES)


## Adds `kart_id`/`driver_id` to `data` when cheaply available on `kart`
## (plain property reads already on the loaded KartController; spec 18d-3
## review fix #1's "if cheaply available").
func _add_kart_identity(data: Dictionary, kart: Node) -> void:
	if not is_instance_valid(kart) or not (kart is KartController):
		return
	var kart_controller: KartController = kart as KartController
	var kart_data: KartData = kart_controller.get_kart_data()
	if kart_data != null and not String(kart_data.id).is_empty():
		data["kart_id"] = String(kart_data.id)
	var driver_data: DriverData = kart_controller.get_driver_data()
	if driver_data != null and not String(driver_data.id).is_empty():
		data["driver_id"] = String(driver_data.id)


func _reset_state(recording: bool) -> void:
	_recording = recording
	_elapsed_seconds = 0.0
	_logs.clear()
	_player_index.clear()
	_known_karts.clear()
	_last_speed.clear()
	_pending_recovery.clear()


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
## GhostRecording.save_best) then rotates out the oldest races beyond `keep`
## (see `TelemetryFileRotation`, split out to stay under this file's
## 400-line budget). 18d-3 review fix #4: if `filename` already exists (two
## files written within the same second, e.g. two local players), the write
## is retried under `<stem>-2.<ext>`, `<stem>-3.<ext>`, ... until a free name
## is found, so no writer ever clobbers another's file. 18d-4 review fix #3:
## if every suffix up to `MAX_COLLISION_SUFFIX` is already taken, the write
## is skipped entirely (with a single `push_warning`) rather than clobbering
## the last candidate tried.
static func write_and_rotate(directory: String, filename: String, data: Dictionary, keep: int = MAX_FILES) -> Error:
	var make_error: Error = DirAccess.make_dir_recursive_absolute(directory)
	if make_error != OK:
		return make_error
	var resolved_filename: String = TelemetryFileRotation.resolve_collision_free_filename(directory, filename, MAX_COLLISION_SUFFIX)
	if resolved_filename.is_empty():
		push_warning("RaceTelemetryService: skipping write for '%s' — no free filename found after %d collision suffixes" % [filename, MAX_COLLISION_SUFFIX])
		return ERR_ALREADY_EXISTS
	var path: String = directory.path_join(resolved_filename)
	var file: FileAccess = FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	var rename_error: Error = DirAccess.rename_absolute(path + ".tmp", path)
	if rename_error != OK:
		return rename_error
	TelemetryFileRotation.rotate(directory, keep)
	return OK
