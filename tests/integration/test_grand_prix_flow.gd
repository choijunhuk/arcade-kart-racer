extends GutTest

const RACE_PATH: String = "res://race/race.tscn"
const SAVE_PATH: String = "user://phase12-gp-save.json"
const TICKS_PER_SECOND: int = 60
const SIM_SCALE: float = 8.0
const ROUND_TIMEOUT_SECONDS: float = 450.0
var _save_path: String
var _original_hz: int
var _original_scale: float


func before_each() -> void:
	_save_path = SaveManager.save_path
	SaveManager.save_path = SAVE_PATH
	_original_hz = Engine.physics_ticks_per_second
	_original_scale = Engine.time_scale
	Engine.physics_ticks_per_second = int(TICKS_PER_SECOND * SIM_SCALE)
	Engine.time_scale = SIM_SCALE
	GameState.reset_session()
	GameState.automation_mode = true


func after_each() -> void:
	SaveManager.save_path = _save_path
	Engine.physics_ticks_per_second = _original_hz
	Engine.time_scale = _original_scale
	get_tree().paused = false
	GameState.reset_session()
	GameState.automation_mode = false
	DirAccess.remove_absolute(SAVE_PATH)
	DirAccess.remove_absolute(SAVE_PATH + ".bak")


func test_two_real_tracks_reach_final_standings_and_save_the_player_best() -> void:
	var tracks: Array[TrackData] = []
	for id: String in ["test_loop", "test_hairpin"]:
		var track: TrackData = TrackData.new()
		track.id = StringName(id)
		track.scene = load("res://track/tracks/%s/%s.tscn" % [id, id]) as PackedScene
		track.laps_default = 1
		tracks.append(track)
	await _run_cup(tracks, 3, 0)
	var data: Dictionary = SaveManager.load_data()
	assert_true((data["grand_prix_bests"] as Dictionary).has("horizon_cup/normal"))


func test_four_content_tracks_complete_the_full_three_lap_championship() -> void:
	var tracks: Array[TrackData] = []
	for resource: Resource in ResourceScanner.scan_tres("res://data/tracks"):
		tracks.append(resource as TrackData)
	assert_eq(tracks.size(), 4)
	await _run_cup(tracks, 8, -1)


func _run_cup(tracks: Array[TrackData], count: int, player_slot: int) -> void:
	var config: RaceConfig = RaceConfig.new()
	config.player_kart = load("res://data/karts/medium.tres") as KartData
	config.player_driver = load("res://data/drivers/aurora_vale.tres") as DriverData
	config.ai_difficulty = load("res://data/ai/normal.tres") as AIDifficultyProfile
	config.kart_count = count
	config.player_slot = player_slot
	config.seed = 12
	GameState.grand_prix_state = GrandPrix.new()
	GameState.grand_prix_state.setup(config, tracks)
	var roster: Array[StringName] = []
	for round_index: int in range(tracks.size()):
		var manager: RaceManager = (load(RACE_PATH) as PackedScene).instantiate() as RaceManager
		var round_config: RaceConfig = GameState.grand_prix_state.current_config()
		manager.configure(round_config, _driver)
		add_child(manager)
		for slot: int in range(count):
			var kart: KartController = manager.get_karts()[slot]
			var identity: StringName = StringName("%s/%s" % [kart.kart_data.id, kart.driver_data.id])
			if round_index == 0:
				roster.append(identity)
			else:
				assert_eq(identity, roster[slot], "same participant in every scene")
		for tick: int in range(int(ROUND_TIMEOUT_SECONDS * TICKS_PER_SECOND)):
			if manager.get_state() == RaceState.RESULTS:
				break
			await wait_physics_frames(1)
		assert_eq(manager.get_state(), RaceState.RESULTS)
		assert_eq(manager.get_results().size(), count)
		for entry: RaceResults.Entry in manager.get_results():
			assert_gt(entry.total_time_seconds, 0.0, "%s %s must finish" % [round_config.track.id, entry.kart_name])
		var screen: ResultsScreen = manager.get_node("ResultsScreen") as ResultsScreen
		var label: Label = screen.get_node("Panel/VBox/GrandPrixStandings") as Label
		assert_false(label.text.is_empty())
		var button: Button = screen.get_node("Panel/VBox/Actions/RestartButton") as Button
		assert_eq(button.text, "FINISH CUP" if round_index == tracks.size() - 1 else "NEXT RACE")
		print("GP_FLOW round=%d/%d track=%s entries=%d complete=%s" % [round_index + 1, tracks.size(), round_config.track.id, manager.get_results().size(), GameState.grand_prix_state.is_complete()])
		manager.free()
		await wait_physics_frames(1)
		if round_index < tracks.size() - 1:
			assert_true(RaceModes.next_grand_prix_race())
	assert_true(GameState.grand_prix_state.is_complete())
	assert_false(RaceModes.next_grand_prix_race())
	for standing: GrandPrix.Standing in GameState.grand_prix_state.standings():
		assert_eq(standing.finishes.size(), tracks.size())


func _driver(kart: KartController, line: RacingLine) -> InputProvider:
	return ScriptedInputProvider.new(kart, line)
