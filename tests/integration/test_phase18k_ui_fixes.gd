extends GutTest

## Phase 18k UI review fixes (.omc/phase18k_ui_tools_review_fixes_brief.md C).

const MAIN_MENU_PATH: String = "res://ui/menus/main_menu.tscn"


func after_each() -> void:
	GameState.reset_session()
	# Overlays are parented on the root (outside this test's scene) and would
	# keep tweening into later tests; free every transition state marker now.
	var root: Window = get_tree().root
	for node_name: StringName in [GameState.TRANSITION_NODE_NAME, GameState.LOAD_ERROR_NODE_NAME]:
		var node: Node = root.get_node_or_null(NodePath(String(node_name)))
		if node != null:
			root.remove_child(node)
			node.free()


## Item 13: a failed load must release the SceneTransition busy marker so the
## next change_scene() runs (OK) instead of being refused with ERR_BUSY.
func test_change_scene_is_not_busy_after_a_failed_transition() -> void:
	var root: Window = get_tree().root
	var overlay: TransitionOverlay = preload("res://ui/components/transition_overlay.tscn").instantiate() as TransitionOverlay
	overlay.name = GameState.TRANSITION_NODE_NAME
	root.add_child(overlay)
	var loading: Control = preload("res://ui/components/loading_screen.tscn").instantiate() as Control
	overlay.add_child(loading)
	assert_eq(GameState.change_scene(MAIN_MENU_PATH), ERR_BUSY, "a live transition still blocks")

	await overlay._show_failure(loading, "Expected scene load failure")
	assert_push_error("Expected scene load failure")
	assert_eq(String(overlay.name), String(GameState.LOAD_ERROR_NODE_NAME), "failure overlay releases the busy name")

	var requested: Array[String] = []
	var capture: Callable = func(path: String) -> void: requested.append(path)
	GameState.scene_change_requested.connect(capture)
	var error: Error = GameState.change_scene(MAIN_MENU_PATH)
	GameState.scene_change_requested.disconnect(capture)
	assert_eq(error, OK, "change_scene must run again after a failed load")
	assert_eq(requested, [MAIN_MENU_PATH])
	assert_null(root.get_node_or_null(NodePath(String(GameState.LOAD_ERROR_NODE_NAME))), "stale failure overlay is removed")
	assert_true(overlay.is_queued_for_deletion())
	assert_not_null(root.get_node_or_null(NodePath(String(GameState.TRANSITION_NODE_NAME))))


## Item 14: the networked pause overlay hides RESTART/SETTINGS, so ui_down
## from RESUME must land on the next *visible* button (LEAVE RACE), not on a
## hidden one that swallows focus.
func test_network_pause_focus_chain_skips_hidden_buttons() -> void:
	var menu: PauseMenu = (load("res://ui/menus/pause_menu.tscn") as PackedScene).instantiate() as PauseMenu
	add_child_autofree(menu)
	var resume: Button = menu.get_node("Panel/VBox/ContinueButton") as Button
	var leave: Button = menu.get_node("Panel/VBox/MenuButton") as Button
	var restart: Button = menu.get_node("Panel/VBox/RestartButton") as Button
	menu._configure_network_buttons(true)
	assert_false(restart.visible)
	assert_same(resume.get_node(resume.focus_neighbor_bottom), leave, "RESUME ui_down -> LEAVE RACE")
	assert_same(leave.get_node(leave.focus_neighbor_bottom), resume, "LEAVE RACE ui_down wraps to RESUME")
	assert_same(leave.get_node(leave.focus_neighbor_top), resume)
	menu._configure_network_buttons(false)
	assert_same(resume.get_node(resume.focus_neighbor_bottom), restart, "local pause restores the full chain")


## Item 14: offline results hide BACK TO LOBBY, so the left/right wrap must
## run MAIN MENU -> RESTART instead of into the hidden button.
func test_results_focus_chain_skips_hidden_back_to_lobby() -> void:
	var screen: ResultsScreen = (load("res://ui/results/results_screen.tscn") as PackedScene).instantiate() as ResultsScreen
	add_child_autofree(screen)
	var manager: RaceManager = RaceManager.new()
	autofree(manager)
	screen.show_results([], manager)
	var restart: Button = screen.get_node("Panel/VBox/Actions/RestartButton") as Button
	var main_menu: Button = screen.get_node("Panel/VBox/Actions/MenuButton") as Button
	var lobby: Button = screen.get_node("Panel/VBox/Actions/BackToLobbyButton") as Button
	assert_false(lobby.visible)
	assert_same(main_menu.get_node(main_menu.focus_neighbor_right), restart, "MAIN MENU ui_right wraps to RESTART")
	assert_same(restart.get_node(restart.focus_neighbor_left), main_menu, "RESTART ui_left wraps to MAIN MENU")


## Item 15: while a RemapRow listens, Escape cancels the capture instead of
## being written as the new binding.
func test_remap_row_escape_cancels_listening_without_rebinding() -> void:
	var row: RemapRow = (load("res://ui/menus/remap_row.tscn") as PackedScene).instantiate() as RemapRow
	add_child_autofree(row)
	row.configure(&"drift", "Drift")
	var before: Array[InputEvent] = InputMap.action_get_events(&"drift")
	var requested: Array = []
	row.remap_requested.connect(func(action: StringName, event: InputEvent) -> void: requested.append([action, event]))
	row._start_listening()
	assert_true(row.is_listening())
	var escape: InputEventKey = InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.physical_keycode = KEY_ESCAPE
	escape.pressed = true
	assert_true(escape.is_action_pressed(&"ui_cancel"), "Escape must map to ui_cancel in this project")
	row._input(escape)
	assert_false(row.is_listening(), "Escape leaves listening mode")
	assert_eq(requested.size(), 0, "no remap is requested for Escape")
	assert_eq(InputMap.action_get_events(&"drift"), before, "binding untouched")
	assert_eq((row.get_node("BindButton") as Button).text, before[0].as_text(), "label shows the current binding again")


## Item 16: `accessibility.drift_tier_icons` gates the tier label/colour; the
## meter must react to the live settings_changed signal, not only at _ready.
func test_drift_meter_honours_the_tier_icons_accessibility_setting() -> void:
	var previous: Variant = SettingsManager.get_setting(&"accessibility", &"drift_tier_icons", true)
	var meter: DriftMeter = (load("res://ui/hud/drift_meter.tscn") as PackedScene).instantiate() as DriftMeter
	add_child_autofree(meter)
	var controller: DriftController = DriftController.new()
	add_child_autofree(controller)
	controller._tier = 3
	meter.set_controller(controller)
	var label: Label = meter.get_node("Panel/TierLabel") as Label
	SettingsManager.set_setting(&"accessibility", &"drift_tier_icons", true)
	meter._process(0.0)
	assert_eq(label.text, "DRIFT T3")
	assert_eq(label.modulate, meter.tuning.drift_tier_magenta)
	SettingsManager.set_setting(&"accessibility", &"drift_tier_icons", false)
	meter._process(0.0)
	assert_eq(label.text, "DRIFT", "tier text hidden when icons are off")
	assert_eq(label.modulate, meter.tuning.drift_tier_cyan, "base colour only when icons are off")
	SettingsManager.set_setting(&"accessibility", &"drift_tier_icons", previous)


## Item 18: the HUD caches `gameplay.speedometer` and follows live changes
## through settings_changed rather than polling SettingsManager per frame.
func test_hud_speedometer_follows_setting_changes_through_the_cache() -> void:
	var previous: Variant = SettingsManager.get_setting(&"gameplay", &"speedometer", true)
	var hud: RaceHud = (load("res://ui/hud/hud.tscn") as PackedScene).instantiate() as RaceHud
	add_child_autofree(hud)
	var speedometer: Control = hud.get_node("Speedometer") as Control
	SettingsManager.set_setting(&"gameplay", &"speedometer", true)
	hud._process(0.0)
	assert_true(speedometer.visible)
	SettingsManager.set_setting(&"gameplay", &"speedometer", false)
	assert_false(bool(hud.get("_speedometer_enabled")), "cache updated by settings_changed")
	hud._process(0.0)
	assert_false(speedometer.visible)
	SettingsManager.set_setting(&"gameplay", &"speedometer", previous)


## Item 19: the online lobby wires an explicit wraparound focus chain across
## all of its runtime-built rows, so gamepad-only navigation reaches every
## control and never dead-ends.
func test_online_lobby_focus_chain_covers_every_control_and_wraps() -> void:
	var lobby: OnlineLobby = (load("res://ui/menus/online_lobby.tscn") as PackedScene).instantiate() as OnlineLobby
	add_child_autofree(lobby)
	await wait_process_frames(2)
	var host: Control = lobby.get("_host") as Control
	var join: Control = lobby.get("_join") as Control
	var ip: Control = lobby.get("_ip") as Control
	var difficulty: Control = lobby.get("_difficulty") as Control
	var back: Control = lobby.get("_back") as Control
	assert_same(host.get_node(host.focus_neighbor_bottom), join, "ui_down steps to the next control in reading order")
	assert_same(host.get_node(host.focus_neighbor_right), join, "ui_right steps within the row")
	assert_same(ip.get_node(ip.focus_neighbor_left), back, "ui_left wraps within the first row")
	assert_same(difficulty.get_node(difficulty.focus_neighbor_bottom), ip, "last control wraps back to the first")
	assert_same(ip.get_node(ip.focus_neighbor_top), difficulty, "first control wraps up to the last")
	var visited: Array[Control] = []
	var cursor: Control = ip
	while not visited.has(cursor) and visited.size() <= 32:
		assert_false(cursor.focus_neighbor_bottom.is_empty(), "%s has an explicit ui_down neighbour" % cursor.name)
		visited.append(cursor)
		cursor = cursor.get_node(cursor.focus_neighbor_bottom) as Control
	assert_same(cursor, ip, "walking ui_down returns to the start without a dead end")
	assert_eq(visited.size(), 17, "chain covers all 17 lobby controls")


## Item 13: a request refused with ERR_BUSY must not be announced either.
func test_busy_change_scene_does_not_emit_scene_change_requested() -> void:
	var root: Window = get_tree().root
	var marker: Node = Node.new()
	marker.name = GameState.TRANSITION_NODE_NAME
	root.add_child(marker)
	var requested: Array[String] = []
	var capture: Callable = func(path: String) -> void: requested.append(path)
	GameState.scene_change_requested.connect(capture)
	assert_eq(GameState.change_scene(MAIN_MENU_PATH), ERR_BUSY)
	GameState.scene_change_requested.disconnect(capture)
	assert_eq(requested.size(), 0)
