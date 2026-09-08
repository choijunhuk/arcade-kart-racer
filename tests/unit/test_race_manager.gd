extends GutTest

const MANAGER_PATH: String = "res://race/race_manager.gd"


func test_transition_table_accepts_only_the_race_flow_edges() -> void:
	var script: GDScript = _load_manager()
	if script == null:
		return
	assert_true(bool(script.call("can_transition", RaceState.LOADING, RaceState.COUNTDOWN)))
	assert_true(bool(script.call("can_transition", RaceState.COUNTDOWN, RaceState.RACING)))
	assert_true(bool(script.call("can_transition", RaceState.RACING, RaceState.FINISHING)))
	assert_true(bool(script.call("can_transition", RaceState.FINISHING, RaceState.RESULTS)))
	assert_false(bool(script.call("can_transition", RaceState.LOADING, RaceState.RESULTS)))
	assert_false(bool(script.call("can_transition", RaceState.RESULTS, RaceState.RACING)))
	assert_false(bool(script.call("can_transition", RaceState.RACING, RaceState.COUNTDOWN)))
	assert_false(bool(script.call("can_transition", RaceState.RESULTS, RaceState.PAUSED)))


func test_pause_edges_exist_only_for_countdown_and_racing() -> void:
	var script: GDScript = _load_manager()
	if script == null:
		return
	assert_true(bool(script.call("can_transition", RaceState.COUNTDOWN, RaceState.PAUSED)))
	assert_true(bool(script.call("can_transition", RaceState.RACING, RaceState.PAUSED)))
	assert_true(bool(script.call("can_transition", RaceState.PAUSED, RaceState.COUNTDOWN)))
	assert_true(bool(script.call("can_transition", RaceState.PAUSED, RaceState.RACING)))
	assert_false(bool(script.call("can_transition", RaceState.LOADING, RaceState.PAUSED)))
	assert_false(bool(script.call("can_transition", RaceState.FINISHING, RaceState.PAUSED)))


func test_finishing_completes_for_all_karts_or_timeout() -> void:
	var script: GDScript = _load_manager()
	if script == null:
		return
	assert_true(bool(script.call("finishing_complete", 4, 4, 0.0, 15.0)))
	assert_false(bool(script.call("finishing_complete", 2, 4, 14.9, 15.0)))
	assert_true(bool(script.call("finishing_complete", 2, 4, 15.0, 15.0)))


func _load_manager() -> GDScript:
	var exists: bool = ResourceLoader.exists(MANAGER_PATH)
	assert_true(exists, "RaceManager script must exist")
	return load(MANAGER_PATH) as GDScript if exists else null

