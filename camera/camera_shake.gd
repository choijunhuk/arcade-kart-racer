class_name CameraShake
extends RefCounted

## Deterministic trauma model for camera-only rotation and position offsets.

class Sample extends RefCounted:
	var rotation_offset: Vector3 = Vector3.ZERO
	var position_offset: Vector3 = Vector3.ZERO

const NOISE_SEED: int = 8_047
const ROTATION_NOISE_OFFSET: float = 31.0
const POSITION_NOISE_OFFSET: float = 67.0

var _tuning: FeelTuning
var _trauma: float = 0.0
var _elapsed: float = 0.0
var _noise: FastNoiseLite = FastNoiseLite.new()


## Applies camera tuning and resets the deterministic noise stream.
func configure(tuning: FeelTuning) -> void:
	_tuning = tuning
	_noise.seed = NOISE_SEED
	_noise.frequency = tuning.shake_noise_frequency


## Adds a trauma source and clamps the accumulator to its readable range.
func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + maxf(amount, 0.0), 0.0, 1.0)


## Advances noise and decay, returning one bounded local-space shake sample.
func step(delta: float, strength: float) -> Sample:
	var sample: Sample = Sample.new()
	if _tuning == null:
		return sample
	_elapsed += maxf(delta, 0.0)
	var amplitude: float = scaled_amplitude(_trauma, strength)
	if amplitude > 0.0:
		var rotation_noise: Vector3 = _noise_vector(_elapsed)
		var position_noise: Vector3 = _noise_vector(_elapsed + POSITION_NOISE_OFFSET)
		sample.rotation_offset = rotation_noise * deg_to_rad(_tuning.maximum_shake_rotation_degrees) * amplitude
		sample.position_offset = position_noise * _tuning.maximum_shake_position * amplitude
	_trauma = decay_trauma(_trauma, _tuning.trauma_decay, delta)
	return sample


## Returns the current normalized trauma accumulator for tests/debug HUD.
func get_trauma() -> float:
	return _trauma


## Clears all pending trauma without changing noise continuity.
func clear() -> void:
	_trauma = 0.0


## Pure linear decay used by the runtime and unit tests.
static func decay_trauma(trauma: float, decay: float, delta: float) -> float:
	return maxf(0.0, clampf(trauma, 0.0, 1.0) - maxf(decay, 0.0) * maxf(delta, 0.0))


## Pure trauma-squared amplitude with a normalized settings multiplier.
static func scaled_amplitude(trauma: float, strength: float) -> float:
	var normalized_trauma: float = clampf(trauma, 0.0, 1.0)
	return normalized_trauma * normalized_trauma * clampf(strength, 0.0, 1.0)


func _noise_vector(sample_time: float) -> Vector3:
	var value: Vector3 = Vector3(
		_noise.get_noise_1d(sample_time),
		_noise.get_noise_1d(sample_time + ROTATION_NOISE_OFFSET),
		_noise.get_noise_1d(sample_time + ROTATION_NOISE_OFFSET * 2.0),
	)
	return value.normalized() if value.length_squared() > 1.0 else value
