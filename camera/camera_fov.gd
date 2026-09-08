class_name CameraFov
extends RefCounted

## Speed-squared FOV plus a spring-damped normalized boost kick.

var _tuning: FeelTuning
var _boost_amount: float = 0.0
var _boost_velocity: float = 0.0


## Applies the data resource used by subsequent FOV steps.
func configure(tuning: FeelTuning) -> void:
	_tuning = tuning
	_boost_amount = 0.0
	_boost_velocity = 0.0


## Advances the boost spring and returns the settings-scaled target FOV.
func step(speed_ratio: float, boosting: bool, delta: float, strength: float) -> float:
	if _tuning == null:
		return 70.0
	var target_boost: float = 1.0 if boosting else 0.0
	var acceleration: float = (target_boost - _boost_amount) * _tuning.boost_fov_spring_stiffness
	acceleration -= _boost_velocity * _tuning.boost_fov_spring_damping
	_boost_velocity += acceleration * maxf(delta, 0.0)
	_boost_amount = clampf(_boost_amount + _boost_velocity * maxf(delta, 0.0), 0.0, 1.0)
	return compute_target(
		_tuning.base_fov, _tuning.speed_fov_add, _tuning.boost_fov_add,
		speed_ratio, _boost_amount, strength,
	)


## Pure Phase 8 FOV formula; strength scales every effect above base FOV.
static func compute_target(
	base_fov: float, speed_add: float, boost_add: float,
	speed_ratio: float, boost_amount: float, strength: float,
) -> float:
	var ratio: float = clampf(speed_ratio, 0.0, 1.0)
	var effect: float = speed_add * ratio * ratio + boost_add * clampf(boost_amount, 0.0, 1.0)
	return base_fov + effect * clampf(strength, 0.0, 1.0)
