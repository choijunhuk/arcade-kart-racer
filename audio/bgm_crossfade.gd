class_name BgmCrossfade
extends RefCounted

## Two-voice music envelope advanced explicitly for deterministic headless tests.

const DEFAULT_FADE_SECONDS: float = 1.0

var current_id: StringName = &""
var pitch_scale: float = 1.0
var gains: Vector2 = Vector2.ZERO
var _voices: Array[AudioVoice] = []
var _ids: Array[StringName] = [&"", &""]
var _from: Vector2 = Vector2.ZERO
var _target: Vector2 = Vector2.ZERO
var _elapsed: float = 0.0
var _duration: float = 0.0


## Borrows the pool's two permanently reserved non-positional voices.
func configure(first: AudioVoice, second: AudioVoice) -> void:
	_voices.assign([first, second])


## Starts or redirects a fade from current gains; same-track requests are idempotent.
func play(id: StringName, stream: AudioStream, volume_db: float, duration: float) -> void:
	if id == current_id:
		return
	var index: int = _ids.find(id)
	if index < 0:
		index = 0 if gains.x <= gains.y else 1
		_voices[index].start(stream, &"Music", volume_db, pitch_scale, true, 0.0)
		_ids[index] = id
		gains[index] = 0.0
	elif not _voices[index].active:
		_voices[index].start(stream, &"Music", volume_db, pitch_scale, true, 0.0)
	current_id = id
	_target = Vector2.ZERO
	_target[index] = 1.0
	_begin_fade(duration)


## Fades both tracks to silence, or stops immediately at zero duration.
func stop(duration: float = DEFAULT_FADE_SECONDS) -> void:
	current_id = &""
	_target = Vector2.ZERO
	_begin_fade(duration)


## Updates both voices so pitch changes also affect outgoing music.
func set_pitch(value: float) -> void:
	pitch_scale = maxf(AudioVoice.MIN_PITCH, value)
	_apply()


## Advances the envelope, clamps overshoot, and stops inaudible outgoing voices.
func step(delta: float) -> void:
	_elapsed = minf(_duration, _elapsed + maxf(delta, 0.0))
	var weight: float = 1.0 if _duration <= 0.0 else _elapsed / _duration
	gains = _from.lerp(_target, weight)
	_apply()
	if weight >= 1.0:
		for index: int in range(_voices.size()):
			if _target[index] <= 0.0:
				_voices[index].stop()


func _begin_fade(duration: float) -> void:
	_from = gains
	_elapsed = 0.0
	_duration = maxf(0.0, duration)
	step(0.0)


func _apply() -> void:
	for index: int in range(_voices.size()):
		_voices[index].update(gains[index], pitch_scale)
