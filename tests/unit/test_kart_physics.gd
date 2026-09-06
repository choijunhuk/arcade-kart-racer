extends GutTest

const DT: float = 1.0 / 60.0

var _tuning: PhysicsTuning
var _kart_data: KartData
var _physics: KartPhysics
var _dummy_body: CharacterBody3D


func before_each() -> void:
	_tuning = load("res://data/tuning/physics_default.tres") as PhysicsTuning
	_kart_data = load("res://data/karts/medium.tres") as KartData
	_physics = KartPhysics.new()
	_dummy_body = CharacterBody3D.new()
	_physics.setup(_dummy_body, [], _tuning, _kart_data)


func after_each() -> void:
	_physics.free()
	_dummy_body.free()


func test_accel_curve_is_monotonically_non_increasing() -> void:
	var previous: float = _tuning.accel_curve.sample(0.0)
	for step: int in range(1, 5):
		var ratio: float = step / 4.0
		var value: float = _tuning.accel_curve.sample(ratio)
		assert_lte(value, previous + 0.001)
		previous = value


func test_steer_curve_decreases_with_speed() -> void:
	var low_speed_value: float = _tuning.steer_curve.sample(0.0)
	var high_speed_value: float = _tuning.steer_curve.sample(1.0)
	assert_gt(low_speed_value, high_speed_value)


func test_speed_converges_toward_max_speed_under_full_throttle() -> void:
	var input: InputFrame = InputFrame.new()
	input.throttle = 1.0
	var terrain: KartPhysics.TerrainSample = KartPhysics.TerrainSample.new()
	var boost: KartPhysics.BoostResult = KartPhysics.BoostResult.new()
	for tick: int in range(600):
		_physics._integrate_longitudinal(input, terrain, boost, DT)

	assert_almost_eq(_physics.speed, _kart_data.max_speed, _kart_data.max_speed * 0.05)


func test_speed_never_exceeds_max_speed_by_more_than_overspeed_tolerance() -> void:
	var input: InputFrame = InputFrame.new()
	input.throttle = 1.0
	var terrain: KartPhysics.TerrainSample = KartPhysics.TerrainSample.new()
	var boost: KartPhysics.BoostResult = KartPhysics.BoostResult.new()
	var max_observed: float = 0.0
	for tick: int in range(900):
		_physics._integrate_longitudinal(input, terrain, boost, DT)
		max_observed = maxf(max_observed, _physics.speed)

	assert_lte(max_observed, _kart_data.max_speed + 0.5)


func test_reverse_engages_after_stopping_under_brake() -> void:
	var input: InputFrame = InputFrame.new()
	input.brake = 1.0
	var terrain: KartPhysics.TerrainSample = KartPhysics.TerrainSample.new()
	var boost: KartPhysics.BoostResult = KartPhysics.BoostResult.new()
	_physics.speed = 4.0
	for tick: int in range(300):
		_physics._integrate_longitudinal(input, terrain, boost, DT)

	assert_almost_eq(_physics.speed, -_tuning.reverse_max_speed, 0.1)


func test_yaw_rate_is_zero_below_min_steer_speed() -> void:
	var input: InputFrame = InputFrame.new()
	input.steer = 1.0
	_physics.speed = _tuning.min_steer_speed * 0.5
	var ground: KartPhysics.GroundProbe = KartPhysics.GroundProbe.new()
	ground.grounded = true
	ground.normal = Vector3.UP

	var yaw_delta: float = _physics._integrate_steering(input, ground, DT)

	assert_eq(yaw_delta, 0.0)


func test_yaw_rate_shrinks_with_speed() -> void:
	var input: InputFrame = InputFrame.new()
	input.steer = 1.0
	var ground: KartPhysics.GroundProbe = KartPhysics.GroundProbe.new()
	ground.grounded = true
	ground.normal = Vector3.UP

	_physics.speed = _tuning.min_steer_speed + 1.0
	var low_speed_yaw: float = absf(_physics._integrate_steering(input, ground, DT))
	_physics.speed = _kart_data.max_speed
	var high_speed_yaw: float = absf(_physics._integrate_steering(input, ground, DT))

	assert_gt(low_speed_yaw, high_speed_yaw)


func test_wall_response_graze_loses_little_speed_and_does_not_bounce() -> void:
	var response: KartPhysics.WallResponse = KartPhysics.compute_wall_response(10.0, _tuning)

	assert_almost_eq(response.speed_mult, _tuning.wall_graze_loss, 0.001)
	assert_almost_eq(response.bounce_mult, 0.0, 0.001)


func test_wall_response_head_on_loses_much_speed_and_bounces() -> void:
	var response: KartPhysics.WallResponse = KartPhysics.compute_wall_response(75.0, _tuning)

	assert_almost_eq(response.speed_mult, _tuning.wall_head_on_loss, 0.001)
	assert_almost_eq(response.bounce_mult, _tuning.wall_bounce, 0.001)


func test_wall_response_interpolates_between_graze_and_head_on() -> void:
	var mid_angle: float = (_tuning.wall_graze_angle_degrees + _tuning.wall_head_on_angle_degrees) / 2.0
	var response: KartPhysics.WallResponse = KartPhysics.compute_wall_response(mid_angle, _tuning)

	assert_lt(response.speed_mult, _tuning.wall_graze_loss)
	assert_gt(response.speed_mult, _tuning.wall_head_on_loss)
	assert_gt(response.bounce_mult, 0.0)
	assert_lt(response.bounce_mult, _tuning.wall_bounce)
