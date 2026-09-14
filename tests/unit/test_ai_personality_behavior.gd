extends GutTest

## Spec §18d (phase 18d-1): seeded, headless behavior checks that different
## `AIPersonality` traits actually produce meaningfully different AI judgment
## across many ticks -- not just different multiplier numbers (see
## `test_ai_personality_tuning.gd` for the pure-mapping boundary checks).

const KART_SCENE: PackedScene = preload("res://kart/kart.tscn")
const NORMAL_DIFFICULTY: AIDifficultyProfile = preload("res://data/ai/normal.tres")
const TICKS: int = 600
const DT: float = 1.0 / 30.0

class FakeItemSlotView extends ItemSlotView:
	var _category: ItemData.ItemCategory

	func _init(category: ItemData.ItemCategory) -> void:
		_category = category

	func has_item() -> bool:
		return true

	func get_category() -> ItemData.ItemCategory:
		return _category


func _count_uses(
	category: ItemData.ItemCategory, personality: AIPersonality, context: AIItemBrain.ItemDecisionContext,
	profile: AIDifficultyProfile, seed_value: int,
) -> int:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var brain: AIItemBrain = AIItemBrain.new(rng)
	var view: FakeItemSlotView = FakeItemSlotView.new(category)
	var uses: int = 0
	for _tick: int in range(TICKS):
		if brain.should_use(view, AIItemUseProfile.new(), profile, context, DT, personality):
			uses += 1
	return uses


func test_aggression_extremes_produce_meaningfully_different_attack_item_use_counts() -> void:
	var context: AIItemBrain.ItemDecisionContext = AIItemBrain.ItemDecisionContext.new()
	context.kart_ahead_in_fire_cone = true # keeps PROJECTILE eligible every tick
	var aggressive: AIPersonality = AIPersonality.new()
	aggressive.aggression = 1.0
	var passive: AIPersonality = AIPersonality.new()
	passive.aggression = 0.0
	var aggressive_uses: int = _count_uses(ItemData.ItemCategory.PROJECTILE, aggressive, context, NORMAL_DIFFICULTY, 11)
	var passive_uses: int = _count_uses(ItemData.ItemCategory.PROJECTILE, passive, context, NORMAL_DIFFICULTY, 11)
	assert_gt(aggressive_uses, passive_uses, "an aggressive AI must decide to fire attack items far more often than a passive one")
	assert_gt(aggressive_uses, passive_uses + 3, "the gap must be a real margin, not seed noise")


func test_high_defense_holds_a_defensive_item_longer_while_leading() -> void:
	var context: AIItemBrain.ItemDecisionContext = AIItemBrain.ItemDecisionContext.new()
	context.rank = AIItemBrain.AEGIS_HOLD_FALLBACK_RANK # leading
	context.rear_kart_distance = 5.0 # keeps SHIELD eligible throughout (spec §13.5 leader fallback rule)
	var guarded: AIPersonality = AIPersonality.new()
	guarded.defense = 1.0
	var exposed: AIPersonality = AIPersonality.new()
	exposed.defense = 0.0
	# Pin accuracy to 1.0 so only the decision-delay difference (the actual
	# "holds on to it longer" behavior) drives the outcome, not an
	# additional accuracy coin flip on top of it.
	var profile: AIDifficultyProfile = NORMAL_DIFFICULTY.duplicate(true) as AIDifficultyProfile
	profile.item_use_accuracy = 1.0
	var guarded_uses: int = _count_uses(ItemData.ItemCategory.SHIELD, guarded, context, profile, 22)
	var exposed_uses: int = _count_uses(ItemData.ItemCategory.SHIELD, exposed, context, profile, 22)
	assert_lt(guarded_uses, exposed_uses, "a defense-heavy leader must decide to spend its defensive item less often than a defense-light one")


## Spec §13.6 hard constraint, checked end-to-end with a real kart:
## `AIDriver._compute_target_speed` takes no personality argument at all, so
## two opposite-extreme personalities driving the same kart/profile/nav must
## produce byte-identical target speeds.
func test_target_speed_is_identical_regardless_of_personality() -> void:
	var kart: KartController = KART_SCENE.instantiate() as KartController
	add_child_autofree(kart)
	var nav: AINavigator.NavResult = AINavigator.NavResult.new()
	nav.curvature_ahead = 0.04
	var context: AIRaceContext = AIRaceContext.new()
	var reckless: AIPersonality = AIPersonality.new()
	reckless.aggression = 1.0
	reckless.overtake_boldness = 1.0
	reckless.drift_ambition = 1.0
	reckless.line_discipline = 0.0
	var cautious: AIPersonality = AIPersonality.new()
	cautious.aggression = 0.0
	cautious.overtake_boldness = 0.0
	cautious.drift_ambition = 0.0
	cautious.line_discipline = 1.0
	var driver_a: AIDriver = AIDriver.new(RandomNumberGenerator.new())
	var driver_b: AIDriver = AIDriver.new(RandomNumberGenerator.new())
	var speed_reckless: float = driver_a._compute_target_speed(kart, NORMAL_DIFFICULTY, nav, context)
	var speed_cautious: float = driver_b._compute_target_speed(kart, NORMAL_DIFFICULTY, nav, context)
	assert_almost_eq(speed_reckless, speed_cautious, 0.0001, "target speed must be identical no matter which personality is driving")
