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
