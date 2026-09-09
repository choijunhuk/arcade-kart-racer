extends GutTest

## Section 2.2 through real SceneTree replacements; GUT remains a separate root.
const MAIN: String = "res://scenes/main.tscn"
const MENU_PATHS: Array[String] = [
	"res://ui/menus/mode_select.tscn", "res://ui/menus/driver_select.tscn",
	"res://ui/menus/kart_select.tscn", "res://ui/menus/track_select.tscn",
	"res://ui/menus/difficulty_select.tscn", "res://race/race.tscn",
]
const RUNS: int = 3
const LAPS: int = 3
const KARTS: int = 8
const TIME_SCALE: float = 4.0
const MAX_RACE_SECONDS: float = 600.0
const MAX_TRANSITION_FRAMES: int = 480
const SETTLE_FRAMES: int = 240
const NODE_GROWTH_LIMIT: int = 50
const MEMORY_GROWTH_LIMIT: int = 8 * 1024 * 1024
const SAVE_PATH: String = "user://phase11_flow_save.json"

var _original_scene: Node
var _original_save_path: String
var _original_scale: float
var _original_physics_hz: int
var _item_uses: int = 0
var _drifts: int = 0
var _race_states: Array[int] = []


func before_each() -> void:
	_original_scene = get_tree().current_scene
	_original_save_path = SaveManager.save_path
	_original_scale = Engine.time_scale
	_original_physics_hz = Engine.physics_ticks_per_second
	SaveManager.save_path = SAVE_PATH
	GameState.reset_session()
	EventBus.item_used.connect(_on_item_used)
	EventBus.drift_started.connect(_on_drift_started)
	EventBus.race_state_changed.connect(_on_race_state_changed)


func after_each() -> void:
	get_tree().paused = false
	Engine.time_scale = _original_scale
	Engine.physics_ticks_per_second = _original_physics_hz
	var current: Node = get_tree().current_scene
	if is_instance_valid(current) and current != _original_scene:
		current.free()
	get_tree().current_scene = _original_scene
	for child: Node in get_tree().root.get_children():
		if child is TransitionOverlay:
			child.free()
	EventBus.item_used.disconnect(_on_item_used)
	EventBus.drift_started.disconnect(_on_drift_started)
	EventBus.race_state_changed.disconnect(_on_race_state_changed)
	SaveManager.save_path = _original_save_path
	GameState.reset_session()
	for path: String in [SAVE_PATH, SAVE_PATH + ".bak"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func test_vertical_slice_flow_three_consecutive_runs() -> void:
	var boot: Node = (load(MAIN) as PackedScene).instantiate()
	get_tree().root.add_child(boot)
	get_tree().current_scene = boot
	await wait_process_frames(SETTLE_FRAMES)
	var baseline_nodes: int = -1
	var baseline_memory: int = -1
	var baseline_orphans: int = -1
	for run_index: int in range(RUNS):
		_set_simulation_scale(1.0)
		_item_uses = 0
		_drifts = 0
		_race_states.clear()
		for path: String in MENU_PATHS:
			# Six sorted kart cards: medium is row 2/column 2; difficulty: easy, hard, normal.
			if path.ends_with("track_select.tscn"):
				await _press_action(&"ui_right")
				await _press_action(&"ui_down")
			elif path.ends_with("race.tscn"):
				await _press_action(&"ui_down")
				await _press_action(&"ui_down")
			await _press_action(&"ui_accept")
			if not await _wait_for_scene(path):
				return
		var manager: RaceManager = get_tree().current_scene as RaceManager
		assert_not_null(manager)
		if manager == null:
			return
		assert_eq(GameState.pending_race_config.player_kart.id, &"medium")
		assert_eq(GameState.pending_race_config.ai_difficulty.id, &"normal")
		assert_eq(GameState.pending_race_config.laps, LAPS)
		assert_eq(manager.get_state(), RaceState.COUNTDOWN)
		assert_eq(manager.get_karts().size(), KARTS)
		assert_true(GameState.pending_race_config.items_enabled)
		assert_eq(manager.get_node("Karts").find_children("AIController", "", true, false).size(), KARTS - 1)
		_bind_player(manager)
		_set_simulation_scale(TIME_SCALE)
		if not await _finish_race(manager):
			return
		assert_gt(_item_uses, 0, "actual pickups must lead to item use")
		assert_gt(_drifts, 0, "real driving must include drift")
		assert_true(_race_states.has(RaceState.FINISHING))
		_set_simulation_scale(1.0)
		await wait_process_frames(SETTLE_FRAMES)
		# Results default focus is Restart: use its real pressed handler.
		await _press_action(&"ui_accept")
		assert_eq(manager.get_state(), RaceState.COUNTDOWN)
		assert_eq(manager.get_results().size(), 0)
		_bind_player(manager)
		_set_simulation_scale(TIME_SCALE)
		if not await _finish_race(manager):
			return
		_set_simulation_scale(1.0)
		await wait_process_frames(SETTLE_FRAMES)
		await _press_action(&"ui_right")
		await _press_action(&"ui_right")
		await _press_action(&"ui_accept")
		if not await _wait_for_scene(MAIN):
			return
		await wait_process_frames(SETTLE_FRAMES)
		var nodes: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
		var memory: int = int(Performance.get_monitor(Performance.MEMORY_STATIC))
		var orphans: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
		if baseline_nodes < 0:
			baseline_nodes = nodes
			baseline_memory = memory
			baseline_orphans = orphans
		assert_lt(nodes - baseline_nodes, NODE_GROWTH_LIMIT)
		assert_lte(orphans, baseline_orphans, "no orphan growth after a complete flow")
		assert_lt(memory - baseline_memory, MEMORY_GROWTH_LIMIT, "settled memory stays within 8 MiB of the warmed flow")
		assert_push_error_count(0)
		assert_engine_error_count(0)
		print("VERTICAL_FLOW run=%d races=2 nodes=%d orphans=%d memory_bytes=%d" % [run_index + 1, nodes, orphans, memory])


func _bind_player(manager: RaceManager) -> void:
	var player: KartController = manager.get_node("Karts/PlayerKart") as KartController
	var track: TrackRoot = manager.get_node("Track") as TrackRoot
	var provider: FlowInputProvider = FlowInputProvider.new(player, track.get_racing_line())
	provider.set_drift_on_corners(true)
	player.set_input_provider(provider)


func _finish_race(manager: RaceManager) -> bool:
	for _tick: int in range(roundi(MAX_RACE_SECONDS * float(_original_physics_hz))):
		if manager.get_state() == RaceState.RESULTS:
			break
		await get_tree().physics_frame
	assert_eq(manager.get_state(), RaceState.RESULTS, "full race must reach results within the physics budget")
	if manager.get_state() != RaceState.RESULTS:
		return false
	var entries: Array[RaceResults.Entry] = manager.get_results()
	assert_eq(entries.size(), KARTS)
	for entry: RaceResults.Entry in entries:
		assert_gt(entry.total_time_seconds, 0.0, "%s must finish" % entry.kart_name)
	var laps: LapTracker = manager.get_node("LapTracker") as LapTracker
	assert_eq(laps.get_lap(manager.get_node("Karts/PlayerKart") as KartController), LAPS)
	await wait_process_frames(2)
	return true


func _wait_for_scene(path: String) -> bool:
	for _frame: int in range(MAX_TRANSITION_FRAMES):
		var current: Node = get_tree().current_scene
		if current != null and current.scene_file_path == path and get_tree().root.get_node_or_null("SceneTransition") == null:
			await wait_process_frames(2)
			return true
		await get_tree().process_frame
	fail_test("Scene transition timed out: %s" % path)
	return false


func _press_action(action: StringName) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventAction = InputEventAction.new()
		event.action = action
		event.pressed = pressed
		Input.parse_input_event(event)
		await wait_process_frames(2)


func _on_item_used(_kart: Node, _id: StringName) -> void:
	_item_uses += 1


func _on_drift_started(_kart: Node, _direction: int) -> void:
	_drifts += 1


func _on_race_state_changed(_old: int, state: int) -> void:
	_race_states.append(state)


func _set_simulation_scale(scale: float) -> void:
	Engine.physics_ticks_per_second = roundi(float(_original_physics_hz) * scale)
	Engine.time_scale = scale
