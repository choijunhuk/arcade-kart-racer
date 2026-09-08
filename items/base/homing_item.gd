class_name HomingItem
extends ItemBase

## Chases the next-ranked kart while blending toward the baked racing line.

const DEFAULT_SPEED: float = 24.0
const LINE_LOOK_AHEAD: float = 5.0
const TARGET_STEER_WEIGHT: float = 0.45
const HIT_RADIUS: float = 1.8
const SPAWN_FORWARD_OFFSET: float = 2.0

@export var speed: float = DEFAULT_SPEED

var target_kart: KartController
var direction: Vector3 = Vector3.FORWARD


## Returns the immediately preceding ranking entry, or null for rank one.
static func select_target(owner: KartController, ranking: Array[KartController]) -> KartController:
	var owner_index: int = ranking.find(owner)
	if owner_index <= 0:
		return null
	return ranking[owner_index - 1]


## Acquires the next kart ahead and launches forward.
func activate(_frame: InputFrame) -> void:
	var tracker: PositionTracker = context.get_position_tracker()
	var ranking: Array[KartController] = tracker.get_ranking() if tracker != null else context.get_karts()
	target_kart = select_target(owner_kart, ranking)
	if target_kart == null:
		expire()
		return
	direction = owner_kart.get_forward().normalized()
	global_position = owner_kart.global_position + direction * SPAWN_FORWARD_OFFSET


## Advances line-guided steering and applies a hit inside the contact radius.
func tick(dt: float) -> void:
	if _advance_lifetime(dt) or not is_instance_valid(target_kart):
		if not is_expired():
			expire()
		return
	var line: RacingLine = context.get_racing_line()
	var desired: Vector3 = (target_kart.global_position - global_position).normalized()
	if line != null:
		var offset: float = line.offset_at(global_position)
		var line_direction: Vector3 = (line.sample(offset + LINE_LOOK_AHEAD) - global_position).normalized()
		desired = line_direction.slerp(desired, TARGET_STEER_WEIGHT).normalized()
	direction = direction.slerp(desired, clampf(dt * speed, 0.0, 1.0)).normalized()
	global_position += direction * speed * dt
	if global_position.distance_to(target_kart.global_position) <= HIT_RADIUS:
		on_hit(target_kart)
		expire()


## Homing threats share the active projectile registry.
func is_projectile() -> bool:
	return true


## Returns current guided travel direction for AI threat sensing.
func get_travel_direction() -> Vector3:
	return direction
