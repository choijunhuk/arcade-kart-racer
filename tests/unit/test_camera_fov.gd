extends GutTest

const FOV_PATH: String = "res://camera/camera_fov.gd"
const EPSILON: float = 0.001


func test_speed_squared_add_matches_camera_formula() -> void:
	var script: GDScript = _require_script()
	if script == null:
		return
	var value: float = float(script.call("compute_target", 70.0, 14.0, 8.0, 0.5, 0.0, 1.0))
	assert_almost_eq(value, 73.5, EPSILON)


func test_fov_strength_scales_speed_and_boost_additions() -> void:
	var script: GDScript = _require_script()
	if script == null:
		return
	var value: float = float(script.call("compute_target", 70.0, 14.0, 8.0, 1.0, 1.0, 0.5))
	assert_almost_eq(value, 81.0, EPSILON)


func test_zero_fov_strength_returns_base_fov_even_during_boost() -> void:
	var script: GDScript = _require_script()
	if script == null:
		return
	var value: float = float(script.call("compute_target", 70.0, 14.0, 8.0, 1.0, 1.0, 0.0))
	assert_almost_eq(value, 70.0, EPSILON)


func _require_script() -> GDScript:
	if ResourceLoader.exists(FOV_PATH):
		return load(FOV_PATH) as GDScript
	fail_test("CameraFov script is missing")
	return null
