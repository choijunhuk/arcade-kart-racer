extends GutTest

## Spec §13.3: pure AINavigator helpers, tested without a RacingLine or scene.


func test_look_ahead_clamps_to_minimum_at_low_speed() -> void:
	assert_eq(AINavigator.compute_look_ahead(0.0, 0.7), AINavigator.MIN_LOOK_AHEAD)


func test_look_ahead_clamps_to_maximum_at_high_speed() -> void:
	assert_eq(AINavigator.compute_look_ahead(100.0, 0.7), AINavigator.MAX_LOOK_AHEAD)


func test_look_ahead_scales_with_speed_between_the_clamps() -> void:
	assert_almost_eq(AINavigator.compute_look_ahead(15.0, 0.7), 10.5, 0.01)


func test_shortcut_never_taken_below_required_speed_regardless_of_probability() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 1
	assert_false(AINavigator.decide_shortcut(1.0, 5.0, 10.0, rng))


func test_shortcut_decision_is_deterministic_for_a_seeded_rng() -> void:
	var rng_a: RandomNumberGenerator = RandomNumberGenerator.new()
	rng_a.seed = 42
	var rng_b: RandomNumberGenerator = RandomNumberGenerator.new()
	rng_b.seed = 42
	var decisions_a: Array[bool] = []
	var decisions_b: Array[bool] = []
	for _i: int in range(20):
		decisions_a.append(AINavigator.decide_shortcut(0.5, 20.0, 10.0, rng_a))
	for _i: int in range(20):
		decisions_b.append(AINavigator.decide_shortcut(0.5, 20.0, 10.0, rng_b))
	assert_eq(decisions_a, decisions_b)


func test_shortcut_take_prob_of_one_always_takes_it_when_fast_enough() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	for _i: int in range(20):
		assert_true(AINavigator.decide_shortcut(1.0, 20.0, 10.0, rng))


func test_shortcut_take_prob_of_zero_never_takes_it() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	for _i: int in range(20):
		assert_false(AINavigator.decide_shortcut(0.0, 20.0, 10.0, rng))
