class_name AreaItem
extends ItemBase

## Owner-centered telegraphed pulse that bumps nearby karts and cancels drift.

const TELEGRAPH_SECONDS: float = 0.3
const DEFAULT_RADIUS: float = 9.0

@export var radius: float = DEFAULT_RADIUS


## Returns true at and after the telegraph boundary.
static func telegraph_complete(elapsed: float, duration: float) -> bool:
	return elapsed >= duration


## Starts the pulse at the owner's current position.
func activate(_frame: InputFrame) -> void:
	global_position = owner_kart.global_position


## Detonates once after the telegraph, bumps targets, and cancels their drift.
func tick(dt: float) -> void:
	if is_expired():
		return
	elapsed_seconds += maxf(dt, 0.0)
	if not telegraph_complete(elapsed_seconds, TELEGRAPH_SECONDS):
		return
	for kart: KartController in context.get_karts():
		if kart == owner_kart or not is_instance_valid(kart):
			continue
		if global_position.distance_to(kart.global_position) > radius:
			continue
		kart.drift_controller.call("cancel")
		on_hit(kart)
	expire()
