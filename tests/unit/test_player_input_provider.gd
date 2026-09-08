extends GutTest

const FRAME_COUNT_TO_TARGET: int = 12

var _strengths: Dictionary[StringName, float] = {}
var _original_sensitivity: Variant


func before_each() -> void:
	_strengths.clear()
	_original_sensitivity = SettingsManager.get_setting(&"controls", &"steering_sensitivity", 1.0)


func after_each() -> void:
	SettingsManager.set_setting(&"controls", &"steering_sensitivity", _original_sensitivity)


func test_steer_smoothly_approaches_digital_input() -> void:
	_strengths[InputActions.STEER_RIGHT] = 1.0
	var provider: PlayerInputProvider = PlayerInputProvider.new(3)
	provider.set_strength_override(_read_strength)

	var first_frame: InputFrame = provider.get_frame()

	assert_gt(first_frame.steer, 0.0)
	assert_lt(first_frame.steer, 1.0)
	for index: int in range(FRAME_COUNT_TO_TARGET):
		provider.get_frame()
	assert_almost_eq(provider.get_frame().steer, 1.0, 0.001)


func test_steer_smoothing_reverses_without_snapping() -> void:
	_strengths[InputActions.STEER_RIGHT] = 1.0
	var provider: PlayerInputProvider = PlayerInputProvider.new(1)
	provider.set_strength_override(_read_strength)
	for index: int in range(FRAME_COUNT_TO_TARGET):
		provider.get_frame()

	_strengths[InputActions.STEER_RIGHT] = 0.0
	_strengths[InputActions.STEER_LEFT] = 1.0
	var reversal_frame: InputFrame = provider.get_frame()

	assert_gt(reversal_frame.steer, -1.0)
	assert_lt(reversal_frame.steer, 1.0)
	assert_eq(reversal_frame.tick, FRAME_COUNT_TO_TARGET + 1)


func test_edge_inputs_fire_once_per_press() -> void:
	var provider: PlayerInputProvider = PlayerInputProvider.new(0)
	provider.set_strength_override(_read_strength)
	_strengths[InputActions.DRIFT] = 1.0
	_strengths[InputActions.USE_ITEM] = 1.0

	var pressed: InputFrame = provider.get_frame()
	var held: InputFrame = provider.get_frame()

	assert_true(pressed.drift_pressed)
	assert_true(pressed.item)
	assert_false(held.drift_pressed)
	assert_false(held.item)


func test_steering_sensitivity_scales_the_smoothing_step() -> void:
	_strengths[InputActions.STEER_RIGHT] = 1.0
	SettingsManager.set_setting(&"controls", &"steering_sensitivity", 0.5)
	var provider: PlayerInputProvider = PlayerInputProvider.new(0)
	provider.set_strength_override(_read_strength)

	var first_frame: InputFrame = provider.get_frame()

	assert_almost_eq(first_frame.steer, (8.0 / 60.0) * 0.5, 0.001)


func _read_strength(action: StringName, device_id: int) -> float:
	assert_true(device_id >= 0)
	return _strengths.get(action, 0.0)
