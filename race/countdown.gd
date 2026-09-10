class_name Countdown
extends Node

## Tick-driven 3-2-1-GO sequence and one-shot start-input adjudication.

signal ticked(value: int)

const FIRST_TICK: int = 3
const GO_TICK: int = 0

var _tuning: RaceTuning
var _karts: Array[KartController] = []
var _pending_results: Dictionary[int, BoostController.StartInputResult] = {}
var _throttle_was_held: Dictionary[int, bool] = {}
var _elapsed_in_step: float = 0.0
var _current_tick: int = FIRST_TICK
var _active: bool = false


## Configures the countdown and resets per-kart start-input decisions.
func setup(tuning: RaceTuning, karts: Array[KartController]) -> void:
	_tuning = tuning
	_karts = karts.duplicate()
	_pending_results.clear()
	_throttle_was_held.clear()
	for kart: KartController in _karts:
		_throttle_was_held[kart.get_instance_id()] = false


## Starts at 3 and freezes every registered kart.
func start() -> void:
	if _tuning == null:
		push_error("Countdown.start requires RaceTuning")
		return
	_elapsed_in_step = 0.0
	_current_tick = FIRST_TICK
	_active = true
	for kart: KartController in _karts:
		kart.set_frozen(true)
	_emit_tick(_current_tick)


## Advances deterministic countdown time; returns true exactly when GO fires.
func advance(delta: float) -> bool:
	if not _active or _tuning == null:
		return false
	_sample_start_inputs()
	_elapsed_in_step += maxf(delta, 0.0)
	while _elapsed_in_step + 0.000001 >= _tuning.countdown_step_seconds:
		_elapsed_in_step -= _tuning.countdown_step_seconds
		_current_tick -= 1
		_emit_tick(_current_tick)
		if _current_tick == GO_TICK:
			_active = false
			_apply_start_outcomes()
			return true
	return false


## Records one throttle edge using BoostController's existing start-window rule.
func evaluate_start_input_for_kart(kart: KartController, frame: InputFrame, phase_seconds: float) -> void:
	var id: int = kart.get_instance_id()
	if _pending_results.has(id) or frame.throttle <= 0.0:
		return
	_pending_results[id] = kart.boost_controller.evaluate_start_input(frame, phase_seconds)


## Returns seconds remaining until GO for HUD/tests.
func get_phase_seconds() -> float:
	if not _active or _tuning == null:
		return 0.0
	return maxf(0.0, float(_current_tick) * _tuning.countdown_step_seconds - _elapsed_in_step)


func _sample_start_inputs() -> void:
	var phase_seconds: float = get_phase_seconds()
	for kart: KartController in _karts:
		var frame: InputFrame = kart.get_input_frame_snapshot()
		var id: int = kart.get_instance_id()
		var held: bool = frame.throttle > 0.0
		if held and not bool(_throttle_was_held.get(id, false)):
			evaluate_start_input_for_kart(kart, frame, phase_seconds)
		_throttle_was_held[id] = held


func _apply_start_outcomes() -> void:
	for kart: KartController in _karts:
		var result: BoostController.StartInputResult = _pending_results.get(kart.get_instance_id()) as BoostController.StartInputResult
		if result != null:
			match result.outcome:
				BoostController.StartInputOutcome.TIER_ONE, BoostController.StartInputOutcome.TIER_TWO:
					kart.request_boost(result.boost_spec, &"start_boost")
				BoostController.StartInputOutcome.WHEELSPIN:
					kart.apply_start_wheelspin(result.wheelspin_duration)
		kart.set_frozen(false)


func _emit_tick(value: int) -> void:
	ticked.emit(value)
	if is_inside_tree():
		EventBus.countdown_tick.emit(value)


## Removes a departed participant without restarting the countdown.
func unregister_kart(kart: KartController) -> void:
	_karts.erase(kart)
	_pending_results.erase(kart.get_instance_id())
	_throttle_was_held.erase(kart.get_instance_id())
