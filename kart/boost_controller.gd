class_name BoostController
extends Node

## Owns one non-additive boost slot and deterministic expiry/extension rules.

signal boost_started(spec: BoostSpecData)
signal boost_ended()

enum StartInputOutcome {
	NONE,
	TIER_ONE,
	TIER_TWO,
	WHEELSPIN,
}

class StartInputResult extends RefCounted:
	var outcome: StartInputOutcome = StartInputOutcome.NONE
	var boost_spec: BoostSpecData
	var wheelspin_duration: float = 0.0

var _tuning: PhysicsTuning
var _kart_data: KartData
var _owner_kart: KartController
var _active_spec: BoostSpecData
var _source: StringName = &""
var _remaining: float = 0.0


## Configures tuning and per-kart boost strength without scene ownership.
func configure(tuning: PhysicsTuning, kart_data: KartData) -> void:
	_tuning = tuning
	_kart_data = kart_data


## Adds the runtime kart owner used only for EventBus payloads.
func set_owner_kart(owner_kart: KartController) -> void:
	_owner_kart = owner_kart


## Requests a boost using replacement-or-extension stacking from spec section 11.
func request(spec: BoostSpecData, source: StringName) -> void:
	if spec == null or _tuning == null:
		push_error("BoostController.request requires configured tuning and a spec")
		return
	if _active_spec == null or spec.speed_mult > _active_spec.speed_mult:
		_active_spec = spec
		_source = source
		_remaining = minf(spec.duration, _tuning.max_boost_duration)
		_emit_started(spec)
	else:
		_remaining = minf(_remaining + spec.duration, _tuning.max_boost_duration)


## Advances expiry and returns the current immutable physics request.
func step(dt: float) -> KartPhysics.BoostResult:
	if _active_spec != null:
		_remaining = maxf(0.0, _remaining - dt)
		if _remaining <= 0.0:
			_end_boost()
	return get_result()


## Returns a snapshot of the current boost without advancing time.
func get_result() -> KartPhysics.BoostResult:
	var result: KartPhysics.BoostResult = KartPhysics.BoostResult.new()
	if _active_spec == null:
		return result
	var power: float = _kart_data.boost_power if _kart_data != null else 1.0
	result.active = true
	result.speed_mult = 1.0 + (_active_spec.speed_mult - 1.0) * power
	result.accel_mult = 1.0 + (_active_spec.accel_mult - 1.0) * power
	result.ignores_offroad = _active_spec.ignores_offroad
	result.source = _source
	result.remaining = _remaining
	result.spec = _active_spec
	return result


## Returns the source label retained when weaker requests extend the slot.
func get_source() -> StringName:
	return _source


## Returns seconds remaining in the active boost.
func get_remaining() -> float:
	return _remaining


## Pure countdown hook: phase is seconds before GO; negative means GO passed.
func evaluate_start_input(frame: InputFrame, countdown_phase: float) -> StartInputResult:
	var result: StartInputResult = StartInputResult.new()
	if _tuning == null or frame.throttle <= 0.0 or countdown_phase < 0.0:
		return result
	if countdown_phase <= _tuning.start_boost_window * 0.5:
		result.outcome = StartInputOutcome.TIER_TWO
		result.boost_spec = _tuning.start_boost_tier_two
	elif countdown_phase <= _tuning.start_boost_window:
		result.outcome = StartInputOutcome.TIER_ONE
		result.boost_spec = _tuning.start_boost_tier_one
	else:
		result.outcome = StartInputOutcome.WHEELSPIN
		result.wheelspin_duration = _tuning.early_acceleration_spin_duration
	return result


func _end_boost() -> void:
	_active_spec = null
	_source = &""
	_remaining = 0.0
	boost_ended.emit()
	if _owner_kart != null and is_inside_tree():
		EventBus.boost_ended.emit(_owner_kart)


func _emit_started(spec: BoostSpecData) -> void:
	boost_started.emit(spec)
	if _owner_kart != null and is_inside_tree():
		EventBus.boost_started.emit(_owner_kart, spec)
