class_name AudioVoice
extends RefCounted

## One reusable lease and its preallocated positional or non-positional player.

const SILENCE_DB: float = -80.0
const MIN_PITCH: float = 0.01
const LOOP_LIFETIME: float = -1.0

var spatial: AudioStreamPlayer3D
var flat: AudioStreamPlayer
var reserved: bool = false
var active: bool = false
var owner_id: int = 0
var sound_id: StringName = &""
var priority: int = 0
var sequence: int = 0
var remaining: float = 0.0
var base_volume_db: float = 0.0
var pitch: float = 1.0
var pauses_with_world: bool = true
var _playback_enabled: bool = DisplayServer.get_name() != "headless"


## Reuses this slot for a stream; callers assign lease identity before starting.
func start(stream: AudioStream, bus: StringName, volume: float, pitch_scale: float, looped: bool, initial_gain: float = 1.0) -> void:
	stop()
	active = true
	base_volume_db = volume
	pitch = maxf(MIN_PITCH, pitch_scale)
	remaining = LOOP_LIFETIME if looped else stream.get_length()
	var initial_db: float = SILENCE_DB if initial_gain <= 0.0 else volume + linear_to_db(initial_gain)
	if spatial != null:
		spatial.stream = stream
		spatial.bus = bus
		spatial.pitch_scale = pitch
		spatial.volume_db = initial_db
		if _playback_enabled:
			spatial.play()
	else:
		flat.stream = stream
		flat.bus = bus
		flat.pitch_scale = pitch
		flat.volume_db = initial_db
		if _playback_enabled:
			flat.play()


## Stops playback without freeing a player or changing lease identity.
func stop() -> void:
	active = false
	remaining = 0.0
	if spatial != null:
		spatial.stop()
	else:
		flat.stop()


## Updates presentation gain/pitch and optional tracked position in place.
func update(gain: float, pitch_scale: float, world_position: Vector3 = Vector3.ZERO) -> void:
	pitch = maxf(MIN_PITCH, pitch_scale)
	var db: float = SILENCE_DB if gain <= 0.0 else base_volume_db + linear_to_db(gain)
	if spatial != null:
		spatial.global_position = world_position
		spatial.volume_db = db
		spatial.pitch_scale = pitch
	else:
		flat.volume_db = db
		flat.pitch_scale = pitch


## Applies pause to world voices only; UI and music remain live.
func set_paused(paused: bool) -> void:
	if spatial != null:
		spatial.stream_paused = paused and pauses_with_world
	else:
		flat.stream_paused = paused and pauses_with_world


## Expires one-shots using explicit elapsed time, independent of the audio device.
func step(delta: float, paused: bool) -> void:
	set_paused(paused)
	if not active or remaining == LOOP_LIFETIME or (paused and pauses_with_world):
		return
	remaining = maxf(0.0, remaining - maxf(delta, 0.0) * pitch)
	if remaining <= 0.0:
		stop()
