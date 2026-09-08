extends GutTest

## Spec §13.5: AIItemBrain's rule table and decision-delay/accuracy gating,
## checked against a fake ItemSlotView so no real ItemSlot (Phase 7) is needed.

class FakeItemSlotView extends ItemSlotView:
	var _has_item: bool
	var _category: StringName

	func _init(has_item: bool, category: StringName) -> void:
		_has_item = has_item
		_category = category

	func has_item() -> bool:
		return _has_item

	func get_category() -> StringName:
		return _category


func _make_profile(delay: float, accuracy: float) -> AIDifficultyProfile:
	var profile: AIDifficultyProfile = AIDifficultyProfile.new()
	profile.item_decision_delay = delay
	profile.item_use_accuracy = accuracy
	return profile


func test_rocket_dart_eligible_when_target_is_in_the_fire_cone() -> void:
	var context: AIItemBrain.ItemDecisionContext = AIItemBrain.ItemDecisionContext.new()
	context.kart_ahead_in_fire_cone = true
	var use_profile: AIItemUseProfile = AIItemUseProfile.new()
	assert_true(AIItemBrain.is_rule_eligible(&"rocket_dart", use_profile, context))


func test_rocket_dart_ineligible_with_nothing_ahead_or_behind() -> void:
	var context: AIItemBrain.ItemDecisionContext = AIItemBrain.ItemDecisionContext.new()
	var use_profile: AIItemUseProfile = AIItemUseProfile.new()
	assert_false(AIItemBrain.is_rule_eligible(&"rocket_dart", use_profile, context))


func test_nitro_can_ineligible_while_already_boosting() -> void:
	var context: AIItemBrain.ItemDecisionContext = AIItemBrain.ItemDecisionContext.new()
	context.curvature_ahead = 0.0
	context.is_boosting = true
	var use_profile: AIItemUseProfile = AIItemUseProfile.new()
	assert_false(AIItemBrain.is_rule_eligible(&"nitro_can", use_profile, context))


func test_nitro_can_eligible_on_a_straight_when_not_boosting() -> void:
	var context: AIItemBrain.ItemDecisionContext = AIItemBrain.ItemDecisionContext.new()
	context.curvature_ahead = 0.0
	context.is_boosting = false
	var use_profile: AIItemUseProfile = AIItemUseProfile.new()
	assert_true(AIItemBrain.is_rule_eligible(&"nitro_can", use_profile, context))


func test_storm_beacon_eligible_only_from_third_place_or_worse() -> void:
	var use_profile: AIItemUseProfile = AIItemUseProfile.new()
	var leading: AIItemBrain.ItemDecisionContext = AIItemBrain.ItemDecisionContext.new()
	leading.rank = 2
	assert_false(AIItemBrain.is_rule_eligible(&"storm_beacon", use_profile, leading))
	var trailing: AIItemBrain.ItemDecisionContext = AIItemBrain.ItemDecisionContext.new()
	trailing.rank = 3
	assert_true(AIItemBrain.is_rule_eligible(&"storm_beacon", use_profile, trailing))


func test_should_use_is_false_without_an_item() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 1
	var brain: AIItemBrain = AIItemBrain.new(rng)
	var view: FakeItemSlotView = FakeItemSlotView.new(false, &"storm_beacon")
	var context: AIItemBrain.ItemDecisionContext = AIItemBrain.ItemDecisionContext.new()
	context.rank = 5
	assert_false(brain.should_use(view, AIItemUseProfile.new(), _make_profile(0.0, 1.0), context, 1.0))


func test_should_use_waits_for_the_decision_delay_before_firing() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 1
	var brain: AIItemBrain = AIItemBrain.new(rng)
	var view: FakeItemSlotView = FakeItemSlotView.new(true, &"storm_beacon")
	var context: AIItemBrain.ItemDecisionContext = AIItemBrain.ItemDecisionContext.new()
	context.rank = 5
	var profile: AIDifficultyProfile = _make_profile(1.0, 1.0)
	assert_false(brain.should_use(view, AIItemUseProfile.new(), profile, context, 0.5))
	assert_true(brain.should_use(view, AIItemUseProfile.new(), profile, context, 0.6))


func test_should_use_never_fires_when_ineligible_even_with_perfect_accuracy() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 1
	var brain: AIItemBrain = AIItemBrain.new(rng)
	var view: FakeItemSlotView = FakeItemSlotView.new(true, &"storm_beacon")
	var context: AIItemBrain.ItemDecisionContext = AIItemBrain.ItemDecisionContext.new()
	context.rank = 1 # leading: storm_beacon rule needs rank >= 3
	var profile: AIDifficultyProfile = _make_profile(0.0, 1.0)
	assert_false(brain.should_use(view, AIItemUseProfile.new(), profile, context, 1.0))
