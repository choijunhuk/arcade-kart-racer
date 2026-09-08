class_name ProjectileItem
extends ItemBase

## Straight projectile with bounded ShapeCast wall reflection and kart hits.

const DEFAULT_SPEED: float = 32.0
const SPAWN_FORWARD_OFFSET: float = 2.0
const WORLD_LAYER_MASK: int = 1
const KART_BUMP_LAYER_MASK: int = 4

@export var speed: float = DEFAULT_SPEED

var direction: Vector3 = Vector3.FORWARD
var bounce_count: int = 0


## Mirrors a velocity about a normalized collision normal.
static func reflect_velocity(velocity: Vector3, normal: Vector3) -> Vector3:
	return velocity.bounce(normal.normalized())


## Returns whether another reflection is inside the configured budget.
static func can_reflect(current_bounces: int, maximum_bounces: int) -> bool:
	return current_bounces < maximum_bounces


## Returns whether elapsed time has reached a positive lifetime.
static func lifetime_expired(elapsed: float, lifetime: float) -> bool:
	return lifetime > 0.0 and elapsed >= lifetime


## Spawns in front or rear according to the look-back use modifier.
func activate(frame: InputFrame) -> void:
	bounce_count = 0
	var rear: bool = frame != null and frame.look_back
	direction = (-owner_kart.get_forward() if rear else owner_kart.get_forward()).normalized()
	global_position = owner_kart.global_position + direction * SPAWN_FORWARD_OFFSET


## Sweeps one deterministic movement segment, resolving a kart or wall hit.
func tick(dt: float) -> void:
	if _advance_lifetime(dt):
		return
	var motion: Vector3 = direction * speed * dt
	var cast: ShapeCast3D = get_node_or_null("CollisionCast") as ShapeCast3D
	if cast == null:
		global_position += motion
		return
	cast.target_position = cast.to_local(cast.global_position + motion)
	cast.collision_mask = WORLD_LAYER_MASK | KART_BUMP_LAYER_MASK
	cast.collide_with_areas = true
	cast.force_shapecast_update()
	if cast.get_collision_count() == 0:
		global_position += motion
		return
	var collider: Object = cast.get_collider(0)
	var target: KartController = _kart_from_collider(collider)
	if target != null and target != owner_kart:
		on_hit(target)
		expire()
		return
	if can_reflect(bounce_count, data.max_bounces):
		direction = reflect_velocity(direction, cast.get_collision_normal(0)).normalized()
		bounce_count += 1
		global_position += direction * speed * dt
	else:
		expire()


## Projectiles participate in the manager registry used by AI and shields.
func is_projectile() -> bool:
	return true


## Returns current reflected travel direction for AI threat sensing.
func get_travel_direction() -> Vector3:
	return direction


func _kart_from_collider(collider: Object) -> KartController:
	if collider is KartController:
		return collider as KartController
	if collider is Area3D:
		return (collider as Area3D).get_parent() as KartController
	return null
