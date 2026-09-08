extends GutTest

const TUNING_PATH: String = "res://data/tuning/race_default.tres"


func test_default_race_tuning_exposes_phase_five_cadences() -> void:
	assert_true(ResourceLoader.exists(TUNING_PATH))
	if not ResourceLoader.exists(TUNING_PATH):
		return
	var tuning: Resource = load(TUNING_PATH) as Resource
	assert_almost_eq(float(tuning.get("countdown_step_seconds")), 1.0, 0.001)
	assert_almost_eq(float(tuning.get("finish_timeout_seconds")), 15.0, 0.001)
	assert_almost_eq(float(tuning.get("position_update_hz")), 5.0, 0.001)
	assert_gt(float(tuning.get("results_delay_seconds")), 0.0)

