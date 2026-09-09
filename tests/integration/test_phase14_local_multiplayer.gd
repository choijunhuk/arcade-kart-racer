extends GutTest

const RACE_SCENE: PackedScene = preload("res://race/race.tscn")
const TEST_TRACK_SCENE: PackedScene = preload("res://track/tracks/test_loop/test_loop.tscn")
const KART: KartData = preload("res://data/karts/medium.tres")
const DIFFICULTY: AIDifficultyProfile = preload("res://data/ai/normal.tres")
const COUNTDOWN_TIMEOUT_TICKS: int = 300
const RACE_TIMEOUT_TICKS: int = 7200
const PAUSE_TICKS: int = 30
const POSITION_EPSILON: float = 0.001
const TEST_FINISH_TIMEOUT_SECONDS: float = 60.0
const MODE_SELECT_SCENE: PackedScene = preload("res://ui/menus/mode_select.tscn")
const LOCAL_LOBBY_PATH: String = "res://ui/menus/local_lobby.tscn"

var _last_scene_path: String = ""


func before_each() -> void:
	GameState.automation_mode = true
	_last_scene_path = ""
	if not GameState.scene_change_requested.is_connected(_on_scene_requested):
		GameState.scene_change_requested.connect(_on_scene_requested)


func after_each() -> void:
	get_tree().paused = false
	GameState.automation_mode = false
	if GameState.scene_change_requested.is_connected(_on_scene_requested):
		GameState.scene_change_requested.disconnect(_on_scene_requested)
	for child: Node in get_tree().root.get_children():
		if child is TransitionOverlay:
			child.free()


func test_mode_select_routes_local_multiplayer_to_the_lobby() -> void:
	var menu: Control = MODE_SELECT_SCENE.instantiate() as Control
	add_child_autofree(menu)
	await wait_process_frames(1)
	var button: Button = menu.get_node_or_null("Panel/VBox/LocalMultiplayerButton") as Button
	assert_not_null(button)
	if button == null:
		return
	button.pressed.emit()
	assert_eq(_last_scene_path, LOCAL_LOBBY_PATH)


func test_lobby_builds_a_two_player_config_when_both_players_ready() -> void:
	var exists: bool = ResourceLoader.exists(LOCAL_LOBBY_PATH, "PackedScene")
	assert_true(exists, "local lobby scene must exist")
	if not exists:
		return
	var lobby: Control = (load(LOCAL_LOBBY_PATH) as PackedScene).instantiate() as Control
	add_child_autofree(lobby)
	assert_true(bool(lobby.call("join_device", -1)))
	assert_true(bool(lobby.call("join_device", 0)))
	assert_true(bool(lobby.call("set_player_ready", -1, true)))
	assert_true(bool(lobby.call("set_player_ready", 0, true)))
	var config: RaceConfig = GameState.pending_race_config
	assert_not_null(config)
	if config == null:
		return
	assert_eq(config.race_mode, RaceConfig.RaceMode.LOCAL_MULTIPLAYER)
	assert_eq(config.human_count(), 2)
	assert_eq(config.ai_count(), 6)
	assert_eq(_last_scene_path, "res://race/race.tscn")


func test_two_scripted_players_have_independent_huds_finish_three_laps_and_reach_results() -> void:
	var race: RaceManager = RACE_SCENE.instantiate() as RaceManager
	race.tuning = race.tuning.duplicate() as RaceTuning
	race.tuning.finish_timeout_seconds = TEST_FINISH_TIMEOUT_SECONDS
	race.configure(_config(), _provider)
	add_child_autofree(race)
	await wait_physics_frames(1)
	assert_true(race.has_method("get_human_karts"))
	if not race.has_method("get_human_karts"):
		return
	var players: Array[KartController] = race.call("get_human_karts") as Array[KartController]
	assert_eq(players.size(), 2)
	if players.size() != 2:
		return
	var split: SplitScreen = race.get_node_or_null("SplitScreen") as SplitScreen
	assert_not_null(split)
	if split == null:
		return
	assert_eq(split.get_viewport_count(), 2)
	var huds: Array[RaceHud] = split.get_huds()
	assert_eq(huds.size(), 2)
	assert_eq(huds[0].get_bound_kart(), players[0])
	assert_eq(huds[1].get_bound_kart(), players[1])
	EventBus.wrong_way.emit(players[1], true)
	assert_false((huds[0].get_node("WrongWayLabel") as Label).visible)
	assert_true((huds[1].get_node("WrongWayLabel") as Label).visible)

	await _wait_for_state(race, RaceState.RESULTS, RACE_TIMEOUT_TICKS)
	assert_eq(race.get_state(), RaceState.RESULTS)
	var human_entries: Array[RaceResults.Entry] = []
	for entry: RaceResults.Entry in race.get_results():
		if entry.is_human:
			human_entries.append(entry)
	assert_eq(human_entries.size(), 2)
	for entry: RaceResults.Entry in human_entries:
		assert_gt(entry.total_time_seconds, 0.0)


func test_pause_event_from_player_two_pauses_the_shared_race() -> void:
	var race: RaceManager = RACE_SCENE.instantiate() as RaceManager
	race.configure(_config(), _provider)
	add_child_autofree(race)
	await _wait_for_state(race, RaceState.RACING, COUNTDOWN_TIMEOUT_TICKS)
	assert_eq(race.get_state(), RaceState.RACING)
	var players: Array[KartController] = race.call("get_human_karts") as Array[KartController]
	if players.size() != 2:
		assert_eq(players.size(), 2)
		return
	var before: Array[Vector3] = [players[0].global_position, players[1].global_position]
	var pause_menu: PauseMenu = race.get_node("PauseMenu") as PauseMenu
	var pause_event: InputEventAction = InputEventAction.new()
	pause_event.device = 1
	pause_event.action = &"pause"
	pause_event.pressed = true
	assert_true(pause_event.is_action_pressed(&"pause"))
	pause_menu._unhandled_input(pause_event)

	assert_eq(race.get_state(), RaceState.PAUSED)
	assert_true(pause_menu.has_method("get_pause_owner_device_id"))
	if pause_menu.has_method("get_pause_owner_device_id"):
		assert_eq(int(pause_menu.call("get_pause_owner_device_id")), 1)
	await wait_physics_frames(PAUSE_TICKS)
	assert_lte(players[0].global_position.distance_to(before[0]), POSITION_EPSILON)
	assert_lte(players[1].global_position.distance_to(before[1]), POSITION_EPSILON)
	race.resume_race()


func _config() -> RaceConfig:
	var track: TrackData = TrackData.new()
	track.id = &"test_loop"
	track.display_name = "Test Loop"
	track.scene = TEST_TRACK_SCENE
	track.laps_default = 3
	var first: PlayerSlot = PlayerSlot.new()
	first.device_id = 0
	first.driver_id = &"aurora_vale"
	first.kart_id = &"medium"
	first.grid_slot = 0
	var second: PlayerSlot = PlayerSlot.new()
	second.device_id = 1
	second.driver_id = &"echo_meridian"
	second.kart_id = &"copper_arc"
	second.grid_slot = 1
	var config: RaceConfig = RaceConfig.new()
	config.race_mode = RaceConfig.RaceMode.LOCAL_MULTIPLAYER
	config.track = track
	config.laps = 3
	config.kart_count = 2
	config.ai_difficulty = DIFFICULTY
	config.player_kart = KART
	config.players = [first, second]
	config.items_enabled = false
	return config


func _provider(kart: KartController, line: RacingLine) -> InputProvider:
	var provider: ScriptedInputProvider = ScriptedInputProvider.new(kart, line)
	provider.set_drift_on_corners(true)
	return provider


func _wait_for_state(race: RaceManager, state: int, max_ticks: int) -> void:
	for _tick: int in range(max_ticks):
		if race.get_state() == state:
			return
		await wait_physics_frames(1)


func _on_scene_requested(scene_path: String) -> void:
	_last_scene_path = scene_path
