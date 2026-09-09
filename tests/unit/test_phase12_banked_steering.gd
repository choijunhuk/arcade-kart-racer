extends GutTest


func test_banked_road_steering_preserves_yaw_only_body_orientation() -> void:
	var body: CharacterBody3D = CharacterBody3D.new()
	add_child_autofree(body)
	var physics: KartPhysics = KartPhysics.new()
	add_child_autofree(physics)
	var tuning: PhysicsTuning = load("res://data/tuning/physics_default.tres") as PhysicsTuning
	var kart: KartData = load("res://data/karts/medium.tres") as KartData
	physics.setup(body, [], tuning, kart)
	physics.speed = 22.0
	var ground: KartPhysics.GroundProbe = KartPhysics.GroundProbe.new()
	ground.grounded = true
	ground.normal = Vector3.UP.rotated(Vector3.FORWARD, deg_to_rad(5.0))
	var frame: InputFrame = InputFrame.new()
	frame.steer = 0.7
	for tick: int in range(120):
		physics._integrate_steering(frame, ground, 1.0 / 60.0)
	assert_almost_eq(body.basis.y.distance_to(Vector3.UP), 0.0, 0.00001)
	assert_almost_eq(body.basis.z.y, 0.0, 0.00001)
