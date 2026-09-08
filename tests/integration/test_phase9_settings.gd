extends GutTest

const SETTINGS_PATH: String = "res://ui/menus/settings_menu.tscn"
const RACE_SCENE: PackedScene = preload("res://race/race.tscn")
const TRACK: TrackData = preload("res://data/tracks/track_01.tres")
const KART: KartData = preload("res://data/karts/medium.tres")
const DRIVER: DriverData = preload("res://data/drivers/aurora_vale.tres")
const DIFFICULTY: AIDifficultyProfile = preload("res://data/ai/normal.tres")


func after_each() -> void:
	get_tree().paused = false


func test_settings_scene_exposes_every_section_and_all_remap_rows() -> void:
	var exists: bool = ResourceLoader.exists(SETTINGS_PATH, "PackedScene")
	assert_true(exists)
	if not exists:
		return
	var settings: Control = (load(SETTINGS_PATH) as PackedScene).instantiate() as Control
	add_child_autofree(settings)
	await wait_process_frames(1)
	var section_picker: OptionButton = settings.get_node("Panel/VBox/SectionPicker") as OptionButton
	var tabs: TabContainer = settings.get_node("Panel/VBox/Tabs") as TabContainer
	assert_eq(section_picker.item_count, 5)
	assert_eq(tabs.get_tab_count(), 5)
	assert_not_null(settings.get_node_or_null("Panel/VBox/Tabs/Audio/MasterSlider"))
	assert_not_null(settings.get_node_or_null("Panel/VBox/Tabs/Video/ResolutionOption"))
	assert_not_null(settings.get_node_or_null("Panel/VBox/Tabs/Accessibility/SpeedLinesToggle"))
	assert_not_null(settings.get_node_or_null("Panel/VBox/Tabs/Gameplay/SpeedometerToggle"))
	var remap_rows: VBoxContainer = settings.get_node("Panel/VBox/Tabs/Controls/Scroll/Rows/RemapRows") as VBoxContainer
	assert_eq(remap_rows.get_child_count(), 14)
	assert_eq(get_viewport().gui_get_focus_owner(), section_picker)
	var master_slider: HSlider = settings.get_node("Panel/VBox/Tabs/Audio/MasterSlider") as HSlider
	assert_eq(section_picker.focus_neighbor_bottom, section_picker.get_path_to(master_slider))


func test_pause_settings_back_keeps_the_race_tree_paused() -> void:
	var config: RaceConfig = RaceConfigBuilder.build(DRIVER, KART, TRACK, DIFFICULTY, 1, 1)
	config.items_enabled = false
	var manager: RaceManager = RACE_SCENE.instantiate() as RaceManager
	manager.configure(config)
	add_child_autofree(manager)
	await wait_physics_frames(1)
	manager.pause_race()
	var pause_menu: PauseMenu = manager.get_node("PauseMenu") as PauseMenu
	var settings_button: Button = pause_menu.get_node_or_null("Panel/VBox/SettingsButton") as Button
	assert_not_null(settings_button)
	if settings_button == null:
		return

	settings_button.pressed.emit()
	await wait_process_frames(1)
	var settings_menu: Control = pause_menu.get_node("SettingsMenu") as Control
	assert_true(get_tree().paused)
	assert_true(settings_menu.visible)
	(settings_menu.get_node("Panel/VBox/BackButton") as Button).pressed.emit()
	await wait_process_frames(1)

	assert_true(get_tree().paused)
	assert_false(settings_menu.visible)
	assert_true(pause_menu.get_node("Panel").visible)


func test_loading_race_scene_preserves_race_mode() -> void:
	var config: RaceConfig = RaceConfigBuilder.build(DRIVER, KART, TRACK, DIFFICULTY, 1, 1)
	config.items_enabled = false
	GameState.current_mode = GameState.Mode.RACE
	var manager: RaceManager = RACE_SCENE.instantiate() as RaceManager
	manager.configure(config)
	add_child_autofree(manager)

	await wait_physics_frames(1)

	assert_eq(GameState.current_mode, GameState.Mode.RACE)
