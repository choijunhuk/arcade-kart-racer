class_name AIItemBrain
extends RefCounted

## Rule-table item-use decisions (spec §13.5), gated by per-difficulty
## decision delay/accuracy. Evaluated against `ItemSlotView` so the rules are
## unit-testable with a fake view before Phase 7 wires a real `ItemSlot`.

const STORM_BEACON_RANK_THRESHOLD: int = 3
const AEGIS_HOLD_FALLBACK_RANK: int = 1

## Snapshot of everything a §13.5 rule needs to know this tick. Built fresh
## per evaluation so rules stay pure functions of (view, use_profile, context).
class ItemDecisionContext extends RefCounted:
	var kart_ahead_distance: float = INF
	var kart_ahead_in_fire_cone: bool = false
	var rear_kart_distance: float = INF
	var curvature_ahead: float = 0.0
	var is_boosting: bool = false
	var incoming_projectile: bool = false
	var rank: int = 8
	var nearby_kart_count: int = 0
	var being_overtaken: bool = false
	var at_corner_apex: bool = false


var _rng: RandomNumberGenerator
var _decision_timer: float = 0.0


func _init(rng: RandomNumberGenerator) -> void:
	_rng = rng


## Evaluates one AI tick's item-use decision; returns true when `item` should
## fire. `difficulty.item_decision_delay` throttles how often a fresh
## eligibility check happens; `item_use_accuracy` is the chance a genuinely
## eligible situation is actually recognized and acted on.
func should_use(
	view: ItemSlotView, use_profile: AIItemUseProfile, difficulty: AIDifficultyProfile,
	context: ItemDecisionContext, dt: float,
) -> bool:
	if not view.has_item():
		_decision_timer = 0.0
		return false
	_decision_timer += dt
	if _decision_timer < difficulty.item_decision_delay:
		return false
	_decision_timer = 0.0
	if not _rule_eligible(view.get_category(), use_profile, context):
		return false
	return _rng.randf() < difficulty.item_use_accuracy


## Pure per-category eligibility rule table (spec §13.5), exposed statically
## so tests can check one rule at a time without rolling `item_use_accuracy`.
static func is_rule_eligible(category: ItemData.ItemCategory, use_profile: AIItemUseProfile, context: ItemDecisionContext) -> bool:
	match category:
		ItemData.ItemCategory.PROJECTILE:
			return context.kart_ahead_in_fire_cone or context.rear_kart_distance <= use_profile.rear_fire_range
		ItemData.ItemCategory.HOMING:
			return context.kart_ahead_distance <= use_profile.homing_range
		ItemData.ItemCategory.TRAP:
			return context.rear_kart_distance <= use_profile.trap_range or context.at_corner_apex
		ItemData.ItemCategory.BOOST:
			return absf(context.curvature_ahead) <= use_profile.straight_curvature_max and not context.is_boosting
		ItemData.ItemCategory.SHIELD:
			return context.incoming_projectile or (context.rank == AEGIS_HOLD_FALLBACK_RANK and context.rear_kart_distance < INF)
		ItemData.ItemCategory.AREA:
			return context.nearby_kart_count >= use_profile.pulse_min_targets or context.being_overtaken
		ItemData.ItemCategory.LEADER_STRIKE:
			return context.rank >= STORM_BEACON_RANK_THRESHOLD
		_:
			return false


func _rule_eligible(category: ItemData.ItemCategory, use_profile: AIItemUseProfile, context: ItemDecisionContext) -> bool:
	return is_rule_eligible(category, use_profile, context)
