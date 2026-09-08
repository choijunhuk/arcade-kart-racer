extends GutTest

## Spec §13.8: real AIController-driven karts racing real tracks. Sped up with
## `Engine.time_scale` the same way `tests/sim/run_ai_race.gd` is, since a
## real lap takes 60-75s of simulated time (spec §15.7).

const RACE_SCENE_PATH: String = "res://race/race.tscn"
const HAIRPIN_TRACK_PATH: String = "res://track/tracks/test_hairpin/test_hairpin.tscn"
const TRACK01_PATH: String = "res://track/tracks/track_01_ridgeline_circuit/track_01_ridgeline_circuit.tscn"
const MEDIUM_KART: KartData = preload("res://data/karts/medium.tres")
const NORMAL_DIFFICULTY: AIDifficultyProfile = preload("res://data/ai/normal.tres")
const EASY_DIFFICULTY: AIDifficultyProfile = preload("res://data/ai/easy.tres")
const HARD_DIFFICULTY: AIDifficultyProfile = preload("res://data/ai/hard.tres")
const SIM_TIME_SCALE: float = 4.0
const MAX_TICKS: int = 6000
const FIXED_SEED: int = 1234
## Multiple seeds so the Easy-vs-Hard pacing comparison is a mean over several
## independent AI rolls, not one seed's noise (spec §13.8: Hard must pace
## faster than Easy in general, not just on a single lucky lap).
const DIFFICULTY_ORDER_SEEDS: Array[int] = [101, 202, 303]
## Small floor on the mean-time gap so the assertion demands a real pacing
## difference, not a statistical coin flip.
const DIFFICULTY_ORDER_MARGIN_SECONDS: float = 0.1

var _respawn_count: int = 0
var _drift_started_count: int = 0


func before_each() -> void:
	_respawn_count = 0
	_drift_started_count = 0
	Engine.time_scale = SIM_TIME_SCALE
	EventBus.kart_respawned.connect(_on_kart_respawned)
	EventBus.drift_started.connect(_on_drift_started)


func after_each() -> void:
	Engine.time_scale = 1.0
	if EventBus.kart_respawned.is_connected(_on_kart_respawned):
		EventBus.kart_respawned.disconnect(_on_kart_respawned)
	if EventBus.drift_started.is_connected(_on_drift_started):
		EventBus.drift_started.disconnect(_on_drift_started)


func test_one_ai_kart_completes_a_hairpin_lap_without_respawn_and_drifts() -> void:
	var manager: RaceManager = _make_manager(_make_config(HAIRPIN_TRACK_PATH, 1, 1, NORMAL_DIFFICULTY))
	add_child_autofree(manager)
	await _wait_for_state(manager, RaceState.RESULTS, MAX_TICKS)
	assert_eq(manager.get_state(), RaceState.RESULTS, "the lone AI kart must finish its one lap")
	assert_eq(_respawn_count, 0, "a clean lap should not need a respawn")
	assert_gt(_drift_started_count, 0, "a hairpin lap should include at least one drift")


func test_four_ai_karts_on_track01_all_finish_one_lap_without_getting_stuck() -> void:
	var manager: RaceManager = _make_manager(_make_config(TRACK01_PATH, 1, 4, NORMAL_DIFFICULTY))
	add_child_autofree(manager)
	await _wait_for_state(manager, RaceState.RESULTS, MAX_TICKS)
	assert_eq(manager.get_state(), RaceState.RESULTS, "all 4 AI karts must finish within the time budget")
	var entries: Array[RaceResults.Entry] = manager.get_results()
	assert_eq(entries.size(), 4, "every kart must appear in the final results")


## Runs several independent seeds per difficulty (1 lap on the hairpin, kept
## cheap the same way the other integration tests are: `Engine.time_scale`
## sped up in `before_each` plus a single-kart, single-lap race) and compares
## the mean finish time so one AI roll's noise cannot flip the result.
func test_hard_difficulty_laps_the_hairpin_faster_than_easy_on_average() -> void:
	var easy_mean: float = await _mean_lap_time_across_seeds(EASY_DIFFICULTY)
	var hard_mean: float = await _mean_lap_time_across_seeds(HARD_DIFFICULTY)
	assert_gt(easy_mean, 0.0)
	assert_gt(hard_mean, 0.0)
	assert_lt(hard_mean, easy_mean - DIFFICULTY_ORDER_MARGIN_SECONDS, "Hard's mean lap time across seeds must beat Easy's by a meaningful margin")


func _mean_lap_time_across_seeds(difficulty: AIDifficultyProfile) -> float:
	var total: float = 0.0
	var finished: int = 0
	for seed: int in DIFFICULTY_ORDER_SEEDS:
		var time: float = await _run_one_lap_and_get_finish_time(difficulty, seed)
		if time >= 0.0:
			total += time
			finished += 1
	assert_gt(finished, 0, "at least one seed must finish to compute a mean")
	return total / float(finished) if finished > 0 else -1.0


func _run_one_lap_and_get_finish_time(difficulty: AIDifficultyProfile, seed: int = FIXED_SEED) -> float:
	var manager: RaceManager = _make_manager(_make_config(HAIRPIN_TRACK_PATH, 1, 1, difficulty, seed))
	add_child_autofree(manager)
	await _wait_for_state(manager, RaceState.RESULTS, MAX_TICKS)
	assert_eq(manager.get_state(), RaceState.RESULTS)
	var entries: Array[RaceResults.Entry] = manager.get_results()
	if entries.is_empty():
		return -1.0
	return entries[0].total_time_seconds


func _make_manager(config: RaceConfig) -> RaceManager:
	var manager: RaceManager = (load(RACE_SCENE_PATH) as PackedScene).instantiate() as RaceManager
	manager.configure(config)
	return manager


func _make_config(track_path: String, laps: int, kart_count: int, difficulty: AIDifficultyProfile, seed: int = FIXED_SEED) -> RaceConfig:
	var track_data: TrackData = TrackData.new()
	track_data.id = &"ai_race_test_track"
	track_data.scene = load(track_path) as PackedScene
	var config: RaceConfig = RaceConfig.new()
	config.track = track_data
	config.laps = laps
	config.kart_count = kart_count
	config.player_kart = MEDIUM_KART
	config.player_slot = -1
	config.ai_difficulty = difficulty
	config.seed = seed
	return config


func _wait_for_state(manager: RaceManager, target_state: int, max_ticks: int) -> void:
	for _tick: int in range(max_ticks):
		if manager.get_state() == target_state:
			return
		await wait_physics_frames(1)


func _on_kart_respawned(_kart: Node) -> void:
	_respawn_count += 1


func _on_drift_started(_kart: Node, _direction: int) -> void:
	_drift_started_count += 1
