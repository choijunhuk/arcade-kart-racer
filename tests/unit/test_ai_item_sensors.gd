extends GutTest


func test_projectile_moving_toward_kart_inside_range_is_a_threat() -> void:
	assert_true(AISensors.projectile_is_approaching(
		Vector3.ZERO, Vector3.FORWARD, Vector3(0.0, 0.0, -8.0), Vector3.BACK, 12.0,
	))


func test_projectile_moving_away_or_behind_is_not_a_threat() -> void:
	assert_false(AISensors.projectile_is_approaching(
		Vector3.ZERO, Vector3.FORWARD, Vector3(0.0, 0.0, -8.0), Vector3.FORWARD, 12.0,
	))
	assert_false(AISensors.projectile_is_approaching(
		Vector3.ZERO, Vector3.FORWARD, Vector3(0.0, 0.0, 5.0), Vector3.FORWARD, 12.0,
	))
