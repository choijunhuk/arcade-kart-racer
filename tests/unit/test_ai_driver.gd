extends GutTest

## Spec §13.4/§13.7: pure AIDriver decision helpers, tested without a kart or
## scene tree, plus a couple of `compute_frame`/`_compute_target_speed` cases
## below that need a real `KartController` to drive.

const KART_SCENE: PackedScene = preload("res://kart/kart.tscn")
const NORMAL_DIFFICULTY: AIDifficultyProfile = preload("res://data/ai/normal.tres")
const HARD_DIFFICULTY: AIDifficultyProfile = preload("res://data/ai/hard.tres")


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


## Spec §13.4: a hit reaction is a brief, involuntary loss of control, not a
## wedged-against-geometry stall, so 6s of HIT state (well past the 2s
## reverse and 5s respawn stuck triggers) must never accumulate into either.
func test_hit_state_never_accumulates_into_reverse_or_respawn() -> void:
	var kart: KartController = KART_SCENE.instantiate() as KartController
	add_child_autofree(kart)
	kart.state = KartState.HIT
	var driver: AIDriver = AIDriver.new(RandomNumberGenerator.new())
	var nav: AINavigator.NavResult = AINavigator.NavResult.new()
	nav.target_point = kart.global_position
	var sensors: AISensors.SensorReport = AISensors.SensorReport.new()
	var respawn_requests: int = 0
	var context: AIRaceContext = AIRaceContext.new()
	context.request_respawn = func(_k: KartController) -> void: respawn_requests += 1
	var dt: float = 1.0 / 30.0
	var ticks: int = int(6.0 / dt)
	for _tick: int in range(ticks):
		var frame: InputFrame = driver.compute_frame(kart, NORMAL_DIFFICULTY, nav, sensors, context, dt)
		assert_eq(frame.brake, 0.0, "a HIT-state frame must not hold reverse brake")
		assert_eq(frame.throttle, 0.0, "a HIT-state frame must stay neutral, not drive")
	assert_eq(respawn_requests, 0, "6s of HIT state must never fire a stuck respawn request")


## Spec §13.6: the rubber-band catch-up multiplier may never push the AI's
## target speed past its own kart's spec max speed, even at the maximum gap.
func test_target_speed_never_exceeds_kart_max_speed_with_max_rubber_band_gap_on_hard() -> void:
	var kart: KartController = KART_SCENE.instantiate() as KartController
	add_child_autofree(kart)
	var player: KartController = KART_SCENE.instantiate() as KartController
	add_child_autofree(player)
	var racing_line: RacingLine = RacingLine.new()
	add_child_autofree(racing_line)
	var tracker: PositionTracker = PositionTracker.new()
	add_child_autofree(tracker)
	tracker.register_kart(kart)
	tracker.register_kart(player)
	# Directly seed each kart's cached progress (bypassing checkpoints/lap
	# tracking, which this test doesn't need) so the player is a full lap
	# ahead of the AI kart: gap = (player - ai) / lap_length clamps to 1.0.
	tracker._records[kart.get_instance_id()].progress = 0.0
	tracker._records[player.get_instance_id()].progress = racing_line.length()
	var context: AIRaceContext = AIRaceContext.new()
	context.racing_line = racing_line
	context.position_tracker = tracker
	context.player_kart = player
	var nav: AINavigator.NavResult = AINavigator.NavResult.new()
	nav.curvature_ahead = 0.0 # straight: corner speed alone would already sit at max_speed
	var driver: AIDriver = AIDriver.new(RandomNumberGenerator.new())
	var target_speed: float = driver._compute_target_speed(kart, HARD_DIFFICULTY, nav, context)
	assert_lte(target_speed, kart.get_kart_data().max_speed, "AI target speed must never exceed the kart's own max_speed")


func test_active_boost_raises_straight_target_without_raising_corner_limit() -> void:
	var kart: KartController = KART_SCENE.instantiate() as KartController
	add_child_autofree(kart)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var driver: AIDriver = AIDriver.new(rng)
	var nav: AINavigator.NavResult = AINavigator.NavResult.new()
	var profile: AIDifficultyProfile = HARD_DIFFICULTY.duplicate(true) as AIDifficultyProfile
	var context: AIRaceContext = AIRaceContext.new()
	var base: float = driver._compute_target_speed(kart, profile, nav, context)
	var boost: BoostSpecData = BoostSpecData.new()
	boost.speed_mult = 1.4
	boost.duration = 2.0
	kart.request_boost(boost, &"item_boost")
	var boosted: float = driver._compute_target_speed(kart, profile, nav, context)
	assert_gt(boosted, base, "AI must not brake away its own Nitro on straights")
	assert_lte(boosted, kart.get_kart_data().max_speed * kart.boost_controller.get_result().speed_mult)
	nav.curvature_ahead = 0.1
	assert_almost_eq(driver._compute_target_speed(kart, profile, nav, context), sqrt(profile.max_lateral_accel / nav.curvature_ahead), 0.001)


func test_ai_hold_preserves_countersteer_to_widen_a_drift() -> void:
	var kart: KartController = KART_SCENE.instantiate() as KartController
	add_child_autofree(kart)
	var planner: AIDriftPlanner = AIDriftPlanner.new(RandomNumberGenerator.new())
	planner._locked_direction = 1
	var frame: InputFrame = InputFrame.zero()
	frame.steer = -0.25
	planner._update_hold(frame, kart, HARD_DIFFICULTY, 0.06, 1.0 / 30.0)
	assert_eq(frame.steer, -0.25, "KartPhysics keeps drift direction locked; AI can countersteer without reversing it")
