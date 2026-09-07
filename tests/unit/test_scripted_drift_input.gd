extends GutTest


func test_default_scripted_driver_keeps_legacy_no_drift_mode() -> void:
	var fixture: Array[Node3D] = _build_fixture()
	var provider: InputProvider = ScriptedInputProvider.new(fixture[0], fixture[1] as Path3D)

	assert_false(provider.get_frame().drift)


func test_drift_mode_presses_once_then_holds_on_a_sharp_corner() -> void:
	var fixture: Array[Node3D] = _build_fixture()
	var provider: InputProvider = ScriptedInputProvider.new(fixture[0], fixture[1] as Path3D)
	assert_true(provider.has_method("set_drift_on_corners"))
	if not provider.has_method("set_drift_on_corners"):
		return
	provider.call("set_drift_on_corners", true)
	var first: InputFrame = provider.get_frame()
	var held: InputFrame = provider.get_frame()

	assert_true(first.drift)
	assert_true(first.drift_pressed)
	assert_true(held.drift)
	assert_false(held.drift_pressed)


func _build_fixture() -> Array[Node3D]:
	var kart: Node3D = Node3D.new()
	add_child_autofree(kart)
	var line: Path3D = Path3D.new()
	add_child_autofree(line)
	var curve: Curve3D = Curve3D.new()
	curve.add_point(Vector3(0.0, 0.0, 0.0))
	curve.add_point(Vector3(0.0, 0.0, -5.0))
	curve.add_point(Vector3(5.0, 0.0, -5.0))
	curve.add_point(Vector3(5.0, 0.0, 0.0))
	curve.add_point(Vector3(0.0, 0.0, 0.0))
	line.curve = curve
	return [kart, line]
