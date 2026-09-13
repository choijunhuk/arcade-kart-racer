extends RefCounted

## Seam-free control for CollisionProbe: one long BoxShape3D wall on a flat floor.

class FlatWallInputProvider extends InputProvider:
	func get_frame() -> InputFrame:
		var frame: InputFrame = InputFrame.new()
		frame.throttle = 1.0
		return frame


const KART_SCENE: PackedScene = preload("res://kart/kart.tscn")
const SWEEP_SPEEDS: Array[float] = [12.0, 22.0, 30.0]
const POST_CONTACT_TICKS: int = 40
const MAX_SCENARIO_TICKS: int = 720
const WALL_CENTER_Z: float = -10.0
const WALL_HALF_DEPTH: float = 0.5
const FALL_Y: float = -3.0


static func run(host: Node, options: Dictionary) -> void:
	var speeds: Array = SWEEP_SPEEDS if bool(options["sweep"]) else [float(options["speed"])]
	var results: Array[Dictionary] = []
	for speed: float in speeds:
		for angle: float in options["angles"]:
			results.append(await _run_scenario(host, speed, angle, options))
	var failed_count: int = results.filter(
		func(result: Dictionary) -> bool: return bool(result["penetrated"]) or bool(result["fell_below_track"])
	).size()
	print("COLLISION_PROBE ", JSON.stringify({
		"summary": true,
		"track": "flat_wall",
		"scenario_count": results.size(),
		"failed_count": failed_count,
		"penetrated": results.any(func(result: Dictionary) -> bool: return bool(result["penetrated"])),
		"fell_below_track": results.any(func(result: Dictionary) -> bool: return bool(result["fell_below_track"])),
	}))
	host.get_tree().quit(1 if failed_count > 0 else 0)


static func _run_scenario(host: Node, speed: float, angle: float, options: Dictionary) -> Dictionary:
	var fixture: Node3D = Node3D.new()
	host.add_child(fixture)
	var body: StaticBody3D = StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	fixture.add_child(body)
	_add_box(body, Vector3(200.0, 1.0, 60.0), Vector3(0.0, -0.5, 0.0))
	_add_box(body, Vector3(200.0, 4.0, WALL_HALF_DEPTH * 2.0), Vector3(0.0, 2.0, WALL_CENTER_Z))
	var kart: KartController = KART_SCENE.instantiate() as KartController
	fixture.add_child(kart)
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame
	var radians: float = deg_to_rad(angle)
	var direction: Vector3 = Vector3(cos(radians), 0.0, -sin(radians)).normalized()
	kart.global_transform = Transform3D(Basis.looking_at(direction, Vector3.UP), Vector3(0.0, 0.65, 0.0))
	if float(options["wall_push_out"]) >= 0.0 or float(options["wall_bounce"]) >= 0.0:
		var diagnostic_tuning: PhysicsTuning = kart.tuning.duplicate(true) as PhysicsTuning
		if float(options["wall_push_out"]) >= 0.0:
			diagnostic_tuning.wall_push_out = float(options["wall_push_out"])
		if float(options["wall_bounce"]) >= 0.0:
			diagnostic_tuning.wall_bounce = float(options["wall_bounce"])
		kart.tuning = diagnostic_tuning
	kart.set_input_provider(FlatWallInputProvider.new())
	(kart.get_node("KartPhysics") as KartPhysics).speed = speed
	var min_y: float = kart.global_position.y
	var min_z: float = kart.global_position.z
	var wall_normal: Variant = null
	var event_wall_inward_dot: Variant = null
	var event_tick: int = -1
	var after_event: int = 0
	for tick: int in range(MAX_SCENARIO_TICKS):
		await host.get_tree().physics_frame
		min_y = minf(min_y, kart.global_position.y)
		min_z = minf(min_z, kart.global_position.z)
		wall_normal = _wall_normal(kart)
		if event_tick < 0 and wall_normal != null:
			event_tick = tick
			event_wall_inward_dot = (wall_normal as Vector3).dot(Vector3.BACK)
		elif event_tick >= 0:
			after_event += 1
			if after_event >= POST_CONTACT_TICKS:
				break
	var result: Dictionary = {
		"track": "flat_wall",
		"speed": speed,
		"angle": angle,
		"event_tick": event_tick,
		"penetrated": min_z < WALL_CENTER_Z - WALL_HALF_DEPTH,
		"fell_below_track": min_y < FALL_Y,
		"min_y": snappedf(min_y, 0.001),
		"max_depth": snappedf(maxf(0.0, WALL_CENTER_Z - WALL_HALF_DEPTH - min_z), 0.001),
		"grounded": kart.is_grounded(),
		"ground_ray_hits": _ground_ray_hits(kart),
		"wall_inward_dot": null if event_wall_inward_dot == null else snappedf(float(event_wall_inward_dot), 0.001),
	}
	print("COLLISION_PROBE ", JSON.stringify(result))
	fixture.queue_free()
	await host.get_tree().physics_frame
	return result


static func _add_box(body: StaticBody3D, size: Vector3, position: Vector3) -> void:
	var node: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	node.shape = shape
	node.position = position
	body.add_child(node)


static func _ground_ray_hits(kart: KartController) -> int:
	var hits: int = 0
	for child: Node in kart.get_node("GroundRays").get_children():
		if child is RayCast3D:
			var ray: RayCast3D = child as RayCast3D
			ray.force_raycast_update()
			if ray.is_colliding():
				hits += 1
	return hits


static func _wall_normal(kart: KartController) -> Variant:
	for index: int in range(kart.get_slide_collision_count()):
		var collision: KinematicCollision3D = kart.get_slide_collision(index)
		if absf(collision.get_normal().dot(Vector3.UP)) < kart.tuning.wall_normal_threshold:
			return collision.get_normal()
	return null
