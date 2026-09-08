extends GutTest

const SHAKE_PATH: String = "res://camera/camera_shake.gd"
const EPSILON: float = 0.0001


func test_trauma_addition_clamps_at_one() -> void:
	var shake: RefCounted = _make_shake()
	if shake == null:
		return
	shake.call("add_trauma", 0.75)
	shake.call("add_trauma", 0.75)
	assert_almost_eq(float(shake.call("get_trauma")), 1.0, EPSILON)


func test_trauma_decay_reaches_zero_without_going_negative() -> void:
	var script: GDScript = _require_script()
	if script == null:
		return
	assert_almost_eq(float(script.call("decay_trauma", 0.8, 1.5, 0.2)), 0.5, EPSILON)
	assert_almost_eq(float(script.call("decay_trauma", 0.2, 1.5, 1.0)), 0.0, EPSILON)


func test_shake_amplitude_uses_trauma_squared() -> void:
	var script: GDScript = _require_script()
	if script == null:
		return
	assert_almost_eq(float(script.call("scaled_amplitude", 0.5, 1.0)), 0.25, EPSILON)
	assert_almost_eq(float(script.call("scaled_amplitude", 0.5, 0.4)), 0.1, EPSILON)


func test_zero_setting_produces_zero_rotation_and_position_offsets() -> void:
	var shake: RefCounted = _make_shake()
	if shake == null:
		return
	shake.call("add_trauma", 1.0)
	var sample: RefCounted = shake.call("step", 0.016, 0.0) as RefCounted
	assert_eq(sample.get("rotation_offset"), Vector3.ZERO)
	assert_eq(sample.get("position_offset"), Vector3.ZERO)


func test_landing_trauma_interpolates_from_point_two_to_point_five() -> void:
	var script: GDScript = load("res://camera/race_camera.gd") as GDScript
	if not script.has_method("landing_trauma"):
		fail_test("RaceCamera.landing_trauma is missing")
		return
	assert_almost_eq(float(script.call("landing_trauma", 4.0, 4.0, 18.0, 0.2, 0.5)), 0.2, EPSILON)
	assert_almost_eq(float(script.call("landing_trauma", 11.0, 4.0, 18.0, 0.2, 0.5)), 0.35, EPSILON)
	assert_almost_eq(float(script.call("landing_trauma", 18.0, 4.0, 18.0, 0.2, 0.5)), 0.5, EPSILON)


func test_explosion_trauma_falls_linearly_to_zero_at_radius() -> void:
	var script: GDScript = load("res://camera/race_camera.gd") as GDScript
	if not script.has_method("explosion_trauma"):
		fail_test("RaceCamera.explosion_trauma is missing")
		return
	assert_almost_eq(float(script.call("explosion_trauma", 0.0, 25.0, 0.7)), 0.7, EPSILON)
	assert_almost_eq(float(script.call("explosion_trauma", 12.5, 25.0, 0.7)), 0.35, EPSILON)
	assert_almost_eq(float(script.call("explosion_trauma", 25.0, 25.0, 0.7)), 0.0, EPSILON)


func _make_shake() -> RefCounted:
	var script: GDScript = _require_script()
	if script == null:
		return null
	var shake: RefCounted = script.new() as RefCounted
	shake.call("configure", preload("res://data/tuning/camera_default.tres"))
	return shake


func _require_script() -> GDScript:
	if ResourceLoader.exists(SHAKE_PATH):
		return load(SHAKE_PATH) as GDScript
	fail_test("CameraShake script is missing")
	return null
