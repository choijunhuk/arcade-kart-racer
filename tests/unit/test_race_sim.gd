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


func _load_sim_script() -> GDScript:
	var exists: bool = ResourceLoader.exists(SIM_SCRIPT_PATH)
	assert_true(exists, "real headless race simulator must exist")
	return load(SIM_SCRIPT_PATH) as GDScript if exists else null
