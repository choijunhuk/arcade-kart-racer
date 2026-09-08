class_name LeaderStrikeItem
extends ItemBase

## Warns and strikes the current leader unless countered during the warning.

const WARNING_SECONDS: float = 3.0

var target_kart: KartController
var _immune: bool = false


## Returns rank one unless rank one is the owner.
static func select_target(owner: KartController, ranking: Array[KartController]) -> KartController:
	if ranking.is_empty() or ranking[0] == owner:
		return null
	return ranking[0]


## Returns false only while the owner currently holds rank one.
static func can_activate_from_rank(rank: int) -> bool:
	return rank > 1


## Acquires the leader and emits the mandatory three-second warning.
func activate(_frame: InputFrame) -> void:
	var tracker: PositionTracker = context.get_position_tracker()
	var ranking: Array[KartController] = tracker.get_ranking() if tracker != null else context.get_karts()
	target_kart = select_target(owner_kart, ranking)
	if target_kart == null:
		expire()
		return
	global_position = target_kart.global_position
	EventBus.threat_warning.emit(target_kart, data.id, WARNING_SECONDS)


## Strikes after the warning unless the target triggered an immunity counter.
func tick(dt: float) -> void:
	if _advance_lifetime(dt) or elapsed_seconds < WARNING_SECONDS:
		return
	if not _immune and is_instance_valid(target_kart):
		global_position = target_kart.global_position
		on_hit(target_kart)
	expire()


## Grants immunity only when the protected kart is this strike's target.
func grant_immunity(kart: KartController) -> void:
	if kart == target_kart:
		_immune = true


## Returns whether the warning target has countered this strike.
func is_target_immune() -> bool:
	return _immune


## Preserves the slot while its owner is currently rank one.
func can_activate() -> bool:
	var tracker: PositionTracker = context.get_position_tracker()
	if tracker == null:
		return true
	return can_activate_from_rank(tracker.get_position(owner_kart))
