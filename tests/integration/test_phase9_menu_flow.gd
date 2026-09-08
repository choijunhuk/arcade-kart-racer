extends GutTest

const MAIN_MENU_PATH: String = "res://ui/menus/main_menu.tscn"
const MODE_SELECT_PATH: String = "res://ui/menus/mode_select.tscn"
const DRIVER_SELECT_PATH: String = "res://ui/menus/driver_select.tscn"
const KART_SELECT_PATH: String = "res://ui/menus/kart_select.tscn"
const TRACK_SELECT_PATH: String = "res://ui/menus/track_select.tscn"
const DIFFICULTY_SELECT_PATH: String = "res://ui/menus/difficulty_select.tscn"
const BOOTSTRAP_PATH: String = "res://scenes/main.tscn"

var _last_scene_path: String = ""


func before_each() -> void:
	_last_scene_path = ""
	GameState.reset_session()
	if not GameState.scene_change_requested.is_connected(_on_scene_change_requested):
		GameState.scene_change_requested.connect(_on_scene_change_requested)


func after_each() -> void:
	_cancel_transition_overlays()
	if GameState.scene_change_requested.is_connected(_on_scene_change_requested):
		GameState.scene_change_requested.disconnect(_on_scene_change_requested)


func test_main_menu_ui_accept_requests_mode_select_and_disables_time_trial() -> void:
	var menu: Control = _instantiate_control(MAIN_MENU_PATH)
	if menu == null:
		return
	add_child_autofree(menu)
	await wait_process_frames(1)
	var play: Button = menu.get_node("Panel/VBox/PlayButton") as Button
	var time_trial: Button = menu.get_node("Panel/VBox/TimeTrialButton") as Button
	assert_eq(get_viewport().gui_get_focus_owner(), play)
	assert_true(time_trial.disabled)

	await _press_action(&"ui_accept")

	assert_eq(_last_scene_path, MODE_SELECT_PATH)


func test_mode_select_ui_accept_requests_driver_select_and_disables_grand_prix() -> void:
	var menu: Control = _instantiate_control(MODE_SELECT_PATH)
	if menu == null:
		return
	add_child_autofree(menu)
	await wait_process_frames(1)
	var single_race: Button = menu.get_node("Panel/VBox/SingleRaceButton") as Button
	var grand_prix: Button = menu.get_node("Panel/VBox/GrandPrixButton") as Button
	assert_eq(get_viewport().gui_get_focus_owner(), single_race)
	assert_true(grand_prix.disabled)

	await _press_action(&"ui_accept")

	assert_eq(_last_scene_path, DRIVER_SELECT_PATH)


func test_driver_grid_scans_eight_cards_and_accepts_the_focused_driver() -> void:
	var menu: Control = _instantiate_control(DRIVER_SELECT_PATH)
	if menu == null:
		return
	add_child_autofree(menu)
	await wait_process_frames(1)
	var grid: GridContainer = menu.get_node("Panel/VBox/Scroll/Grid") as GridContainer
	assert_eq(grid.get_child_count(), 8)
	assert_eq(get_viewport().gui_get_focus_owner(), grid.get_child(0))

	await _press_action(&"ui_accept")

	assert_eq(GameState.selected_driver_id, &"aurora_vale")
	assert_eq(_last_scene_path, KART_SELECT_PATH)


func test_kart_grid_scans_three_cards_and_accepts_the_focused_kart() -> void:
	var menu: Control = _instantiate_control(KART_SELECT_PATH)
	if menu == null:
		return
	add_child_autofree(menu)
	await wait_process_frames(1)
	var grid: GridContainer = menu.get_node("Panel/VBox/Scroll/Grid") as GridContainer
	assert_eq(grid.get_child_count(), 3)
	assert_eq(get_viewport().gui_get_focus_owner(), grid.get_child(0))

	await _press_action(&"ui_accept")

	assert_eq(GameState.selected_kart_id, &"heavy")
	assert_eq(_last_scene_path, TRACK_SELECT_PATH)


func test_track_select_shows_laps_and_accepts_the_focused_track() -> void:
	var menu: Control = _instantiate_control(TRACK_SELECT_PATH)
	if menu == null:
		return
	add_child_autofree(menu)
	await wait_process_frames(1)
	var list: VBoxContainer = menu.get_node("Panel/VBox/TrackList") as VBoxContainer
	assert_eq(list.get_child_count(), 1)
	var track_button: Button = list.get_child(0) as Button
	assert_string_contains(track_button.text, "3 LAPS")
	assert_eq(get_viewport().gui_get_focus_owner(), track_button)

	await _press_action(&"ui_accept")

	assert_eq(GameState.selected_track_id, &"track_01_ridgeline_circuit")
	assert_eq(_last_scene_path, DIFFICULTY_SELECT_PATH)


func test_difficulty_accept_builds_selected_config_and_requests_race() -> void:
	GameState.set_selection(&"aurora_vale", &"medium", &"track_01_ridgeline_circuit")
	var menu: Control = _instantiate_control(DIFFICULTY_SELECT_PATH)
	if menu == null:
		return
	add_child_autofree(menu)
	await wait_process_frames(1)
	var list: VBoxContainer = menu.get_node("Panel/VBox/DifficultyList") as VBoxContainer
	assert_eq(list.get_child_count(), 3)
	assert_eq(get_viewport().gui_get_focus_owner(), list.get_child(0))

	await _press_action(&"ui_accept")

	var config: RaceConfig = GameState.pending_race_config
	assert_not_null(config)
	if config == null:
		return
	assert_eq(config.player_driver.id, &"aurora_vale")
	assert_eq(config.player_kart.id, &"medium")
	assert_eq(config.track.id, &"track_01_ridgeline_circuit")
	assert_eq(config.ai_difficulty.id, &"easy")
	assert_eq(_last_scene_path, "res://race/race.tscn")


func test_bootstrap_scene_contains_the_real_main_menu() -> void:
	var bootstrap: Node = (load(BOOTSTRAP_PATH) as PackedScene).instantiate()
	autofree(bootstrap)
	assert_not_null(bootstrap.get_node_or_null("MainMenu"))
	assert_not_null(bootstrap.get_node_or_null("MainMenu/Panel/VBox/PlayButton"))


func _instantiate_control(path: String) -> Control:
	var exists: bool = ResourceLoader.exists(path, "PackedScene")
	assert_true(exists, "%s must exist" % path)
	return (load(path) as PackedScene).instantiate() as Control if exists else null


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
	_cancel_transition_overlays()


func _cancel_transition_overlays() -> void:
	for child: Node in get_tree().root.get_children():
		if child is TransitionOverlay:
			child.free()


func _on_scene_change_requested(scene_path: String) -> void:
	_last_scene_path = scene_path
