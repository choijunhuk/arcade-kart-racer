extends GutTest

const RESULTS_SCENE: PackedScene = preload("res://ui/results/results_screen.tscn")
const RACE_SCENE: PackedScene = preload("res://race/race.tscn")
const DRIVER: DriverData = preload("res://data/drivers/aurora_vale.tres")
const KART: KartData = preload("res://data/karts/medium.tres")
const TRACK: TrackData = preload("res://data/tracks/track_01.tres")
const DIFFICULTY: AIDifficultyProfile = preload("res://data/ai/normal.tres")

var _last_scene_path: String = ""


func before_each() -> void:
	_last_scene_path = ""
	if not GameState.scene_change_requested.is_connected(_on_scene_requested):
		GameState.scene_change_requested.connect(_on_scene_requested)


func after_each() -> void:
	get_tree().paused = false
	if GameState.scene_change_requested.is_connected(_on_scene_requested):
		GameState.scene_change_requested.disconnect(_on_scene_requested)
	for child: Node in get_tree().root.get_children():
		if child is TransitionOverlay:
			child.free()


func test_results_table_sorts_rows_and_shows_all_columns_and_record_badge() -> void:
	var screen: ResultsScreen = RESULTS_SCENE.instantiate() as ResultsScreen
	add_child_autofree(screen)
	var fields_exist: bool = _entry_fields_exist()
	assert_true(fields_exist)
	if not fields_exist:
		return
	var second: RaceResults.Entry = _entry(2, "Echo Meridian", "Granite Roar", 65.2, 31.4, false)
	var first: RaceResults.Entry = _entry(1, "Aurora Vale", "Apex Pulse", 61.0, 29.8, true)
	var manager: RaceManager = RaceManager.new()
	autofree(manager)
	screen.show_results([second, first], manager)
	await wait_process_frames(1)
	var rows: VBoxContainer = screen.get_node("Panel/VBox/Rows") as VBoxContainer
	assert_eq(rows.get_child_count(), 2)
	var first_row: HBoxContainer = rows.get_child(0) as HBoxContainer
	assert_eq((first_row.get_node("Position") as Label).text, "1")
	assert_eq((first_row.get_node("Driver") as Label).text, "Aurora Vale")
	assert_eq((first_row.get_node("Kart") as Label).text, "Apex Pulse")
	assert_true((screen.get_node("Panel/VBox/NewRecordBadge") as Label).visible)
	assert_not_null(screen.get_node_or_null("Panel/VBox/Actions/TrackSelectButton"))
	assert_eq(get_viewport().gui_get_focus_owner(), screen.get_node("Panel/VBox/Actions/RestartButton"))


func test_track_select_action_requests_the_track_menu() -> void:
	var config: RaceConfig = RaceConfigBuilder.build(DRIVER, KART, TRACK, DIFFICULTY, 1, 1)
	config.items_enabled = false
	var manager: RaceManager = RACE_SCENE.instantiate() as RaceManager
	manager.configure(config)
	add_child_autofree(manager)
	await wait_physics_frames(1)
	var screen: ResultsScreen = manager.get_node("ResultsScreen") as ResultsScreen
	screen.show_results([], manager)
	var track_button: Button = screen.get_node_or_null("Panel/VBox/Actions/TrackSelectButton") as Button
	assert_not_null(track_button)
	if track_button == null:
		return
	track_button.pressed.emit()

	assert_eq(_last_scene_path, "res://ui/menus/track_select.tscn")


func test_results_restart_button_returns_the_live_manager_to_countdown() -> void:
	var config: RaceConfig = RaceConfigBuilder.build(DRIVER, KART, TRACK, DIFFICULTY, 1, 1)
	config.items_enabled = false
	var manager: RaceManager = RACE_SCENE.instantiate() as RaceManager
	manager.configure(config)
	add_child_autofree(manager)
	await wait_physics_frames(1)
	manager.call("_force_state", RaceState.RESULTS)
	var screen: ResultsScreen = manager.get_node("ResultsScreen") as ResultsScreen
	screen.show_results([], manager)
	(screen.get_node("Panel/VBox/Actions/RestartButton") as Button).pressed.emit()
	await wait_physics_frames(1)

	assert_eq(manager.get_state(), RaceState.COUNTDOWN)


func _entry(
	rank: int,
	driver_name: String,
	kart_name: String,
	total_time: float,
	best_lap: float,
	new_record: bool,
) -> RaceResults.Entry:
	var entry: RaceResults.Entry = RaceResults.Entry.new()
	entry.rank = rank
	entry.set(&"driver_name", driver_name)
	entry.set(&"kart_display_name", kart_name)
	entry.total_time_seconds = total_time
	entry.best_lap_seconds = best_lap
	entry.set(&"is_new_record", new_record)
	return entry


func _entry_fields_exist() -> bool:
	var entry: RaceResults.Entry = RaceResults.Entry.new()
	var names: Array[StringName] = []
	for property: Dictionary in entry.get_property_list():
		names.append(StringName(str(property.get("name", ""))))
	return names.has(&"driver_name") and names.has(&"kart_display_name") and names.has(&"is_new_record")


func _on_scene_requested(scene_path: String) -> void:
	_last_scene_path = scene_path
