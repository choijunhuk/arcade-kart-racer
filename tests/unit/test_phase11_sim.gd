extends GutTest

const SIM: GDScript = preload("res://tests/sim/run_ai_race.gd")


func test_twenty_races_default_to_strict_balance() -> void:
	assert_true(SIM.parse_options(PackedStringArray(["--races", "20"]))["strict_balance"])
	assert_false(SIM.parse_options(PackedStringArray(["--races", "10"]))["strict_balance"])


func test_explicit_advisory_survives_argument_order() -> void:
	var options: Dictionary = SIM.parse_options(PackedStringArray([
		"--strict-balance", "off", "--races", "20", "--mixed-karts", "on",
	]))
	assert_false(options["strict_balance"])
	assert_true(options.get("mixed_karts", false))


func test_item_gate_requires_measured_control_delta() -> void:
	var summary: Dictionary = {"average_rank_one_hits_per_race": 3.0, "mean_lap1_rank8_gain": 2.0}
	assert_false(SIM.items_balance_pass(summary), "absolute gain alone cannot pass")
	summary["lap1_rank8_gain_delta"] = 0.4
	assert_true(SIM.items_balance_pass(summary))
	summary["lap1_rank8_gain_delta"] = 0.399
	assert_false(SIM.items_balance_pass(summary))
	summary["lap1_rank8_gain_delta"] = 1.0
	summary["average_rank_one_hits_per_race"] = 3.01
	assert_false(SIM.items_balance_pass(summary))


func test_item_gate_rejects_non_finite_metrics() -> void:
	assert_false(SIM.items_balance_pass({
		"average_rank_one_hits_per_race": 0.0, "lap1_rank8_gain_delta": INF,
	}))


func test_paired_summary_uses_current_control_not_an_absolute_gain() -> void:
	var paired: Dictionary = RaceSimMetrics.with_control(
		{"mean_lap1_rank8_gain": 0.95, "average_rank_one_hits_per_race": 1.0},
		{"mean_lap1_rank8_gain": 0.55},
	)
	assert_almost_eq(paired["lap1_rank8_gain_delta"], 0.4, 0.000001)
	assert_true(RaceSimMetrics.items_balance_pass(paired), "decimal subtraction must not fail an exact boundary")


func test_finish_spread_excludes_dnfs_and_is_not_divided_by_laps() -> void:
	assert_eq(RaceSimMetrics.finish_spread({"times": {"a": 180.0, "b": 195.0}}), 15.0)
	assert_eq(RaceSimMetrics.finish_spread({"times": {"a": 180.0, "b": -1.0}}), -1.0)


func test_mixed_gate_requires_all_three_classes_to_win() -> void:
	assert_true(RaceSimMetrics.classes_balance_pass({"class_wins": {"light": 1, "medium": 3, "heavy": 8}}))
	assert_false(RaceSimMetrics.classes_balance_pass({"class_wins": {"light": 0, "medium": 4, "heavy": 8}}))


func test_seed_option_preserves_a_reproducible_starting_seed() -> void:
	assert_eq(SIM.parse_options(PackedStringArray(["--seed", "7"]))["seed"], 7)


func test_simulated_physics_retains_the_real_sixty_hz_step() -> void:
	assert_almost_eq(SIM.SIM_TIME_SCALE / float(SIM.SIM_PHYSICS_TICKS), 1.0 / 60.0, 0.000001)
