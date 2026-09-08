extends GutTest

const COUNTDOWN_PATH: String = "res://race/countdown.gd"
const TUNING_PATH: String = "res://data/tuning/race_default.tres"
const KART_SCENE: PackedScene = preload("res://kart/kart.tscn")


func test_countdown_emits_three_two_one_go_at_one_second_steps() -> void:
	var countdown: Node = _make_countdown([])
	if countdown == null:
		return
	watch_signals(countdown)
	countdown.call("start")
	assert_signal_emitted_with_parameters(countdown, "ticked", [3])
	assert_false(bool(countdown.call("advance", 0.99)))
	assert_eq(get_signal_emit_count(countdown, "ticked"), 1)
	assert_false(bool(countdown.call("advance", 0.01)))
	assert_signal_emitted_with_parameters(countdown, "ticked", [2])
	assert_false(bool(countdown.call("advance", 1.0)))
	assert_signal_emitted_with_parameters(countdown, "ticked", [1])
	assert_true(bool(countdown.call("advance", 1.0)))
	assert_signal_emitted_with_parameters(countdown, "ticked", [0])


func test_perfect_start_input_applies_tier_two_at_go() -> void:
	var kart: KartController = KART_SCENE.instantiate() as KartController
	add_child_autofree(kart)
	var countdown: Node = _make_countdown([kart])
	if countdown == null:
		return
	var frame: InputFrame = InputFrame.new()
	frame.throttle = 1.0
	countdown.call("evaluate_start_input_for_kart", kart, frame, 0.1)
	countdown.call("start")
	countdown.call("advance", 3.0)
	assert_eq(kart.get_boost_source(), &"start_boost")
	assert_eq(kart.boost_controller.get_result().spec.id, &"start_boost_2")


func test_early_start_input_keeps_kart_frozen_for_wheelspin_duration() -> void:
	var kart: KartController = KART_SCENE.instantiate() as KartController
	add_child_autofree(kart)
	var countdown: Node = _make_countdown([kart])
	if countdown == null:
		return
	var frame: InputFrame = InputFrame.new()
	frame.throttle = 1.0
	countdown.call("evaluate_start_input_for_kart", kart, frame, 1.0)
	countdown.call("start")
	countdown.call("advance", 3.0)
	assert_gt(float(kart.call("get_start_wheelspin_remaining")), 0.0)
	assert_eq(kart.get_state(), KartState.FROZEN)


func _make_countdown(karts: Array[KartController]) -> Node:
	var exists: bool = ResourceLoader.exists(COUNTDOWN_PATH) and ResourceLoader.exists(TUNING_PATH)
	assert_true(exists, "Countdown and RaceTuning resources must exist")
	if not exists:
		return null
	var countdown: Node = (load(COUNTDOWN_PATH) as GDScript).new() as Node
	add_child_autofree(countdown)
	countdown.call("setup", load(TUNING_PATH), karts)
	return countdown

