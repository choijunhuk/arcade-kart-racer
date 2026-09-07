extends GutTest

const CONTROLLER_PATH: String = "res://kart/drift_controller.gd"
const DT: float = 0.1
const EPSILON: float = 0.001

var _tuning: PhysicsTuning
var _kart_data: KartData
var _controller: Node


func before_each() -> void:
	_tuning = (load("res://data/tuning/physics_default.tres") as PhysicsTuning).duplicate(true) as PhysicsTuning
	_kart_data = (load("res://data/karts/medium.tres") as KartData).duplicate(true) as KartData
	if not ResourceLoader.exists(CONTROLLER_PATH):
		return
	var script: GDScript = load(CONTROLLER_PATH) as GDScript
	_controller = script.new() as Node
	add_child_autofree(_controller)
	_controller.call("configure", _tuning, _kart_data)


func test_controller_script_exists() -> void:
	assert_true(ResourceLoader.exists(CONTROLLER_PATH))


func test_valid_press_enters_hop_then_locks_direction_into_hold() -> void:
	if not _require_controller():
		return
	_step(_frame(0.8, true, true), 12.0, true, 0.0, 0.0, false, DT)
	assert_eq(int(_controller.call("get_state")), 1)

	_step(_frame(0.8, true), 12.0, true, 0.0, 0.8, false, _tuning.drift_hop_duration)
	assert_eq(int(_controller.call("get_state")), 2)
	assert_eq(int(_controller.call("get_direction")), 1)


func test_hop_without_minimum_steer_returns_to_none() -> void:
	if not _require_controller():
		return
	_step(_frame(0.8, true, true), 12.0, true, 0.0, 0.0, false, DT)
	_step(_frame(0.0, true), 12.0, true, 0.0, 0.0, false, _tuning.drift_hop_duration)
	assert_eq(int(_controller.call("get_state")), 0)


func test_release_preserves_released_tier_and_exposes_matching_boost() -> void:
	if not _require_controller():
		return
	_enter_hold(1.0)
	_charge_for(_tuning.mini_turbo_tiers[1].charge_seconds + DT, 1.0, 1.0)
	_step(_frame(1.0, false), 18.0, true, 0.0, 1.0, false, DT)

	assert_eq(int(_controller.call("get_state")), 3)
	assert_eq(int(_controller.call("get_released_tier")), 2)
	var spec: BoostSpecData = _controller.call("get_pending_boost_spec") as BoostSpecData
	assert_not_null(spec)
	assert_almost_eq(spec.speed_mult, 1.25, EPSILON)
	assert_almost_eq(spec.duration, 1.4, EPSILON)


func test_hold_outputs_complete_drift_physics_contract_values() -> void:
	if not _require_controller():
		return
	_enter_hold(-1.0)
	var result: KartPhysics.DriftResult = _step(_frame(0.5, true), 18.0, true, 0.0, -1.0, false, DT)
	assert_true(result.is_drifting)
	assert_almost_eq(result.drift_dir, -1.0, EPSILON)
	assert_almost_eq(result.steer_influence, _tuning.drift_steer_influence, EPSILON)
	assert_almost_eq(result.grip, _tuning.drift_grip, EPSILON)
	assert_almost_eq(result.speed_retention, _tuning.drift_speed_retention, EPSILON)


func test_charge_tiers_match_one_two_point_two_and_three_point_six_seconds() -> void:
	if not _require_controller():
		return
	_enter_hold(1.0)
	_charge_for(0.9, 0.0, 1.0)
	assert_eq(int(_controller.call("get_tier")), 0)
	_charge_for(0.1, 0.0, 1.0)
	assert_eq(int(_controller.call("get_tier")), 1)
	_charge_for(1.2, 0.0, 1.0)
	assert_eq(int(_controller.call("get_tier")), 2)
	_charge_for(1.4, 0.0, 1.0)
	assert_eq(int(_controller.call("get_tier")), 3)


func test_low_yaw_rate_applies_straight_drift_suppression() -> void:
	if not _require_controller():
		return
	_enter_hold(1.0)
	_step(_frame(0.0, true), 18.0, true, 0.0, 0.0, false, 1.0)
	assert_almost_eq(float(_controller.call("get_charge")), _tuning.base_charge_rate * _tuning.low_turn_quality_mult, EPSILON)


func test_aligned_steer_earns_charge_bonus_and_kart_drift_factor() -> void:
	if not _require_controller():
		return
	_kart_data.drift_factor = 1.15
	_controller.call("configure", _tuning, _kart_data)
	_enter_hold(1.0)
	_step(_frame(1.0, true), 18.0, true, 0.0, 1.0, false, 1.0)
	var expected: float = _tuning.base_charge_rate * (1.0 + _tuning.steer_alignment_bonus) * 1.15
	assert_almost_eq(float(_controller.call("get_charge")), expected, EPSILON)


func test_opposite_steer_halts_charge_then_cancels_without_decreasing() -> void:
	if not _require_controller():
		return
	_enter_hold(1.0)
	_charge_for(0.5, 1.0, 1.0)
	var charged: float = float(_controller.call("get_charge"))
	_step(_frame(-1.0, true), 18.0, true, 0.0, 1.0, false, _tuning.drift_opposite_cancel_delay * 0.5)
	assert_almost_eq(float(_controller.call("get_charge")), charged, EPSILON)
	_step(_frame(-1.0, true), 18.0, true, 0.0, 1.0, false, _tuning.drift_opposite_cancel_delay * 0.6)
	assert_eq(int(_controller.call("get_state")), 0)
	assert_eq(int(_controller.call("get_tier")), 0)


func test_low_speed_only_cancels_after_configured_delay() -> void:
	if not _require_controller():
		return
	_enter_hold(-1.0)
	_step(_frame(-1.0, true), 1.0, true, 0.0, -1.0, false, _tuning.drift_cancel_delay * 0.5)
	assert_eq(int(_controller.call("get_state")), 2)
	_step(_frame(-1.0, true), 1.0, true, 0.0, -1.0, false, _tuning.drift_cancel_delay * 0.6)
	assert_eq(int(_controller.call("get_state")), 0)


func test_airborne_and_hit_cancel_hold_without_reward() -> void:
	if not _require_controller():
		return
	_enter_hold(1.0)
	_step(_frame(1.0, true), 18.0, false, _tuning.drift_airborne_cancel_time + DT, 1.0, false, DT)
	assert_eq(int(_controller.call("get_state")), 0)
	assert_null(_controller.call("get_pending_boost_spec"))
	_advance_cooldown()
	_enter_hold(1.0)
	_step(_frame(1.0, true), 18.0, true, 0.0, 1.0, true, DT)
	assert_eq(int(_controller.call("get_state")), 0)


func test_cooldown_blocks_reentry_until_elapsed() -> void:
	if not _require_controller():
		return
	_enter_hold(1.0)
	_step(_frame(1.0, false), 18.0, true, 0.0, 1.0, false, DT)
	_step(InputFrame.new(), 18.0, true, 0.0, 0.0, false, DT)
	_step(_frame(1.0, true, true), 18.0, true, 0.0, 0.0, false, DT)
	assert_eq(int(_controller.call("get_state")), 0)
	_step(InputFrame.new(), 18.0, true, 0.0, 0.0, false, _tuning.drift_cooldown)
	_step(_frame(1.0, true, true), 18.0, true, 0.0, 0.0, false, DT)
	assert_eq(int(_controller.call("get_state")), 1)


func test_trick_arms_after_minimum_air_time_and_requests_boost_on_landing() -> void:
	if not _require_controller():
		return
	_step(_frame(0.0, true, true), 12.0, false, _tuning.trick_min_air_time, 0.0, false, DT)
	assert_true(bool(_controller.call("is_trick_armed")))
	_step(InputFrame.new(), 12.0, true, 0.0, 0.0, false, DT)
	var spec: BoostSpecData = _controller.call("get_pending_boost_spec") as BoostSpecData
	assert_not_null(spec)
	assert_eq(spec.id, &"trick")
	assert_false(bool(_controller.call("is_trick_armed")))


func test_trick_press_before_minimum_air_time_is_ignored() -> void:
	if not _require_controller():
		return
	_step(_frame(0.0, true, true), 12.0, false, _tuning.trick_min_air_time - DT, 0.0, false, DT)
	assert_false(bool(_controller.call("is_trick_armed")))


func _require_controller() -> bool:
	if _controller != null:
		return true
	fail_test("DriftController could not be constructed")
	return false


func _frame(steer: float, held: bool, pressed: bool = false) -> InputFrame:
	var frame: InputFrame = InputFrame.new()
	frame.steer = steer
	frame.drift = held
	frame.drift_pressed = pressed
	return frame


func _step(frame: InputFrame, speed: float, grounded: bool, air_time: float, yaw_rate: float, is_hit: bool, dt: float) -> KartPhysics.DriftResult:
	return _controller.call("step", frame, speed, grounded, air_time, yaw_rate, is_hit, dt) as KartPhysics.DriftResult


func _enter_hold(direction: float) -> void:
	_step(_frame(direction, true, true), 18.0, true, 0.0, 0.0, false, DT)
	_step(_frame(direction, true), 18.0, true, 0.0, direction, false, _tuning.drift_hop_duration)


func _charge_for(seconds: float, steer: float, yaw_rate: float) -> void:
	var remaining: float = seconds
	while remaining > 0.0:
		var step_dt: float = minf(DT, remaining)
		_step(_frame(steer, true), 18.0, true, 0.0, yaw_rate, false, step_dt)
		remaining -= step_dt


func _advance_cooldown() -> void:
	_step(InputFrame.new(), 18.0, true, 0.0, 0.0, false, _tuning.drift_cooldown)
