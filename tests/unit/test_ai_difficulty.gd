extends GutTest

## Spec §13.6: easy/normal/hard resource ordering and AIDifficulty helpers.

const EASY: AIDifficultyProfile = preload("res://data/ai/easy.tres")
const NORMAL: AIDifficultyProfile = preload("res://data/ai/normal.tres")
const HARD: AIDifficultyProfile = preload("res://data/ai/hard.tres")


func test_speed_confidence_increases_from_easy_to_hard() -> void:
	assert_lt(EASY.speed_confidence, NORMAL.speed_confidence)
	assert_lt(NORMAL.speed_confidence, HARD.speed_confidence)


func test_no_difficulty_exceeds_a_speed_multiplier_of_one() -> void:
	assert_lte(EASY.speed_confidence, 1.0)
	assert_lte(NORMAL.speed_confidence, 1.0)
	assert_lte(HARD.speed_confidence, 1.0)


func test_drift_skill_and_target_tier_increase_from_easy_to_hard() -> void:
	assert_lt(EASY.drift_skill, NORMAL.drift_skill)
	assert_lt(NORMAL.drift_skill, HARD.drift_skill)
	assert_lt(EASY.target_tier, NORMAL.target_tier)
	assert_lt(NORMAL.target_tier, HARD.target_tier)


func test_late_brake_probability_decreases_from_easy_to_hard() -> void:
	assert_gt(EASY.late_brake_prob, NORMAL.late_brake_prob)
	assert_gt(NORMAL.late_brake_prob, HARD.late_brake_prob)


func test_steer_noise_decreases_from_easy_to_hard() -> void:
	assert_gt(EASY.steer_noise, NORMAL.steer_noise)
	assert_gt(NORMAL.steer_noise, HARD.steer_noise)


func test_shortcut_take_prob_increases_from_easy_to_hard() -> void:
	assert_lt(EASY.shortcut_take_prob, NORMAL.shortcut_take_prob)
	assert_lt(NORMAL.shortcut_take_prob, HARD.shortcut_take_prob)


func test_sensing_parameters_are_uniform_across_difficulties() -> void:
	# Spec §13.6 last bullet: difficulty is judgment quality, not perception.
	assert_eq(EASY.ai_tick_hz, NORMAL.ai_tick_hz)
	assert_eq(NORMAL.ai_tick_hz, HARD.ai_tick_hz)
	assert_eq(EASY.max_lateral_accel, HARD.max_lateral_accel)


func test_validate_accepts_the_three_shipped_profiles() -> void:
	assert_true(AIDifficulty.validate(EASY))
	assert_true(AIDifficulty.validate(NORMAL))
	assert_true(AIDifficulty.validate(HARD))


func test_validate_rejects_a_speed_confidence_above_one() -> void:
	var profile: AIDifficultyProfile = AIDifficultyProfile.new()
	profile.speed_confidence = 1.2
	assert_false(AIDifficulty.validate(profile))
	assert_push_error("speed_confidence exceeds 1.0")


func test_tick_interval_matches_the_configured_hz() -> void:
	var profile: AIDifficultyProfile = AIDifficultyProfile.new()
	profile.ai_tick_hz = 30.0
	assert_almost_eq(AIDifficulty.tick_interval(profile), 1.0 / 30.0, 0.0001)


func test_sample_base_lane_offset_stays_within_the_configured_range() -> void:
	var profile: AIDifficultyProfile = AIDifficultyProfile.new()
	profile.lane_offset_min = -1.5
	profile.lane_offset_max = 1.5
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 3
	for _i: int in range(50):
		var offset: float = AIDifficulty.sample_base_lane_offset(profile, rng)
		assert_between(offset, -1.5, 1.5)
