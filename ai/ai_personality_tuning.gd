class_name AIPersonalityTuning
extends RefCounted

## Pure static mapping (spec §18d — phase 18d-1) from `AIPersonality` trait
## values (0..1, neutral 0.5) to concrete AI judgment-timing/probability
## multipliers, consumed by `ai_item_brain.gd`, `ai_driver.gd`, and
## `ai_driver_drift.gd`. Every function here is a no-op (returns 1.0, or the
## input unchanged) at neutral 0.5 / a null personality, so a driver with no
## `ai_personality` assigned behaves byte-identical to before this phase.
## Deliberately never touches max_speed/acceleration/speed_confidence/
## rubber-band — those remain `AIDifficultyProfile`-only (spec §13.6).

const ATTACK_CATEGORIES: Array[ItemData.ItemCategory] = [
	ItemData.ItemCategory.PROJECTILE, ItemData.ItemCategory.HOMING,
	ItemData.ItemCategory.AREA, ItemData.ItemCategory.LEADER_STRIKE,
]
const DEFENSE_CATEGORIES: Array[ItemData.ItemCategory] = [
	ItemData.ItemCategory.SHIELD, ItemData.ItemCategory.TRAP,
]

## --- aggression (ai_item_brain.gd: attack-category items) ---
const AGGRESSION_ACCURACY_MIN_MULT: float = 0.65 # aggression=0.0
const AGGRESSION_ACCURACY_MAX_MULT: float = 1.35 # aggression=1.0
const AGGRESSION_DELAY_MIN_MULT: float = 0.6 # aggression=1.0: decides fastest
const AGGRESSION_DELAY_MAX_MULT: float = 1.5 # aggression=0.0: hesitates longest

## --- defense (ai_item_brain.gd: defensive-category items) ---
const DEFENSE_ACCURACY_MIN_MULT: float = 0.65 # defense=0.0
const DEFENSE_ACCURACY_MAX_MULT: float = 1.35 # defense=1.0
const DEFENSE_DELAY_MIN_MULT: float = 0.6 # defense=0.0: fires the instant it is eligible
const DEFENSE_DELAY_MAX_MULT: float = 1.8 # defense=1.0: holds on to it longer

## --- overtake_boldness (ai_driver.gd) ---
const BOLDNESS_SPEED_DELTA_MIN_MULT: float = 0.6 # boldness=1.0: needs only a small speed gap
const BOLDNESS_SPEED_DELTA_MAX_MULT: float = 1.6 # boldness=0.0: needs a big speed gap
const BOLDNESS_RELAX_MIN_MULT: float = 0.4 # boldness=1.0: relaxes into forcing a pass sooner
const BOLDNESS_RELAX_MAX_MULT: float = 2.0 # boldness=0.0: waits much longer before forcing it

## --- line_discipline (ai_driver.gd: overtake lane-bias amplitude) ---
const DISCIPLINE_WIDTH_MIN_MULT: float = 0.55 # discipline=1.0: narrow, tight to the line
const DISCIPLINE_WIDTH_MAX_MULT: float = 1.6 # discipline=0.0: wanders/swings wide

## --- drift_ambition (ai_driver_drift.gd) ---
const AMBITION_HIGH_THRESHOLD: float = 0.7
const AMBITION_LOW_THRESHOLD: float = 0.3
const AMBITION_MIN_TIER: int = 1
const AMBITION_MAX_TIER: int = 3
const AMBITION_CANCEL_MIN_MULT: float = 0.5 # ambition=1.0: rarely bails out early
const AMBITION_CANCEL_MAX_MULT: float = 1.8 # ambition=0.0: bails out early more readily


## Linear interpolation pinned so `trait_value=0.5` always yields exactly
## `1.0` (neutral), regardless of how far `min_mult`/`max_mult` sit from 1.0.
static func _lerp_from_neutral(trait_value: float, min_mult: float, max_mult: float) -> float:
	var t: float = clampf(trait_value, 0.0, 1.0)
	if t >= 0.5:
		return lerpf(1.0, max_mult, (t - 0.5) / 0.5)
	return lerpf(min_mult, 1.0, t / 0.5)


## `AIItemBrain.should_use` accuracy multiplier for one item category.
static func item_accuracy_multiplier(category: ItemData.ItemCategory, personality: AIPersonality) -> float:
	var p: AIPersonality = AIPersonality.resolve(personality)
	if category in ATTACK_CATEGORIES:
		return _lerp_from_neutral(p.aggression, AGGRESSION_ACCURACY_MIN_MULT, AGGRESSION_ACCURACY_MAX_MULT)
	if category in DEFENSE_CATEGORIES:
		return _lerp_from_neutral(p.defense, DEFENSE_ACCURACY_MIN_MULT, DEFENSE_ACCURACY_MAX_MULT)
	return 1.0


## `AIItemBrain.should_use` decision-delay multiplier for one item category.
static func item_delay_multiplier(category: ItemData.ItemCategory, personality: AIPersonality) -> float:
	var p: AIPersonality = AIPersonality.resolve(personality)
	if category in ATTACK_CATEGORIES:
		# Higher aggression -> shorter delay, so invert the neutral-anchored lerp.
		return _lerp_from_neutral(1.0 - p.aggression, AGGRESSION_DELAY_MIN_MULT, AGGRESSION_DELAY_MAX_MULT)
	if category in DEFENSE_CATEGORIES:
		return _lerp_from_neutral(p.defense, DEFENSE_DELAY_MIN_MULT, DEFENSE_DELAY_MAX_MULT)
	return 1.0


## `AIDriver._can_attempt_overtake`'s effective `OVERTAKE_SPEED_DELTA` multiplier.
static func overtake_speed_delta_multiplier(personality: AIPersonality) -> float:
	var p: AIPersonality = AIPersonality.resolve(personality)
	return _lerp_from_neutral(1.0 - p.overtake_boldness, BOLDNESS_SPEED_DELTA_MIN_MULT, BOLDNESS_SPEED_DELTA_MAX_MULT)


## `AIDriver.compute_overtake_bias`'s effective `OVERTAKE_BLOCKED_RELAX_SECONDS` multiplier.
static func overtake_relax_multiplier(personality: AIPersonality) -> float:
	var p: AIPersonality = AIPersonality.resolve(personality)
	return _lerp_from_neutral(1.0 - p.overtake_boldness, BOLDNESS_RELAX_MIN_MULT, BOLDNESS_RELAX_MAX_MULT)


## `AIDriver.compute_overtake_bias`'s lane-offset amplitude multiplier.
static func lane_width_multiplier(personality: AIPersonality) -> float:
	var p: AIPersonality = AIPersonality.resolve(personality)
	return _lerp_from_neutral(1.0 - p.line_discipline, DISCIPLINE_WIDTH_MIN_MULT, DISCIPLINE_WIDTH_MAX_MULT)


## `AIDriftPlanner._update_hold`'s effective drift-hold target tier, nudged
## +-1 from the difficulty's own `target_tier` (still clamped to [1, 3]);
## the neutral middle band [0.3, 0.7] leaves the difficulty's tier untouched.
static func drift_target_tier(base_target_tier: int, personality: AIPersonality) -> int:
	var p: AIPersonality = AIPersonality.resolve(personality)
	var delta: int = 0
	if p.drift_ambition >= AMBITION_HIGH_THRESHOLD:
		delta = 1
	elif p.drift_ambition <= AMBITION_LOW_THRESHOLD:
		delta = -1
	return clampi(base_target_tier + delta, AMBITION_MIN_TIER, AMBITION_MAX_TIER)


## `AIDriftPlanner._update_hold`'s effective early-release mistake-chance multiplier.
static func drift_cancel_prob_multiplier(personality: AIPersonality) -> float:
	var p: AIPersonality = AIPersonality.resolve(personality)
	return _lerp_from_neutral(1.0 - p.drift_ambition, AMBITION_CANCEL_MIN_MULT, AMBITION_CANCEL_MAX_MULT)
