extends GutTest

## Regression coverage for the Phase 8 review: `_resolve_clipping()` must pull
## the chase camera closer than its normal follow distance when world
## geometry sits between the kart and the desired unclipped camera position,
## instead of letting the camera clip through the wall.

const KART_SCENE: PackedScene = preload("res://kart/kart.tscn")
const CAMERA_SCENE: PackedScene = preload("res://camera/race_camera.tscn")


func test_wall_between_camera_and_kart_shrinks_camera_distance() -> void:
	var kart: KartController = KART_SCENE.instantiate() as KartController
	add_child_autofree(kart)
	kart.global_position = Vector3.ZERO
	kart.rotation = Vector3.ZERO
	var camera: RaceCamera = CAMERA_SCENE.instantiate() as RaceCamera
	add_child_autofree(camera)
	camera.call("set_target", kart)

	var tuning: FeelTuning = camera.tuning
	# Unclipped chase position directly behind the kart (forward is -Z), matching
	# `_desired_position()` with zero drift offset.
	var desired: Vector3 = (
		kart.global_position + Vector3.BACK * tuning.camera_distance + Vector3.UP * tuning.camera_height
	)
	var focus: Vector3 = kart.global_position + Vector3.UP

	var wall: StaticBody3D = _build_wall()
	add_child_autofree(wall)
	await wait_physics_frames(1)

	var resolved: Vector3 = camera.call("_resolve_clipping", desired) as Vector3

	assert_lt(kart.global_position.distance_to(resolved), tuning.camera_distance)
	assert_lt(focus.distance_to(resolved), focus.distance_to(desired))


func test_clear_path_leaves_the_default_position_unclipped() -> void:
	var kart: KartController = KART_SCENE.instantiate() as KartController
	add_child_autofree(kart)
	kart.global_position = Vector3.ZERO
	kart.rotation = Vector3.ZERO
	var camera: RaceCamera = CAMERA_SCENE.instantiate() as RaceCamera
	add_child_autofree(camera)
	camera.call("set_target", kart)

	var tuning: FeelTuning = camera.tuning
	var desired: Vector3 = (
		kart.global_position + Vector3.BACK * tuning.camera_distance + Vector3.UP * tuning.camera_height
	)
	await wait_physics_frames(1)

	var resolved: Vector3 = camera.call("_resolve_clipping", desired) as Vector3

	assert_eq(resolved, desired)


## Places a wall directly in the ray path between the look-target focus point
## (kart position + 1m up) and the default unclipped chase position behind
## the kart, on the default `camera_collision_mask` layer ("world" = 1).
func _build_wall() -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(10.0, 4.0, 1.0)
	shape.shape = box
	shape.position = Vector3(0.0, 2.0, 2.75)
	body.add_child(shape)
	return body
