extends GutTest

const CONTROLLER_PATH: String = "res://kart/boost_controller.gd"
const EPSILON: float = 0.001

var _tuning: PhysicsTuning
var _controller: Node


func before_each() -> void:
	_tuning = (load("res://data/tuning/physics_default.tres") as PhysicsTuning).duplicate(true) as PhysicsTuning
	if not ResourceLoader.exists(CONTROLLER_PATH):
		return
	var script: GDScript = load(CONTROLLER_PATH) as GDScript
	_controller = script.new() as Node
	add_child_autofree(_controller)
	var kart_data: KartData = (load("res://data/karts/medium.tres") as KartData).duplicate(true) as KartData
	_controller.call("configure", _tuning, kart_data)


func test_controller_script_exists() -> void:
	assert_true(ResourceLoader.exists(CONTROLLER_PATH))


func test_stronger_boost_replaces_multiplier_duration_and_source() -> void:
	if not _require_controller():
		return
	_controller.call("request", _tuning.trick_boost, &"trick")
	_controller.call("step", 0.2)
	_controller.call("request", _tuning.boost_pad_boost, &"boost_pad")
	var result: KartPhysics.BoostResult = _controller.call("get_result") as KartPhysics.BoostResult
	assert_almost_eq(result.speed_mult, _tuning.boost_pad_boost.speed_mult, EPSILON)
	assert_almost_eq(float(_controller.call("get_remaining")), _tuning.boost_pad_boost.duration, EPSILON)
	assert_eq(StringName(_controller.call("get_source")), &"boost_pad")


func test_equal_or_weaker_boost_extends_without_changing_multiplier() -> void:
	if not _require_controller():
		return
	_controller.call("request", _tuning.boost_pad_boost, &"boost_pad")
	_controller.call("step", 0.4)
	_controller.call("request", _tuning.trick_boost, &"trick")
	var result: KartPhysics.BoostResult = _controller.call("get_result") as KartPhysics.BoostResult
	assert_almost_eq(result.speed_mult, _tuning.boost_pad_boost.speed_mult, EPSILON)
	assert_almost_eq(float(_controller.call("get_remaining")), 1.2, EPSILON)
	assert_eq(StringName(_controller.call("get_source")), &"boost_pad")


func test_extension_is_capped_at_max_boost_duration() -> void:
	if not _require_controller():
		return
	for request_index: int in range(10):
		_controller.call("request", _tuning.trick_boost, &"trick")
	assert_almost_eq(float(_controller.call("get_remaining")), _tuning.max_boost_duration, EPSILON)


func test_expiry_returns_neutral_result_and_clears_source() -> void:
	if not _require_controller():
		return
	_controller.call("request", _tuning.trick_boost, &"trick")
	var result: KartPhysics.BoostResult = _controller.call("step", _tuning.trick_boost.duration) as KartPhysics.BoostResult
	assert_false(result.active)
	assert_almost_eq(result.speed_mult, 1.0, EPSILON)
	assert_eq(StringName(_controller.call("get_source")), &"")


func test_boost_pad_result_ignores_offroad() -> void:
	if not _require_controller():
		return
	_controller.call("request", _tuning.boost_pad_boost, &"boost_pad")
	var result: KartPhysics.BoostResult = _controller.call("get_result") as KartPhysics.BoostResult
	assert_true(result.ignores_offroad)


func test_start_input_inside_inner_half_window_returns_tier_two() -> void:
	if not _require_controller():
		return
	var result: RefCounted = _controller.call("evaluate_start_input", _throttle_frame(), _tuning.start_boost_window * 0.25) as RefCounted
	assert_eq(int(result.get("outcome")), 2)
	assert_eq((result.get("boost_spec") as BoostSpecData).id, &"start_boost_2")


func test_start_input_inside_outer_window_returns_tier_one() -> void:
	if not _require_controller():
		return
	var result: RefCounted = _controller.call("evaluate_start_input", _throttle_frame(), _tuning.start_boost_window * 0.75) as RefCounted
	assert_eq(int(result.get("outcome")), 1)
	assert_eq((result.get("boost_spec") as BoostSpecData).id, &"start_boost_1")


func test_start_input_too_early_returns_wheelspin_duration() -> void:
	if not _require_controller():
		return
	var result: RefCounted = _controller.call("evaluate_start_input", _throttle_frame(), _tuning.start_boost_window + 0.1) as RefCounted
	assert_eq(int(result.get("outcome")), 3)
	assert_almost_eq(float(result.get("wheelspin_duration")), _tuning.early_acceleration_spin_duration, EPSILON)


func test_start_input_without_throttle_returns_no_outcome() -> void:
	if not _require_controller():
		return
	var result: RefCounted = _controller.call("evaluate_start_input", InputFrame.new(), 0.0) as RefCounted
	assert_eq(int(result.get("outcome")), 0)
	assert_null(result.get("boost_spec"))


func _require_controller() -> bool:
	if _controller != null:
		return true
	fail_test("BoostController could not be constructed")
	return false


func _throttle_frame() -> InputFrame:
	var frame: InputFrame = InputFrame.new()
	frame.throttle = 1.0
	return frame
