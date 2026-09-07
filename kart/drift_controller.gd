class_name DriftController
extends Node

## Deterministic drift and trick state machine. Runtime ownership is optional so
## `step()` can be driven directly by unit tests without a scene tree.

signal drift_started(direction: int)
signal drift_tier_changed(tier: int)
signal drift_ended(released_tier: int)
signal hop_requested(vertical_impulse: float)
signal boost_requested(spec: BoostSpecData, source: StringName)

enum DriftState {
	NONE,
	HOP,
	HOLD,
	RELEASE,
}

var _tuning: PhysicsTuning
var _kart_data: KartData
var _owner_kart: KartController
var _state: DriftState = DriftState.NONE
var _direction: int = 0
var _charge: float = 0.0
var _tier: int = 0
var _released_tier: int = 0
var _hop_elapsed: float = 0.0
var _low_speed_elapsed: float = 0.0
var _opposite_elapsed: float = 0.0
var _cooldown_remaining: float = 0.0
var _trick_armed: bool = false
var _was_grounded: bool = true
var _pending_boost_spec: BoostSpecData


## Configures data dependencies without requiring scene ownership.
func configure(tuning: PhysicsTuning, kart_data: KartData) -> void:
	_tuning = tuning
	_kart_data = kart_data


## Adds the runtime kart owner used only for global EventBus payloads.
func set_owner_kart(owner_kart: KartController) -> void:
	_owner_kart = owner_kart


## Advances drift/trick state from explicit inputs and returns one physics request.
func step(
	frame: InputFrame, speed: float, grounded: bool, air_time: float,
	yaw_rate: float, is_hit: bool, dt: float,
) -> KartPhysics.DriftResult:
	if _tuning == null or _kart_data == null:
		push_error("DriftController must be configured before step()")
		return KartPhysics.DriftResult.new()
	_cooldown_remaining = maxf(0.0, _cooldown_remaining - dt)
	_update_trick(frame, grounded, air_time)
	match _state:
		DriftState.NONE:
			_try_begin_hop(frame, speed, grounded)
		DriftState.HOP:
			_update_hop(frame, dt)
		DriftState.HOLD:
			_update_hold(frame, speed, grounded, air_time, yaw_rate, is_hit, dt)
		DriftState.RELEASE:
			_state = DriftState.NONE
	_was_grounded = grounded
	return _build_result()


## Returns the current state enum for HUD/debug/tests.
func get_state() -> DriftState:
	return _state


## Returns the direction locked at hop completion (-1 or +1).
func get_direction() -> int:
	return _direction


## Returns monotonically increasing charge for the active drift.
func get_charge() -> float:
	return _charge


## Returns the highest reached mini-turbo tier, or zero.
func get_tier() -> int:
	return _tier


## Returns the tier captured by the most recent release.
func get_released_tier() -> int:
	return _released_tier


## Returns whether an eligible airborne trick is waiting for landing.
func is_trick_armed() -> bool:
	return _trick_armed


## Returns a release/trick boost request until the runtime consumes it.
func get_pending_boost_spec() -> BoostSpecData:
	return _pending_boost_spec


## Clears the pending request after BoostController accepts it.
func clear_pending_boost_spec() -> void:
	_pending_boost_spec = null


## Returns normalized charge toward the final configured tier.
func get_charge_ratio() -> float:
	if _tuning == null or _tuning.mini_turbo_tiers.is_empty():
		return 0.0
	return clampf(_charge / _tuning.mini_turbo_tiers.back().charge_seconds, 0.0, 1.0)


## Returns the tier-derived unsigned body yaw angle in degrees, or zero
## outside an active drift hold.
func get_visual_angle_degrees() -> float:
	if _state != DriftState.HOLD:
		return 0.0
	if _tier > 0 and _tier <= _tuning.drift_visual_angles_degrees.size():
		return _tuning.drift_visual_angles_degrees[_tier - 1]
	if not _tuning.drift_visual_angles_degrees.is_empty():
		return _tuning.drift_visual_angles_degrees[0]
	return 0.0


func _try_begin_hop(frame: InputFrame, speed: float, grounded: bool) -> void:
	if _cooldown_remaining > 0.0 or not frame.drift_pressed or not grounded:
		return
	if speed <= _tuning.drift_min_speed or absf(frame.steer) < _tuning.drift_min_steer:
		return
	_state = DriftState.HOP
	_hop_elapsed = 0.0
	hop_requested.emit(_tuning.drift_hop_impulse)


func _update_hop(frame: InputFrame, dt: float) -> void:
	_hop_elapsed += dt
	if _hop_elapsed < _tuning.drift_hop_duration:
		return
	if absf(frame.steer) < _tuning.drift_min_steer or not frame.drift:
		_end_without_reward()
		return
	_direction = 1 if frame.steer > 0.0 else -1
	_state = DriftState.HOLD
	_emit_drift_started()


func _update_hold(
	frame: InputFrame, speed: float, grounded: bool, air_time: float,
	yaw_rate: float, is_hit: bool, dt: float,
) -> void:
	if is_hit or (not grounded and air_time > _tuning.drift_airborne_cancel_time):
		_end_without_reward()
		return
	_low_speed_elapsed = _low_speed_elapsed + dt if speed < _tuning.drift_cancel_speed else 0.0
	if _low_speed_elapsed >= _tuning.drift_cancel_delay:
		_end_without_reward()
		return
	if not frame.drift:
		_release()
		return
	var strong_opposite: bool = frame.steer * float(_direction) <= -_tuning.drift_min_steer
	_opposite_elapsed = _opposite_elapsed + dt if strong_opposite else 0.0
	if _opposite_elapsed >= _tuning.drift_opposite_cancel_delay:
		_end_without_reward()
		return
	if not strong_opposite:
		_accumulate_charge(frame.steer, yaw_rate, dt)


func _accumulate_charge(steer: float, yaw_rate: float, dt: float) -> void:
	var alignment: float = maxf(0.0, steer * float(_direction))
	var turn_quality: float = 1.0 if absf(yaw_rate) >= _tuning.min_drift_yaw_rate else _tuning.low_turn_quality_mult
	var rate: float = _tuning.base_charge_rate
	rate *= 1.0 + _tuning.steer_alignment_bonus * alignment
	rate *= turn_quality * _kart_data.drift_charge_mult
	_charge += rate * dt
	_update_tier()


func _update_tier() -> void:
	var reached: int = 0
	for tier_data: MiniTurboTier in _tuning.mini_turbo_tiers:
		if _charge + 0.000001 >= tier_data.charge_seconds:
			reached = maxi(reached, tier_data.tier)
	if reached == _tier:
		return
	_tier = reached
	drift_tier_changed.emit(_tier)
	if _owner_kart != null and is_inside_tree():
		EventBus.drift_tier_changed.emit(_owner_kart, _tier)


func _release() -> void:
	_released_tier = _tier
	_state = DriftState.RELEASE
	if _released_tier > 0:
		_pending_boost_spec = _boost_spec_for_tier(_released_tier)
		boost_requested.emit(_pending_boost_spec, StringName("mini_turbo_%d" % _released_tier))
	_emit_drift_ended(_released_tier)
	_begin_cooldown()


func _end_without_reward() -> void:
	_released_tier = 0
	_emit_drift_ended(0)
	_begin_cooldown()
	_state = DriftState.NONE


func _begin_cooldown() -> void:
	_cooldown_remaining = _tuning.drift_cooldown
	_direction = 0
	_charge = 0.0
	_tier = 0
	_hop_elapsed = 0.0
	_low_speed_elapsed = 0.0
	_opposite_elapsed = 0.0


func _boost_spec_for_tier(tier: int) -> BoostSpecData:
	for tier_data: MiniTurboTier in _tuning.mini_turbo_tiers:
		if tier_data.tier != tier:
			continue
		var spec: BoostSpecData = BoostSpecData.new()
		spec.id = StringName("mini_turbo_%d" % tier)
		spec.speed_mult = tier_data.speed_mult
		spec.accel_mult = tier_data.accel_mult
		spec.duration = tier_data.duration
		spec.priority = tier
		return spec
	return null


func _update_trick(frame: InputFrame, grounded: bool, air_time: float) -> void:
	if not grounded and air_time >= _tuning.trick_min_air_time and frame.drift_pressed:
		_trick_armed = true
	if grounded and not _was_grounded and _trick_armed:
		_pending_boost_spec = _tuning.trick_boost
		_trick_armed = false
		boost_requested.emit(_pending_boost_spec, &"trick")


func _build_result() -> KartPhysics.DriftResult:
	var result: KartPhysics.DriftResult = KartPhysics.DriftResult.new()
	if _state != DriftState.HOLD:
		return result
	result.is_drifting = true
	result.drift_dir = float(_direction)
	result.steer_influence = _tuning.drift_steer_influence
	result.grip = _tuning.drift_grip
	result.speed_retention = _tuning.drift_speed_retention
	result.visual_angle_degrees = get_visual_angle_degrees()
	return result


func _emit_drift_started() -> void:
	drift_started.emit(_direction)
	if _owner_kart != null and is_inside_tree():
		EventBus.drift_started.emit(_owner_kart, _direction)


func _emit_drift_ended(released_tier: int) -> void:
	drift_ended.emit(released_tier)
	if _owner_kart != null and is_inside_tree():
		EventBus.drift_ended.emit(_owner_kart, released_tier)
