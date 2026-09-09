class_name GhostWorldReplay
extends Node3D

## Replays moving world colliders privately; live gates cannot alter a saved lap.

const PRIVATE_WORLD_MASK: int = 1 << 19
const TRANSFORM_COMPONENTS: int = 12
var copies: Array[StaticBody3D] = []


## Copies only mover collision shapes onto a layer seen exclusively by this ghost.
func setup(track: TrackRoot, kart: KartController, motion: KartWorldMotion) -> void:
	motion.collision_mask |= PRIVATE_WORLD_MASK
	for child: Node in track.get_node("MovingObstacles").get_children():
		if not child is MovingObstacle:
			continue
		var mover: MovingObstacle = child as MovingObstacle
		var copy: StaticBody3D = StaticBody3D.new()
		copy.collision_layer = PRIVATE_WORLD_MASK
		copy.collision_mask = 0
		add_child(copy)
		copy.global_transform = mover.global_transform
		for shape: Node in mover.get_children():
			if shape is CollisionShape3D:
				copy.add_child(shape.duplicate())
		copies.append(copy)
		motion.add_collision_exception_with(mover)
		for ray: Node in kart.get_node("GroundRays").get_children():
			(ray as RayCast3D).add_exception(mover)
			(ray as RayCast3D).collision_mask |= PRIVATE_WORLD_MASK


## Serializes the exact collider poses observed at an input-consumption boundary.
static func capture(movers: Array[MovingObstacle]) -> Array[Array]:
	var result: Array[Array] = []
	for mover: MovingObstacle in movers:
		var transform: Transform3D = mover.global_transform
		var values: Array[float] = []
		for vector: Vector3 in [transform.basis.x, transform.basis.y, transform.basis.z, transform.origin]:
			values.append_array([vector.x, vector.y, vector.z])
		result.append(values)
	return result


## Updates private copies before the ghost's ground probes and slide calculation.
func apply_frame(frame: Dictionary) -> void:
	var poses: Array = frame.get("movers", [])
	for index: int in range(mini(poses.size(), copies.size())):
		var values: Array = poses[index]
		copies[index].global_transform = Transform3D(Basis(_vector(values, 0),
			_vector(values, 3), _vector(values, 6)), _vector(values, 9))


## Validates numeric transforms before saved values reach the physics server.
static func valid_poses(value: Variant, count: int) -> bool:
	if not value is Array or value.size() != count:
		return false
	for pose: Variant in value:
		if not pose is Array or pose.size() != TRANSFORM_COMPONENTS:
			return false
		for component: Variant in pose:
			if not (component is int or component is float) or not is_finite(float(component)):
				return false
	return true


static func _vector(values: Array, offset: int) -> Vector3:
	return Vector3(float(values[offset]), float(values[offset + 1]), float(values[offset + 2]))
