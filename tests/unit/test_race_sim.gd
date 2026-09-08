extends GutTest

const SIM_SCRIPT_PATH: String = "res://tests/sim/run_ai_race.gd"


func test_sim_options_default_to_one_three_lap_eight_kart_race() -> void:
	var script: GDScript = _load_sim_script()
	if script == null:
		return
	var options: Dictionary = script.call("parse_options", PackedStringArray()) as Dictionary
	assert_eq(int(options["laps"]), 3)
	assert_eq(int(options["karts"]), 8)
	assert_eq(int(options["races"]), 1)


func test_sim_options_accept_user_laps_karts_and_races() -> void:
	var script: GDScript = _load_sim_script()
	if script == null:
		return
	var args: PackedStringArray = PackedStringArray(["--laps", "2", "--karts", "4", "--races", "3"])
	var options: Dictionary = script.call("parse_options", args) as Dictionary
	assert_eq(int(options["laps"]), 2)
	assert_eq(int(options["karts"]), 4)
	assert_eq(int(options["races"]), 3)


func test_sim_failure_requires_every_time_to_be_non_negative() -> void:
	var script: GDScript = _load_sim_script()
	if script == null:
		return
	assert_false(bool(script.call("has_unfinished", {"Kart1": 10.0, "Kart2": 12.0})))
	assert_true(bool(script.call("has_unfinished", {"Kart1": 10.0, "Kart2": -1.0})))


func test_sim_options_default_to_normal_difficulty_and_track01() -> void:
	var script: GDScript = _load_sim_script()
	if script == null:
		return
	var options: Dictionary = script.call("parse_options", PackedStringArray()) as Dictionary
	assert_eq(options["difficulty"], &"normal")
	assert_eq(options["track"], &"track_01")


func test_sim_options_accept_difficulty_and_track() -> void:
	var script: GDScript = _load_sim_script()
	if script == null:
		return
	var args: PackedStringArray = PackedStringArray(["--difficulty", "hard", "--track", "test_hairpin"])
	var options: Dictionary = script.call("parse_options", args) as Dictionary
	assert_eq(options["difficulty"], &"hard")
	assert_eq(options["track"], &"test_hairpin")


func test_sim_options_fall_back_for_an_unknown_difficulty_or_track() -> void:
	var script: GDScript = _load_sim_script()
	if script == null:
		return
	var args: PackedStringArray = PackedStringArray(["--difficulty", "extreme", "--track", "moon_base"])
	var options: Dictionary = script.call("parse_options", args) as Dictionary
	assert_eq(options["difficulty"], &"normal")
	assert_eq(options["track"], &"track_01")


func test_race_fails_when_any_kart_never_finishes() -> void:
	var script: GDScript = _load_sim_script()
	if script == null:
		return
	var race_output: Dictionary = {"times": {"Kart1": 60.0, "Kart2": -1.0}, "respawns": {"Kart1": 0, "Kart2": 0}, "wall_head_on_count": 0}
	assert_true(bool(script.call("_race_failed", race_output, 3)))


func test_race_fails_when_a_kart_respawns_more_than_twice() -> void:
	var script: GDScript = _load_sim_script()
	if script == null:
		return
	var race_output: Dictionary = {"times": {"Kart1": 60.0}, "respawns": {"Kart1": 3}, "wall_head_on_count": 0}
	assert_true(bool(script.call("_race_failed", race_output, 3)))


func test_race_fails_when_wall_head_ons_exceed_the_per_lap_budget() -> void:
	var script: GDScript = _load_sim_script()
	if script == null:
		return
	var race_output: Dictionary = {"times": {"Kart1": 60.0}, "respawns": {"Kart1": 0}, "wall_head_on_count": 10}
	assert_true(bool(script.call("_race_failed", race_output, 3)))


func test_race_passes_within_every_budget() -> void:
	var script: GDScript = _load_sim_script()
	if script == null:
		return
	var race_output: Dictionary = {"times": {"Kart1": 60.0, "Kart2": 65.0}, "respawns": {"Kart1": 1, "Kart2": 2}, "wall_head_on_count": 6}
	assert_false(bool(script.call("_race_failed", race_output, 3)))


func test_summarize_averages_lap_time_across_finishers_and_races() -> void:
	var script: GDScript = _load_sim_script()
	if script == null:
		return
	var race_outputs: Array[Dictionary] = [
		{"times": {"Kart1": 60.0, "Kart2": -1.0}},
		{"times": {"Kart1": 90.0}},
	]
	var summary: Dictionary = script.call("_summarize", race_outputs, 3) as Dictionary
	# Finishers only: 60/3=20, 90/3=30 -> mean 25.
	assert_almost_eq(float(summary["mean_lap_time_seconds"]), 25.0, 0.001)
	assert_eq(int(summary["finisher_samples"]), 2)


func _load_sim_script() -> GDScript:
	var exists: bool = ResourceLoader.exists(SIM_SCRIPT_PATH)
	assert_true(exists, "real headless race simulator must exist")
	return load(SIM_SCRIPT_PATH) as GDScript if exists else null
