extends GutTest

const HUD_PATH: String = "res://ui/hud/hud.tscn"
const PAUSE_PATH: String = "res://ui/menus/pause_menu.tscn"
const RESULTS_PATH: String = "res://ui/results/results_screen.tscn"
const MAIN_PATH: String = "res://scenes/main.tscn"
const KART_SCENE: PackedScene = preload("res://kart/kart.tscn")


func after_each() -> void:
	get_tree().paused = false


func test_hud_reflects_countdown_wrong_way_final_lap_and_finish_events() -> void:
	var hud: Node = _instantiate_required(HUD_PATH)
	if hud == null:
		return
	add_child_autofree(hud)
	var kart: KartController = KART_SCENE.instantiate() as KartController
	add_child_autofree(kart)
	var laps: LapTracker = LapTracker.new()
	var positions: PositionTracker = PositionTracker.new()
	add_child_autofree(laps)
	add_child_autofree(positions)
	hud.call("bind", kart, laps, positions, 4, 2)

	EventBus.countdown_tick.emit(0)
	assert_eq((hud.get_node("CountdownLabel") as Label).text, "GO")
	EventBus.wrong_way.emit(kart, true)
	assert_true((hud.get_node("WrongWayLabel") as Label).visible)
	EventBus.lap_completed.emit(kart, 1, 12.0)
	assert_eq((hud.get_node("MessageLabel") as Label).text, "FINAL LAP")
	EventBus.kart_finished.emit(kart, 24.0)
	assert_eq((hud.get_node("MessageLabel") as Label).text, "FINISH")


func test_pause_menu_focuses_continue_and_exposes_three_actions() -> void:
	var menu: Node = _instantiate_required(PAUSE_PATH)
	if menu == null:
		return
	add_child_autofree(menu)
	var manager: RaceManager = (load("res://race/race.tscn") as PackedScene).instantiate() as RaceManager
	autofree(manager)
	menu.call("show_menu", manager)
	await wait_process_frames(1)
	var continue_button: Button = menu.get_node("Panel/VBox/ContinueButton") as Button
	assert_true(menu.visible)
	assert_eq(get_viewport().gui_get_focus_owner(), continue_button)
	assert_not_null(menu.get_node_or_null("Panel/VBox/RestartButton"))
	assert_not_null(menu.get_node_or_null("Panel/VBox/MenuButton"))


func test_results_screen_builds_rows_and_focuses_restart() -> void:
	var screen: Node = _instantiate_required(RESULTS_PATH)
	if screen == null:
		return
	add_child_autofree(screen)
	var manager: RaceManager = (load("res://race/race.tscn") as PackedScene).instantiate() as RaceManager
	autofree(manager)
	var first: RaceResults.Entry = RaceResults.Entry.new()
	first.kart_name = "PlayerKart"
	first.rank = 1
	first.total_time_seconds = 30.25
	first.best_lap_seconds = 30.25
	var second: RaceResults.Entry = RaceResults.Entry.new()
	second.kart_name = "DummyKart2"
	second.rank = 2
	second.total_time_seconds = -1.0
	var entries: Array[RaceResults.Entry] = [first, second]
	screen.call("show_results", entries, manager)
	await wait_process_frames(1)
	var rows: VBoxContainer = screen.get_node("Panel/VBox/Rows") as VBoxContainer
	var restart_button: Button = screen.get_node("Panel/VBox/Actions/RestartButton") as Button
	assert_eq(rows.get_child_count(), 2)
	assert_eq(get_viewport().gui_get_focus_owner(), restart_button)


func test_main_scene_builds_default_config_and_offers_start_button() -> void:
	var main: Node = (load(MAIN_PATH) as PackedScene).instantiate()
	autofree(main)
	assert_not_null(main.get_node_or_null("Center/StartButton"))
	assert_true(main.has_method("build_default_config"))
	if not main.has_method("build_default_config"):
		return
	var config: RaceConfig = main.call("build_default_config") as RaceConfig
	assert_eq(config.track.id, &"track_01_ridgeline_circuit")
	assert_eq(config.laps, 3)
	assert_eq(config.kart_count, 8)
	assert_eq(config.player_kart.id, &"medium")


func _instantiate_required(path: String) -> Node:
	var exists: bool = ResourceLoader.exists(path)
	assert_true(exists, "%s must exist" % path)
	return (load(path) as PackedScene).instantiate() if exists else null
