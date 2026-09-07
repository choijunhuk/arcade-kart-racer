extends GutTest

## Drives `kart.tscn` full throttle head-on into a wall and checks the DoD
## claims: the kart is never wedged (speed recovers once steering away) and
## the body never flips (up vector stays close to world up), because the
## controller only ever rotates yaw (spec §9.7, §9.8, §24 Phase 1).

class _FullThrottleProvider extends InputProvider:
	var steer: float = 0.0

	func get_frame() -> InputFrame:
		var frame: InputFrame = InputFrame.new()
		frame.throttle = 1.0
		frame.steer = steer
		return frame

const HEAD_ON_SECONDS: float = 2.0
const RECOVERY_SECONDS: float = 1.0
const TICKS_PER_SECOND: int = 60
const MIN_RECOVERED_SPEED: float = 3.0
const MAX_TILT_DEGREES: float = 10.0


func test_kart_recovers_from_a_head_on_wall_collision_without_flipping() -> void:
	var floor_body: StaticBody3D = _build_floor()
	add_child_autofree(floor_body)
	var wall: StaticBody3D = _build_wall()
	add_child_autofree(wall)
	var kart: KartController = (load("res://kart/kart.tscn") as PackedScene).instantiate()
	add_child_autofree(kart)
	await wait_physics_frames(1)
	kart.global_position = Vector3(0.0, 0.65, 0.0)
	kart.rotation = Vector3.ZERO

	var provider: _FullThrottleProvider = _FullThrottleProvider.new()
	kart.set_input_provider(provider)

	var saw_bump: bool = false
	for tick: int in range(int(HEAD_ON_SECONDS * TICKS_PER_SECOND)):
		await wait_physics_frames(1)
		saw_bump = saw_bump or kart.get_hit_state() == HitReactor.HitType.BUMP

	var up_dot: float = kart.global_transform.basis.y.dot(Vector3.UP)
	assert_gt(up_dot, cos(deg_to_rad(MAX_TILT_DEGREES)), "kart body tilted as if it flipped")
	assert_true(saw_bump, "head-on wall collision never triggered HitReactor.BUMP")

	provider.steer = 1.0
	await wait_physics_frames(int(RECOVERY_SECONDS * TICKS_PER_SECOND))

	assert_gt(kart.get_speed(), MIN_RECOVERED_SPEED, "kart stayed stuck against the wall")
	assert_ne(kart.get_state(), KartState.HIT, "BUMP reaction did not recover")


func _build_floor() -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(60.0, 1.0, 60.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	body.add_child(shape)
	return body


func _build_wall() -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(20.0, 4.0, 1.0)
	shape.shape = box
	shape.position = Vector3(0.0, 2.0, -10.0)
	body.add_child(shape)
	return body
