extends GutTest


func test_zero_returns_a_neutral_frame() -> void:
	var frame: InputFrame = InputFrame.zero()

	assert_eq(frame.throttle, 0.0)
	assert_eq(frame.brake, 0.0)
	assert_eq(frame.steer, 0.0)
	assert_false(frame.drift)
	assert_false(frame.drift_pressed)
	assert_false(frame.item)
	assert_false(frame.look_back)
	assert_eq(frame.tick, 0)


func test_clone_copies_values_without_aliasing() -> void:
	var original: InputFrame = InputFrame.new()
	original.throttle = 0.75
	original.brake = 0.25
	original.steer = -0.5
	original.drift = true
	original.drift_pressed = true
	original.item = true
	original.look_back = true
	original.tick = 42

	var copy: InputFrame = original.clone()
	original.steer = 1.0

	assert_ne(copy, original)
	assert_eq(copy.throttle, 0.75)
	assert_eq(copy.brake, 0.25)
	assert_eq(copy.steer, -0.5)
	assert_true(copy.drift)
	assert_true(copy.drift_pressed)
	assert_true(copy.item)
	assert_true(copy.look_back)
	assert_eq(copy.tick, 42)
