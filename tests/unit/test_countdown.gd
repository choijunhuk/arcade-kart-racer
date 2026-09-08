extends GutTest

const COUNTDOWN_PATH: String = "res://race/countdown.gd"
const TUNING_PATH: String = "res://data/tuning/race_default.tres"
const KART_SCENE: PackedScene = preload("res://kart/kart.tscn")
const START_BOOST_WINDOW: float = 0.35

var _strengths: Dictionary[StringName, float] = {}


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


## Regression for the tick-bias bug (spec §6.1 rule 2): a press must count
## for the exact physics tick it happens on. Countdown._sample_start_inputs
## reads kart.get_input_frame_snapshot(), which only reflects the current
## tick once the kart's own _physics_process has refreshed it -- exactly
## what RaceManager now guarantees by deferring Countdown.advance() until
## after every kart has ticked. Pressing throttle right at the start-boost
## window edge (phase_seconds == start_boost_window) must still land TIER_ONE,
## not fall through to WHEELSPIN, once the kart's frame is fresh first.
func test_start_input_pressed_on_the_exact_window_edge_tick_counts() -> void:
	_strengths.clear()
	var kart: KartController = KART_SCENE.instantiate() as KartController
	add_child_autofree(kart)
	var provider: PlayerInputProvider = PlayerInputProvider.new()
	provider.set_strength_override(_read_strength)
	kart.set_input_provider(provider)
	var countdown: Node = _make_countdown([kart])
	if countdown == null:
		return

	countdown.call("start")
	countdown.call("advance", 1.0) # tick 3 -> 2
	countdown.call("advance", 1.0) # tick 2 -> 1 (1.0s of phase remains)
	countdown.call("advance", 1.0 - START_BOOST_WINDOW) # phase now == window edge

	# Press throttle "this tick": refresh the kart's cached frame first, then
	# let Countdown sample it, mirroring the fixed per-tick ordering.
	_strengths[InputActions.ACCELERATE] = 1.0
	kart.call("_physics_process", START_BOOST_WINDOW)
	var fired_go: bool = bool(countdown.call("advance", START_BOOST_WINDOW))

	assert_true(fired_go, "the remaining phase step must land exactly on GO")
	assert_eq(kart.get_boost_source(), &"start_boost")
	assert_eq(kart.boost_controller.get_result().spec.id, &"start_boost_1")


func _read_strength(action: StringName, _device_id: int) -> float:
	return _strengths.get(action, 0.0)


func _make_countdown(karts: Array[KartController]) -> Node:
	var exists: bool = ResourceLoader.exists(COUNTDOWN_PATH) and ResourceLoader.exists(TUNING_PATH)
	assert_true(exists, "Countdown and RaceTuning resources must exist")
	if not exists:
		return null
	var countdown: Node = (load(COUNTDOWN_PATH) as GDScript).new() as Node
	add_child_autofree(countdown)
	countdown.call("setup", load(TUNING_PATH), karts)
	return countdown

