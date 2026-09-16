extends GutTest

## Phase 18e-2: the difficulty select and local lobby MIRROR toggles drive
## the pending config and remember the choice in settings gameplay.mirror;
## online (NetRaceSetup) and the tutorial launcher stay forced off.

const DIFFICULTY_SELECT_PATH: String = "res://ui/menus/difficulty_select.tscn"
const LOCAL_LOBBY_PATH: String = "res://ui/menus/local_lobby.tscn"
const TEST_SETTINGS_PATH: String = "user://phase18e_mirror_settings_test.cfg"

var _settings_path: String


func before_each() -> void:
	GameState.reset_session()
	# Mirror mode is gated by the 18e-3 unlock rules; this file covers the
	# toggle itself, so the automation bypass keeps it enabled and pressable.
	GameState.automation_mode = true
	_settings_path = SettingsManager.settings_path
	SettingsManager.settings_path = TEST_SETTINGS_PATH
	SettingsManager.load_settings()


func after_each() -> void:
	SettingsManager.settings_path = _settings_path
	SettingsManager.load_settings()
	DirAccess.remove_absolute(TEST_SETTINGS_PATH)
	GameState.reset_session()
	GameState.automation_mode = false
	_cancel_leaked_scene_transition()


## See test_phase18e_speed_class_menu.gd: a real go_to() parents a
## PROCESS_MODE_ALWAYS TransitionOverlay directly onto get_tree().root,
## outside this test's own scene, so add_child_autofree never sees it. Left
## alone it keeps animating into later tests' frames.
func _cancel_leaked_scene_transition() -> void:
	var root: Window = get_tree().root
	var transition: Node = root.get_node_or_null(NodePath(String(GameState.TRANSITION_NODE_NAME)))
	if transition != null:
		root.remove_child(transition)
		transition.free()


func test_difficulty_select_mirror_toggle_defaults_to_the_remembered_setting() -> void:
	SettingsManager.update_setting(&"gameplay", &"mirror", true)
	GameState.set_selection(&"aurora_vale", &"medium", &"track_01_ridgeline_circuit")
	var menu: Control = _instantiate_menu(DIFFICULTY_SELECT_PATH)
	add_child_autofree(menu)
	await wait_process_frames(1)
	var toggle: CheckButton = menu.get_node("Panel/VBox/MirrorToggle") as CheckButton
	assert_not_null(toggle)
	if toggle != null:
		assert_true(toggle.button_pressed)


func test_difficulty_select_mirror_choice_propagates_to_config_and_settings() -> void:
	GameState.set_selection(&"aurora_vale", &"medium", &"track_01_ridgeline_circuit")
	var menu: Control = _instantiate_menu(DIFFICULTY_SELECT_PATH)
	add_child_autofree(menu)
	await wait_process_frames(1)
	(menu.get_node("Panel/VBox/MirrorToggle") as CheckButton).button_pressed = true

	await _press_action(&"ui_accept")

	var config: RaceConfig = GameState.pending_race_config
	assert_not_null(config)
	if config != null:
		assert_true(config.mirror)
	assert_true(bool(SettingsManager.get_setting(&"gameplay", &"mirror", false)))


func test_local_lobby_mirror_toggle_propagates_to_the_shared_config() -> void:
	var exists: bool = ResourceLoader.exists(LOCAL_LOBBY_PATH, "PackedScene")
	assert_true(exists, "local lobby scene must exist")
	if not exists:
		return
	var lobby: Control = (load(LOCAL_LOBBY_PATH) as PackedScene).instantiate() as Control
	add_child_autofree(lobby)
	(lobby.get_node("Panel/VBox/MirrorToggle") as CheckButton).button_pressed = true
	assert_true(bool(lobby.call("join_device", -1)))
	assert_true(bool(lobby.call("join_device", 0)))
	assert_true(bool(lobby.call("set_player_ready", -1, true)))
	assert_true(bool(lobby.call("set_player_ready", 0, true)))
	var config: RaceConfig = GameState.pending_race_config
	assert_not_null(config)
	if config != null:
		assert_true(config.mirror)
	assert_true(bool(SettingsManager.get_setting(&"gameplay", &"mirror", false)))


func _instantiate_menu(path: String) -> Control:
	return (load(path) as PackedScene).instantiate() as Control


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
