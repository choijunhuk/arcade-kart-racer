extends GutTest

## Phase 18e-1: the difficulty select menu's class picker drives the pending
## config/roster and remembers the choice in settings gameplay.speed_class.

const DIFFICULTY_SELECT_PATH: String = "res://ui/menus/difficulty_select.tscn"
const TEST_SETTINGS_PATH: String = "user://phase18e_settings_test.cfg"

var _settings_path: String


func before_each() -> void:
	GameState.reset_session()
	_settings_path = SettingsManager.settings_path
	SettingsManager.settings_path = TEST_SETTINGS_PATH
	SettingsManager.load_settings()


func after_each() -> void:
	SettingsManager.settings_path = _settings_path
	SettingsManager.load_settings()
	DirAccess.remove_absolute(TEST_SETTINGS_PATH)
	GameState.reset_session()
	_cancel_leaked_scene_transition()


## test_turbo_choice_scales_pending_config_and_roster_max_speed presses
## ui_accept, which drives the real DifficultySelectMenu -> GameState.change_scene()
## path and parents a PROCESS_MODE_ALWAYS TransitionOverlay directly onto
## get_tree().root (outside this test's own scene, so add_child_autofree never
## sees it). Left alone it keeps animating and eventually calls
## change_scene_to_packed() on a later, unrelated test's frames, swapping the
## real current_scene to a live race mid-suite and corrupting other tests'
## physics. Free it here, before any other test can advance another frame.
func _cancel_leaked_scene_transition() -> void:
	var root: Window = get_tree().root
	var transition: Node = root.get_node_or_null(NodePath(String(GameState.TRANSITION_NODE_NAME)))
	if transition != null:
		root.remove_child(transition)
		transition.free()


func test_difficulty_select_lists_three_classes_defaulting_to_standard() -> void:
	GameState.set_selection(&"aurora_vale", &"medium", &"track_01_ridgeline_circuit")
	var menu: Control = _instantiate_menu()
	add_child_autofree(menu)
	await wait_process_frames(1)
	var option: OptionButton = menu.get_node("Panel/VBox/SpeedClassOption") as OptionButton
	assert_eq(option.item_count, 3)
	assert_eq(option.get_item_text(0), "CRUISE")
	assert_eq(option.get_item_text(1), "STANDARD")
	assert_eq(option.get_item_text(2), "TURBO")
	assert_eq(option.selected, 1)
	assert_false(option.disabled)


func test_turbo_choice_scales_pending_config_and_roster_max_speed() -> void:
	GameState.set_selection(&"aurora_vale", &"medium", &"track_01_ridgeline_circuit")
	var menu: Control = _instantiate_menu()
	add_child_autofree(menu)
	await wait_process_frames(1)
	(menu.get_node("Panel/VBox/SpeedClassOption") as OptionButton).select(2)

	await _press_action(&"ui_accept")

	var config: RaceConfig = GameState.pending_race_config
	assert_not_null(config)
	if config == null:
		return
	assert_eq(config.speed_class, RaceConfig.SpeedClass.TURBO)
	assert_eq(GameState.selected_speed_class, RaceConfig.SpeedClass.TURBO)
	var roster: RaceRoster = RaceRoster.new()
	var scaled: KartData = roster.kart_for_slot(config, config.player_slot, config.players[0])
	var base_speed: float = (load("res://data/karts/medium.tres") as KartData).max_speed
	assert_almost_eq(scaled.max_speed, base_speed * 1.15, 0.001)
	assert_eq(int(SettingsManager.get_setting(&"gameplay", &"speed_class", -1)), RaceConfig.SpeedClass.TURBO)


func test_next_menu_open_restores_the_remembered_speed_class() -> void:
	SettingsManager.update_setting(&"gameplay", &"speed_class", RaceConfig.SpeedClass.CRUISE)
	GameState.set_selection(&"aurora_vale", &"medium", &"track_01_ridgeline_circuit")
	var menu: Control = _instantiate_menu()
	add_child_autofree(menu)
	await wait_process_frames(1)
	assert_eq((menu.get_node("Panel/VBox/SpeedClassOption") as OptionButton).selected, 0)


func test_time_trial_forces_and_disables_standard_class_selection() -> void:
	GameState.selected_race_mode = RaceConfig.RaceMode.TIME_TRIAL
	SettingsManager.update_setting(&"gameplay", &"speed_class", RaceConfig.SpeedClass.TURBO)
	GameState.set_selection(&"aurora_vale", &"medium", &"track_01_ridgeline_circuit")
	var menu: Control = _instantiate_menu()
	add_child_autofree(menu)
	await wait_process_frames(1)
	var option: OptionButton = menu.get_node("Panel/VBox/SpeedClassOption") as OptionButton
	assert_eq(option.selected, 1)
	assert_true(option.disabled)


func _instantiate_menu() -> Control:
	return (load(DIFFICULTY_SELECT_PATH) as PackedScene).instantiate() as Control


func _press_action(action: StringName) -> void:
	var press: InputEventAction = InputEventAction.new()
	press.action = action
	press.pressed = true
	Input.parse_input_event(press)
	await wait_process_frames(1)
	var release: InputEventAction = InputEventAction.new()
	release.action = action
	release.pressed = false
	Input.parse_input_event(release)
	await wait_process_frames(1)
