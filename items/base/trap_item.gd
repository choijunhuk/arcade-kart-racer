class_name TrapItem
extends ItemBase

## Stationary rear drop/forward throw that arms after a deterministic delay.

const DEFAULT_ARM_DELAY: float = 0.5
const DEFAULT_TRIGGER_RADIUS: float = 1.8
const DEFAULT_OWNER_CAP: int = 2
const REAR_DROP_DISTANCE: float = 2.0
const FORWARD_THROW_DISTANCE: float = 5.0

@export var arm_delay: float = DEFAULT_ARM_DELAY
@export var trigger_radius: float = DEFAULT_TRIGGER_RADIUS
@export var max_per_owner: int = DEFAULT_OWNER_CAP


## Returns true once elapsed time reaches the arming boundary.
static func is_armed_after(elapsed: float, delay: float) -> bool:
	return elapsed >= delay


## Returns whether spawning one more trap stays within the owner cap.
static func within_owner_cap(active_count: int, maximum: int) -> bool:
	return active_count < maximum


## Drops behind by default; look-back turns the use into a forward throw.
func activate(frame: InputFrame) -> void:
	var forward_throw: bool = frame != null and frame.look_back
	var direction: Vector3 = owner_kart.get_forward()
	var distance: float = FORWARD_THROW_DISTANCE if forward_throw else -REAR_DROP_DISTANCE
	global_position = owner_kart.global_position + direction * distance


## Arms on time, then hits the first registered kart entering its radius.
func tick(dt: float) -> void:
	if _advance_lifetime(dt) or not is_armed_after(elapsed_seconds, arm_delay):
		return
	for kart: KartController in context.get_karts():
		if kart != owner_kart and is_instance_valid(kart) and global_position.distance_to(kart.global_position) <= trigger_radius:
			on_hit(kart)
			expire()
			return


## Enforces the simultaneous trap limit independently for each owner.
func can_spawn(active_items: Array[ItemBase]) -> bool:
	var owned_traps: int = 0
	for item: ItemBase in active_items:
		if item is TrapItem and item.owner_kart == owner_kart and not item.is_expired():
			owned_traps += 1
	return within_owner_cap(owned_traps, max_per_owner)
