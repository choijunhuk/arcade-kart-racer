class_name GridSettle
extends Node

## Seats a freshly spawned kart on the road under its StartGrid slot.
##
## Authored slots can sit below the road top (Track01's markers were 0.1 m
## under its ribbon, so karts waited sunk into the road for the whole frozen
## countdown and popped up at GO) or below the body clearance a sloped grid
## needs. The settle runs as a one-shot child node on the kart's first
## physics tick: the freshly instanced track's collision is not queryable in
## the frame it is added (a ray cast there misses), and a child node dies with
## its kart if the race is torn down first. Only the height changes, never the
## slot's horizontal position or facing; it is a pure geometry query, so the
## server and every client derive the same spawn height.

## Probe window around the slot: start above markers that sit inside the
## road, search a short distance below markers that float above it.
const SURFACE_PROBE_ABOVE: float = 2.0
const SURFACE_PROBE_BELOW: float = 3.0
const WORLD_COLLISION_MASK: int = 1
## Height above the hover pose from which the body box is dropped onto the road.
const BODY_DROP_HEIGHT: float = 1.0
## A race (re)loaded mid physics tick gets its first settle call before the
## track collision syncs; retry a few ticks (the kart is frozen meanwhile).
const MAX_ATTEMPTS: int = 5

var _attempts_left: int = MAX_ATTEMPTS


## Places `kart` on `slot` and schedules the surface settle for its first tick.
static func place(kart: KartController, slot: Transform3D) -> void:
	kart.global_transform = slot
	var settle: GridSettle = GridSettle.new()
	settle.name = "GridSettle"
	kart.add_child(settle)


func _physics_process(_delta: float) -> void:
	var kart: KartController = get_parent() as KartController
	_attempts_left -= 1
	if kart == null or settle_kart(kart) or _attempts_left <= 0:
		set_physics_process(false)
		queue_free()


## Snaps `kart` vertically to the world surface under it plus its hover
## height, raised further if its body box would still cut into a sloped road
## (an upright kart on Glacier Crown's ~7 degree grid needs ~0.44 m, not
## 0.35 m). Returns false, leaving the kart untouched, when nothing driveable
## lies within the probe window.
static func settle_kart(kart: KartController) -> bool:
	var space: PhysicsDirectSpaceState3D = kart.get_world_3d().direct_space_state
	var origin: Vector3 = kart.global_position
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		origin + Vector3.UP * SURFACE_PROBE_ABOVE, origin + Vector3.DOWN * SURFACE_PROBE_BELOW, WORLD_COLLISION_MASK)
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return false
	var hover_y: float = (hit["position"] as Vector3).y + kart.tuning.hover_height
	kart.global_position.y = maxf(hover_y, _body_rest_y(kart, space, hover_y))
	kart.reset_physics_interpolation()
	return true


## Lowest origin height at which the kart's body shape, dropped straight down
## from above `hover_y`, rests on the world without overlapping it.
static func _body_rest_y(kart: KartController, space: PhysicsDirectSpaceState3D, hover_y: float) -> float:
	var body_shape: CollisionShape3D = kart.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if body_shape == null or body_shape.shape == null:
		return hover_y
	var params: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	params.shape = body_shape.shape
	params.collision_mask = WORLD_COLLISION_MASK
	var start: Transform3D = body_shape.global_transform
	start.origin.y += hover_y + BODY_DROP_HEIGHT - kart.global_position.y
	params.transform = start
	params.motion = Vector3.DOWN * BODY_DROP_HEIGHT
	var safe_fraction: float = space.cast_motion(params)[0]
	if safe_fraction <= 0.0:
		return hover_y # Started overlapping (e.g. a low ceiling): no usable answer.
	return hover_y + BODY_DROP_HEIGHT * (1.0 - safe_fraction)
