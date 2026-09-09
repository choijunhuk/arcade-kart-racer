class_name TimeTrialGhost
extends Node

## Records complete valid laps and owns a non-interacting replay of the best lap.

const MILLISECONDS_PER_SECOND: float = 1000.0
var ghost_directory: String = GhostRecording.DEFAULT_DIRECTORY
var best: GhostRecording
var playback: GhostPlayback
var completed_recording: GhostRecording
var current_ticks: int = 0
var last_save_error: Error = OK
var _kart: KartController
var _track: TrackRoot
var _track_id: StringName
var _provider: RecordingInputProvider
var _recording: GhostRecording
var _last_lap_seconds: float = 0.0
var _valid_lap: bool = true
var _active: bool = false
var _progress: float = 0.0
var _previous_offset: float = 0.0
var _total_laps: int = 3


## Wraps the player's chosen input source without introducing AI or item systems.
func setup(kart: KartController, track: TrackRoot, id: StringName, total_laps: int = 3) -> void:
	_kart = kart
	_track = track
	_track_id = id
	_total_laps = total_laps
	_provider = RecordingInputProvider.new(kart.input_provider)
	for child: Node in track.get_node("MovingObstacles").get_children():
		if child is MovingObstacle:
			_provider.movers.append(child as MovingObstacle)
	kart.set_input_provider(_provider)
	kart.replay_event_received.connect(_provider.record_event)
	EventBus.lap_completed.connect(_on_lap)
	EventBus.kart_respawned.connect(_on_respawn)
	EventBus.race_started.connect(start)
	best = GhostRecording.load_best(id, ghost_directory)


## Captures the GO state after countdown start-boost/wheelspin decisions.
func start() -> void:
	_active = true
	_begin_lap()


func _physics_process(delta: float) -> void:
	if not _active:
		return
	if _recording.frames.size() > _recording.progress.size():
		var offset: float = _track.get_racing_line().offset_at(_kart.global_position, _previous_offset)
		var length: float = _track.get_lap_length()
		_progress += fposmod(offset - _previous_offset + length * 0.5, length) - length * 0.5
		_previous_offset = offset
		_recording.progress.append(maxf(0.0, _progress))
	current_ticks = _recording.frames.size()
	if playback != null:
		playback.step(delta)


## Stops recording after finish but preserves the saved best for result display.
func stop() -> void:
	_active = false
	_provider.recording = null


## Current lap elapsed time is counted in the same fixed ticks as the recording.
func current_seconds() -> float:
	return float(current_ticks) / float(GhostRecording.TICK_RATE)


## Returns the saved best in seconds, or -1 until a valid lap has been recorded.
func best_seconds() -> float:
	return float(best.lap_ticks) / float(GhostRecording.TICK_RATE) if best != null else -1.0


## Positive means behind the saved ghost at the same forward lap progress.
func delta_seconds() -> float:
	return current_seconds() - best.seconds_at_progress(maxf(0.0, _progress)) if best != null else 0.0


func _begin_lap() -> void:
	_recording = GhostRecording.new()
	_recording.track_id = _track_id
	_recording.initial_state = KartReplayState.capture(_kart)
	_recording.initial_state["mover_count"] = _provider.movers.size()
	_recording.start_offset = _track.get_racing_line().offset_at(_kart.global_position)
	_provider.recording = _recording
	_provider.pending_events.clear()
	_previous_offset = _recording.start_offset
	_progress = 0.0
	current_ticks = 0
	_valid_lap = true
	_reset_playback.call_deferred()


func _reset_playback() -> void:
	if playback != null:
		playback.free()
		playback = null
	if best != null and _active:
		playback = GhostPlayback.new()
		add_child(playback)
		playback.setup(best, _track)


func _on_lap(kart: Node, lap: int, cumulative_seconds: float) -> void:
	if kart != _kart or not _active:
		return
	var lap_ticks: int = roundi((cumulative_seconds - _last_lap_seconds) * GhostRecording.TICK_RATE)
	_last_lap_seconds = cumulative_seconds
	_recording.lap_ticks = lap_ticks
	if _valid_lap and (best == null or lap_ticks < best.lap_ticks):
		completed_recording = GhostRecording.from_dict(_recording.to_dict())
		if completed_recording != null:
			last_save_error = completed_recording.save_best(ghost_directory)
			if last_save_error == OK:
				best = completed_recording
			elif last_save_error != ERR_ALREADY_EXISTS:
				push_warning("Ghost could not be saved: %s" % error_string(last_save_error))
	if lap < _total_laps:
		_begin_lap()
	else:
		stop()


func _on_respawn(kart: Node) -> void:
	if kart == _kart:
		_valid_lap = false
