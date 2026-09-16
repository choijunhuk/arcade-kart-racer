extends GutTest

## Phase 18e-3: pickers disable locked content with a hint, skip it in the
## focus chain, the bypass switches open everything, the results screen
## announces new unlocks, and non-picker config paths stay untouched.

const SAVE_PATH: String = "user://phase18e_unlocks_save.json"
const TEST_SETTINGS_PATH: String = "user://phase18e_unlocks_settings.cfg"
const KART_SELECT_PATH: String = "res://ui/menus/kart_select.tscn"
const DRIVER_SELECT_PATH: String = "res://ui/menus/driver_select.tscn"
const TRACK_SELECT_PATH: String = "res://ui/menus/track_select.tscn"
const DIFFICULTY_SELECT_PATH: String = "res://ui/menus/difficulty_select.tscn"
const LOCAL_LOBBY_PATH: String = "res://ui/menus/local_lobby.tscn"
const RESULTS_SCENE: PackedScene = preload("res://ui/results/results_screen.tscn")
const TRACK_02: String = "track_02_lumen_underpass"

var _save_path: String
var _settings_path: String


func before_each() -> void:
	_save_path = SaveManager.save_path
	SaveManager.save_path = SAVE_PATH
	_settings_path = SettingsManager.settings_path
	SettingsManager.settings_path = TEST_SETTINGS_PATH
	SettingsManager.load_settings()
	GameState.reset_session()
	GameState.automation_mode = false
	_remove_files()


func after_each() -> void:
	SaveManager.save_path = _save_path
	SettingsManager.settings_path = _settings_path
	SettingsManager.load_settings()
	GameState.reset_session()
	GameState.automation_mode = false
	_remove_files()
	for child: Node in get_tree().root.get_children():
		if child is TransitionOverlay:
			child.free()


func test_kart_cards_lock_ruled_karts_and_focus_steps_over_them() -> void:
	var menu: KartSelectMenu = (load(KART_SELECT_PATH) as PackedScene).instantiate() as KartSelectMenu
	add_child_autofree(menu)
	await wait_process_frames(2)
	var grid: GridContainer = menu.get_node("Panel/VBox/Scroll/Grid") as GridContainer
	assert_eq(grid.get_child_count(), 6, "locked cards stay visible")
	var basalt: Button = grid.get_child(0) as Button
	var zephyr: Button = grid.get_child(5) as Button
	assert_true(basalt.disabled)
	assert_true(zephyr.disabled)
	assert_eq(basalt.focus_mode, Control.FOCUS_NONE)
	assert_eq((basalt.get_node("Content/Name") as Label).text, "Basalt Crown  LOCKED")
	assert_eq(basalt.tooltip_text, "Finish top 3 in the Horizon Cup")
	assert_eq(zephyr.tooltip_text, "Win the Horizon Cup")
	for index: int in range(1, 5):
		assert_false((grid.get_child(index) as Button).disabled, "kart %d stays open" % index)
	assert_eq(get_viewport().gui_get_focus_owner(), grid.get_child(1), "initial focus skips the locked first card")
	assert_same((grid.get_child(1) as Control).find_valid_focus_neighbor(SIDE_LEFT), grid.get_child(2), "left from card 1 steps over locked card 0")
	assert_same((grid.get_child(4) as Control).find_valid_focus_neighbor(SIDE_RIGHT), grid.get_child(3), "right from card 4 steps over locked card 5")


func test_driver_cards_lock_nyx_and_echo() -> void:
	var menu: DriverSelectMenu = (load(DRIVER_SELECT_PATH) as PackedScene).instantiate() as DriverSelectMenu
	add_child_autofree(menu)
	await wait_process_frames(2)
	var grid: GridContainer = menu.get_node("Panel/VBox/Scroll/Grid") as GridContainer
	assert_eq(grid.get_child_count(), 8)
	var locked: Array[int] = []
	for index: int in range(grid.get_child_count()):
		if (grid.get_child(index) as Button).disabled:
			locked.append(index)
	assert_eq(locked, [3, 6], "echo_meridian and nyx_calder are the ruled drivers")
	assert_eq((grid.get_child(6).get_node("Content/Name") as Label).text, "Nyx Calder  LOCKED")
	assert_eq((grid.get_child(3) as Button).tooltip_text, "Set a best lap on every track")
	assert_eq(get_viewport().gui_get_focus_owner(), grid.get_child(0))


func test_track_list_locks_later_tracks_until_earned() -> void:
	var menu: TrackSelectMenu = (load(TRACK_SELECT_PATH) as PackedScene).instantiate() as TrackSelectMenu
	add_child_autofree(menu)
	await wait_process_frames(2)
	var list: VBoxContainer = menu.get_node("Panel/VBox/TrackList") as VBoxContainer
	assert_false((list.get_child(0) as Button).disabled)
	assert_false((list.get_child(1) as Button).disabled)
	var glacier: Button = list.get_child(2) as Button
	var ochre: Button = list.get_child(3) as Button
	assert_true(glacier.disabled)
	assert_true(ochre.disabled)
	assert_eq(glacier.text, "Glacier Crown  •  LOCKED\nFinish top 3 on Lumen Underpass")
	assert_eq(ochre.tooltip_text, "Finish top 3 on Glacier Crown")
	assert_same((list.get_child(1) as Control).find_valid_focus_neighbor(SIDE_BOTTOM), menu.get_node("Panel/VBox/BackButton"), "down from track 2 skips both locked tracks")
	menu.free()

	assert_eq(SaveManager.record_race_result(StringName(TRACK_02), 60_000, 2), OK)
	var earned: TrackSelectMenu = (load(TRACK_SELECT_PATH) as PackedScene).instantiate() as TrackSelectMenu
	add_child_autofree(earned)
	await wait_process_frames(2)
	var earned_list: VBoxContainer = earned.get_node("Panel/VBox/TrackList") as VBoxContainer
	assert_false((earned_list.get_child(2) as Button).disabled, "top 3 on track_02 opens track_03")
	assert_true((earned_list.get_child(3) as Button).disabled, "track_04 still needs track_03")


func test_difficulty_menu_locks_turbo_and_falls_back_to_standard() -> void:
	SettingsManager.update_setting(&"gameplay", &"speed_class", RaceConfig.SpeedClass.TURBO)
	GameState.set_selection(&"aurora_vale", &"medium", &"track_01_ridgeline_circuit")
	var menu: DifficultySelectMenu = (load(DIFFICULTY_SELECT_PATH) as PackedScene).instantiate() as DifficultySelectMenu
	add_child_autofree(menu)
	await wait_process_frames(1)
	var option: OptionButton = menu.get_node("Panel/VBox/SpeedClassOption") as OptionButton
	assert_true(option.is_item_disabled(2))
	assert_eq(option.get_item_text(2), "TURBO  LOCKED")
	assert_eq(option.tooltip_text, "Finish top 3 in a STANDARD Horizon Cup")
	assert_eq(option.selected, 1, "a remembered TURBO choice falls back to STANDARD while locked")

	option.select(2)
	menu._start_race(load("res://data/ai/normal.tres") as AIDifficultyProfile)
	assert_eq(GameState.pending_race_config.speed_class, RaceConfig.SpeedClass.STANDARD, "a forced locked selection cannot start a TURBO race")


func test_automation_mode_and_unlock_all_open_every_picker() -> void:
	GameState.automation_mode = true
	var menu: KartSelectMenu = (load(KART_SELECT_PATH) as PackedScene).instantiate() as KartSelectMenu
	add_child_autofree(menu)
	await wait_process_frames(2)
	var grid: GridContainer = menu.get_node("Panel/VBox/Scroll/Grid") as GridContainer
	for index: int in range(grid.get_child_count()):
		assert_false((grid.get_child(index) as Button).disabled, "automation opens kart %d" % index)
	assert_eq(get_viewport().gui_get_focus_owner(), grid.get_child(0))
	menu.free()
	GameState.automation_mode = false

	SettingsManager.set_setting(&"gameplay", &"unlock_all", true)
	GameState.set_selection(&"aurora_vale", &"medium", &"track_01_ridgeline_circuit")
	var difficulty: DifficultySelectMenu = (load(DIFFICULTY_SELECT_PATH) as PackedScene).instantiate() as DifficultySelectMenu
	add_child_autofree(difficulty)
	await wait_process_frames(1)
	var option: OptionButton = difficulty.get_node("Panel/VBox/SpeedClassOption") as OptionButton
	assert_false(option.is_item_disabled(2))
	assert_eq(option.get_item_text(2), "TURBO")
	var tracks: TrackSelectMenu = (load(TRACK_SELECT_PATH) as PackedScene).instantiate() as TrackSelectMenu
	add_child_autofree(tracks)
	await wait_process_frames(1)
	var list: VBoxContainer = tracks.get_node("Panel/VBox/TrackList") as VBoxContainer
	assert_false((list.get_child(3) as Button).disabled, "unlock_all opens track_04")


func test_local_lobby_only_cycles_unlocked_content() -> void:
	var lobby: LocalLobby = (load(LOCAL_LOBBY_PATH) as PackedScene).instantiate() as LocalLobby
	add_child_autofree(lobby)
	assert_eq(lobby._karts.size(), 4)
	assert_eq(lobby._drivers.size(), 6)
	for kart: KartData in lobby._karts:
		assert_false(kart.id in [&"basalt_crown", &"zephyr_needle"])
	assert_true(lobby.join_device(-1))
	var panel: PanelContainer = lobby.get_node("Panel/VBox/Players/Player1Panel") as PanelContainer
	var rows: VBoxContainer = panel.get_child(0) as VBoxContainer
	assert_true((rows.get_child(3) as Label).text.ends_with("KART    Copper Arc"), "the default kart is the first unlocked one")


func test_online_widget_disables_locked_options_and_moves_the_selection() -> void:
	var option: OptionButton = OptionButton.new()
	add_child_autofree(option)
	var karts: Array[Resource] = ResourceScanner.scan_tres("res://data/karts")
	for kart: Resource in karts:
		option.add_item(String(kart.get("display_name")))
	OnlineLobbyWidgets.lock_options(option, karts, "kart", SaveManager.load_data())
	assert_true(option.is_item_disabled(0))
	assert_true(option.is_item_disabled(5))
	assert_eq(option.get_item_text(0), "Basalt Crown  LOCKED")
	assert_eq(option.selected, 1, "the selection moves off the locked default")
	assert_eq(OnlineLobbyWidgets.display_name(karts, "zephyr_needle"), "Zephyr Needle", "remote picks still resolve")


func test_results_screen_announces_new_unlocks() -> void:
	var screen: ResultsScreen = RESULTS_SCENE.instantiate() as ResultsScreen
	add_child_autofree(screen)
	var manager: RaceManager = RaceManager.new()
	autofree(manager)
	var results: RaceResults = RaceResults.new()
	results.name = "RaceResults"
	manager.add_child(results)
	results.newly_unlocked = ["kart:zephyr_needle", "track:track_03_glacier_crown"]
	screen.show_results([], manager)
	var label: Label = screen.get_node("Panel/VBox/UnlockedLabel") as Label
	assert_true(label.visible)
	assert_eq(label.text, "UNLOCKED: Zephyr Needle, Glacier Crown")

	results.newly_unlocked = []
	screen.show_results([], manager)
	assert_false(label.visible, "nothing new earned hides the line")


func test_non_picker_config_paths_ignore_locks() -> void:
	var track: TrackData = load("res://data/tracks/track_04.tres") as TrackData
	var config: RaceConfig = RaceConfigBuilder.build(
		load("res://data/drivers/nyx_calder.tres") as DriverData,
		load("res://data/karts/zephyr_needle.tres") as KartData,
		track, load("res://data/ai/normal.tres") as AIDifficultyProfile,
	)
	assert_eq(config.player_driver.id, &"nyx_calder")
	assert_eq(config.player_kart.id, &"zephyr_needle")
	assert_eq(config.track.id, &"track_04_ochre_rift")
	var tracks: Array[TrackData] = []
	for resource: Resource in ResourceScanner.scan_tres("res://data/tracks"):
		tracks.append(resource as TrackData)
	var gp: GrandPrix = GrandPrix.new()
	gp.setup(config, tracks)
	var ids: Array[StringName] = []
	for _round: int in range(tracks.size()):
		ids.append(gp.current_config().track.id)
		gp.round_index += 1
	assert_eq(ids, [&"track_01_ridgeline_circuit", StringName(TRACK_02), &"track_03_glacier_crown", &"track_04_ochre_rift"], "GP rounds run locked tracks")


func _remove_files() -> void:
	for path: String in [SAVE_PATH, SAVE_PATH + ".bak", TEST_SETTINGS_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
