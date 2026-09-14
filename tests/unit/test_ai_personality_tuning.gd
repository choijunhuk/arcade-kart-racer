extends GutTest

## Spec §18d (phase 18d-1): `AIPersonalityTuning`'s pure trait->multiplier
## mapping. Covers the neutral no-op point (0.5 / null), both boundaries
## (0.0/1.0), and that none of this module's outputs ever touch a
## speed-related quantity (spec §13.6: judgment/style only).

const PROJECTILE: ItemData.ItemCategory = ItemData.ItemCategory.PROJECTILE
const SHIELD: ItemData.ItemCategory = ItemData.ItemCategory.SHIELD
const BOOST: ItemData.ItemCategory = ItemData.ItemCategory.BOOST


func _personality(aggression: float = 0.5, defense: float = 0.5, overtake_boldness: float = 0.5, drift_ambition: float = 0.5, line_discipline: float = 0.5) -> AIPersonality:
	var p: AIPersonality = AIPersonality.new()
	p.aggression = aggression
	p.defense = defense
	p.overtake_boldness = overtake_boldness
	p.drift_ambition = drift_ambition
	p.line_discipline = line_discipline
	return p


func test_null_personality_is_neutral_for_every_multiplier() -> void:
	assert_almost_eq(AIPersonalityTuning.item_accuracy_multiplier(PROJECTILE, null), 1.0, 0.0001)
	assert_almost_eq(AIPersonalityTuning.item_delay_multiplier(PROJECTILE, null), 1.0, 0.0001)
	assert_almost_eq(AIPersonalityTuning.item_accuracy_multiplier(SHIELD, null), 1.0, 0.0001)
	assert_almost_eq(AIPersonalityTuning.item_delay_multiplier(SHIELD, null), 1.0, 0.0001)
	assert_almost_eq(AIPersonalityTuning.overtake_speed_delta_multiplier(null), 1.0, 0.0001)
	assert_almost_eq(AIPersonalityTuning.overtake_relax_multiplier(null), 1.0, 0.0001)
	assert_almost_eq(AIPersonalityTuning.lane_width_multiplier(null), 1.0, 0.0001)
	assert_almost_eq(AIPersonalityTuning.drift_cancel_prob_multiplier(null), 1.0, 0.0001)
	assert_eq(AIPersonalityTuning.drift_target_tier(2, null), 2)


func test_all_neutral_0_5_traits_match_null_exactly() -> void:
	var neutral: AIPersonality = _personality()
	assert_almost_eq(AIPersonalityTuning.item_accuracy_multiplier(PROJECTILE, neutral), AIPersonalityTuning.item_accuracy_multiplier(PROJECTILE, null), 0.0001)
	assert_almost_eq(AIPersonalityTuning.overtake_speed_delta_multiplier(neutral), AIPersonalityTuning.overtake_speed_delta_multiplier(null), 0.0001)
	assert_almost_eq(AIPersonalityTuning.lane_width_multiplier(neutral), AIPersonalityTuning.lane_width_multiplier(null), 0.0001)
	assert_eq(AIPersonalityTuning.drift_target_tier(2, neutral), AIPersonalityTuning.drift_target_tier(2, null))


func test_non_attack_non_defense_category_is_always_a_noop() -> void:
	assert_almost_eq(AIPersonalityTuning.item_accuracy_multiplier(BOOST, _personality(1.0)), 1.0, 0.0001)
	assert_almost_eq(AIPersonalityTuning.item_delay_multiplier(BOOST, _personality(0.0)), 1.0, 0.0001)


func test_aggression_boundaries_move_attack_accuracy_and_delay_in_opposite_directions() -> void:
	var low: AIPersonality = _personality(0.0)
	var high: AIPersonality = _personality(1.0)
	# Higher aggression -> more likely to act (accuracy up)...
	assert_gt(AIPersonalityTuning.item_accuracy_multiplier(PROJECTILE, high), AIPersonalityTuning.item_accuracy_multiplier(PROJECTILE, low))
	# ...and decides faster (delay multiplier down).
	assert_lt(AIPersonalityTuning.item_delay_multiplier(PROJECTILE, high), AIPersonalityTuning.item_delay_multiplier(PROJECTILE, low))


func test_defense_boundaries_hold_longer_as_defense_rises() -> void:
	var low: AIPersonality = _personality(0.5, 0.0)
	var high: AIPersonality = _personality(0.5, 1.0)
	assert_gt(AIPersonalityTuning.item_delay_multiplier(SHIELD, high), AIPersonalityTuning.item_delay_multiplier(SHIELD, low))
	assert_gt(AIPersonalityTuning.item_accuracy_multiplier(SHIELD, high), AIPersonalityTuning.item_accuracy_multiplier(SHIELD, low))


func test_overtake_boldness_boundaries_lower_the_bar_to_attempt_a_pass() -> void:
	var timid: AIPersonality = _personality(0.5, 0.5, 0.0)
	var bold: AIPersonality = _personality(0.5, 0.5, 1.0)
	# Bolder AI needs a smaller speed gap and relaxes into forcing a pass sooner.
	assert_lt(AIPersonalityTuning.overtake_speed_delta_multiplier(bold), AIPersonalityTuning.overtake_speed_delta_multiplier(timid))
	assert_lt(AIPersonalityTuning.overtake_relax_multiplier(bold), AIPersonalityTuning.overtake_relax_multiplier(timid))


func test_line_discipline_boundaries_narrow_or_widen_the_lane_swing() -> void:
	var loose: AIPersonality = _personality(0.5, 0.5, 0.5, 0.5, 0.0)
	var tight: AIPersonality = _personality(0.5, 0.5, 0.5, 0.5, 1.0)
	assert_lt(AIPersonalityTuning.lane_width_multiplier(tight), AIPersonalityTuning.lane_width_multiplier(loose))


func test_drift_ambition_boundaries_shift_target_tier_and_cancel_chance() -> void:
	var low: AIPersonality = _personality(0.5, 0.5, 0.5, 0.0)
	var mid: AIPersonality = _personality(0.5, 0.5, 0.5, 0.5)
	var high: AIPersonality = _personality(0.5, 0.5, 0.5, 1.0)
	assert_eq(AIPersonalityTuning.drift_target_tier(2, low), 1, "low ambition settles for a lower tier")
	assert_eq(AIPersonalityTuning.drift_target_tier(2, mid), 2, "neutral ambition leaves the difficulty's own tier untouched")
	assert_eq(AIPersonalityTuning.drift_target_tier(2, high), 3, "high ambition chases a higher tier")
	assert_eq(AIPersonalityTuning.drift_target_tier(3, high), 3, "target tier never exceeds the [1,3] clamp")
	assert_gt(AIPersonalityTuning.drift_cancel_prob_multiplier(low), AIPersonalityTuning.drift_cancel_prob_multiplier(high), "low ambition bails out of a drift more readily")


## Spec §13.6 hard constraint: `AIPersonalityTuning` must expose no function
## that accepts or derives a speed/acceleration/speed_confidence/rubber-band
## quantity at all -- personality can only ever reach judgment-timing and
## probability multipliers. `AIDriver.compute_corner_speed`/
## `compute_rubber_band_mult` (the two speed-governing pure formulas) simply
## have no personality parameter to pass one through; see
## `test_ai_personality_behavior.gd` for the end-to-end confirmation with a
## real kart.
func test_no_tuning_function_name_references_a_speed_governing_quantity() -> void:
	# "speed_delta" (a threshold gap the overtake judgment is allowed to
	# scale, per spec §18d item 3) is intentionally not on this list -- only
	# the actual speed/acceleration/confidence/rubber-band state the hard
	# constraint (spec §13.6) forbids touching.
	var forbidden_substrings: Array[String] = ["max_speed", "acceleration", "speed_confidence", "rubber_band"]
	for method: Dictionary in AIPersonalityTuning.new().get_method_list():
		var method_name: String = str(method.get("name", ""))
		if not method_name.begins_with("item_") and not method_name.begins_with("overtake_") \
				and not method_name.begins_with("lane_") and not method_name.begins_with("drift_"):
			continue
		for forbidden: String in forbidden_substrings:
			assert_false(method_name.contains(forbidden), "%s must not touch speed-governing state" % method_name)
