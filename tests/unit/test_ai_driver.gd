extends GutTest

## Spec §13.4/§13.7: pure AIDriver decision helpers, tested without a kart or
## scene tree.


func test_steer_sign_matches_error_sign() -> void:
	var positive: float = AIDriver.compute_steer(0.5, 0.5, 0.033, 1.8, 0.35, 0.0, 0.0)
	var negative: float = AIDriver.compute_steer(-0.5, -0.5, 0.033, 1.8, 0.35, 0.0, 0.0)
	assert_gt(positive, 0.0)
	assert_lt(negative, 0.0)
	assert_almost_eq(positive, -negative, 0.0001)


func test_steer_clamps_to_unit_range_for_large_errors() -> void:
	var steer: float = AIDriver.compute_steer(3.0, 0.0, 0.033, 1.8, 0.35, 0.0, 0.0)
	assert_eq(steer, 1.0)
	var steer_negative: float = AIDriver.compute_steer(-3.0, 0.0, 0.033, 1.8, 0.35, 0.0, 0.0)
	assert_eq(steer_negative, -1.0)


func test_steer_zero_error_and_noise_yields_zero() -> void:
	assert_eq(AIDriver.compute_steer(0.0, 0.0, 0.033, 1.8, 0.35, 0.0, 0.0), 0.0)


func test_corner_speed_matches_sqrt_formula_below_max_speed() -> void:
	# sqrt(20 / 0.05) = 20.0, scaled by 0.9 confidence.
	var speed: float = AIDriver.compute_corner_speed(20.0, 0.05, 28.0, 0.9)
	assert_almost_eq(speed, 20.0 * 0.9, 0.01)


func test_corner_speed_clamps_to_max_speed_when_curvature_is_gentle() -> void:
	var speed: float = AIDriver.compute_corner_speed(20.0, 0.0001, 28.0, 1.0)
	assert_almost_eq(speed, 28.0, 0.01)


func test_corner_speed_treats_zero_curvature_as_straight() -> void:
	var speed: float = AIDriver.compute_corner_speed(20.0, 0.0, 28.0, 0.8)
	assert_almost_eq(speed, 28.0 * 0.8, 0.01)


func test_rubber_band_mult_clamps_to_plus_minus_max_band() -> void:
	# gap=2.0 would raw-compute 1 + 0.04*2.0 = 1.08, well past the +-0.05
	# band, so the clamp (not the raw formula) must be doing the work here.
	assert_almost_eq(AIDriver.compute_rubber_band_mult(2.0, 0.04, 0.05), 1.05, 0.0001)
	assert_almost_eq(AIDriver.compute_rubber_band_mult(-2.0, 0.04, 0.05), 0.95, 0.0001)


func test_rubber_band_mult_is_one_with_no_gap() -> void:
	assert_almost_eq(AIDriver.compute_rubber_band_mult(0.0, 0.04, 0.05), 1.0, 0.0001)


func test_rubber_band_mult_scales_linearly_within_the_band() -> void:
	assert_almost_eq(AIDriver.compute_rubber_band_mult(0.5, 0.04, 0.05), 1.02, 0.0001)


func test_choose_overtake_side_prefers_right_when_both_clear() -> void:
	assert_eq(AIDriver.choose_overtake_side(true, true), 1)


func test_choose_overtake_side_picks_the_only_clear_lane() -> void:
	assert_eq(AIDriver.choose_overtake_side(true, false), -1)
	assert_eq(AIDriver.choose_overtake_side(false, true), 1)


func test_choose_overtake_side_returns_zero_when_boxed_in() -> void:
	assert_eq(AIDriver.choose_overtake_side(false, false), 0)


func test_evaluate_stuck_is_none_below_the_reverse_trigger() -> void:
	assert_eq(AIDriver.evaluate_stuck(1.0), AIDriver.StuckAction.NONE)


func test_evaluate_stuck_reverses_after_two_seconds() -> void:
	assert_eq(AIDriver.evaluate_stuck(2.5), AIDriver.StuckAction.REVERSE)


func test_evaluate_stuck_requests_respawn_after_five_seconds() -> void:
	assert_eq(AIDriver.evaluate_stuck(5.5), AIDriver.StuckAction.RESPAWN)
