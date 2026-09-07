class_name SlipstreamSensor
extends Node

## Detects a same-direction kart ahead and advances deterministic charge/exit
## timers. The exit bonus temporarily feeds KartPhysics.BoostResult until the
## Phase 3 BoostController owns all boost sources.

class TimerResult extends RefCounted:
	var charge_time: float = 0.0
	var active: bool = false
	var exit_remaining: float = 0.0
	var speed_mult: float = 1.0


var _cast: ShapeCast3D
var _owner_kart: KartController
var _tuning: PhysicsTuning
var _charge_time: float = 0.0
var _active: bool = false
var _exit_remaining: float = 0.0


## Wires the forward cast and excludes the owning kart from detection.
func setup(cast: ShapeCast3D, owner_kart: KartController, tuning: PhysicsTuning) -> void:
	_cast = cast
	_owner_kart = owner_kart
	_tuning = tuning
	_cast.target_position = Vector3(0.0, 0.0, -tuning.slipstream_range)
	_cast.add_exception(owner_kart)


## Advances detection and returns the current speed multiplier.
func tick(delta: float) -> TimerResult:
	var result: TimerResult = advance_timer(
		_has_same_direction_target(), delta, _charge_time, _active,
		_exit_remaining, _tuning,
	)
	_charge_time = result.charge_time
	_active = result.active
	_exit_remaining = result.exit_remaining
	return result


## Returns whether full slipstream charge is currently sustained.
func is_active() -> bool:
	return _active


## Pure timer transition for deterministic unit tests.
static func advance_timer(
	has_target: bool, delta: float, charge_time: float, was_active: bool,
	exit_remaining: float, tuning: PhysicsTuning,
) -> TimerResult:
	var result: TimerResult = TimerResult.new()
	result.charge_time = charge_time
	result.active = was_active
	result.exit_remaining = maxf(0.0, exit_remaining)
	if has_target:
		result.charge_time = minf(tuning.slipstream_time, charge_time + delta)
		result.active = result.charge_time >= tuning.slipstream_time
		result.exit_remaining = 0.0
	elif was_active:
		result.charge_time = 0.0
		result.active = false
		result.exit_remaining = tuning.slipstream_exit_duration
	else:
		result.charge_time = 0.0
		result.exit_remaining = maxf(0.0, result.exit_remaining - delta)
	if result.active:
		result.speed_mult = tuning.slipstream_speed_mult
	elif result.exit_remaining > 0.0 and tuning.slipstream_exit_boost != null:
		result.speed_mult = tuning.slipstream_exit_boost.speed_mult
	return result


func _has_same_direction_target() -> bool:
	_cast.force_shapecast_update()
	for index: int in _cast.get_collision_count():
		var collider: Object = _cast.get_collider(index)
		if collider is KartController:
			var other: KartController = collider as KartController
			if _owner_kart.get_forward().dot(other.get_forward()) >= _tuning.slipstream_direction_dot:
				return true
	return false
