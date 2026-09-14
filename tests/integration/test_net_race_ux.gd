extends GutTest

## Phase 18f online UX (spec items 2-3):
## - the networked pause overlay never pauses the tree or enters
##   RaceManager's PAUSED state — the server-authoritative race keeps
##   running — and LEAVE RACE still closes the session;
## - RESULTS offers a way back to the lobby that keeps the session alive,
##   instead of every action closing it.

const RACE_SCENE: PackedScene = preload("res://race/race.tscn")
const RESULTS_SCENE: PackedScene = preload("res://ui/results/results_screen.tscn")

var _last_scene_path: String = ""


func before_each() -> void:
	_last_scene_path = ""
	if not GameState.scene_change_requested.is_connected(_on_scene_requested):
		GameState.scene_change_requested.connect(_on_scene_requested)


func after_each() -> void:
	get_tree().paused = false
	GameState.net_session = null
	GameState.is_networked = false
	if GameState.scene_change_requested.is_connected(_on_scene_requested):
		GameState.scene_change_requested.disconnect(_on_scene_requested)
	for child: Node in get_tree().root.get_children():
		if child is TransitionOverlay:
			child.free()


func _on_scene_requested(scene_path: String) -> void:
	_last_scene_path = scene_path


## Builds a real, single-human networked RaceManager (so the actual
## PauseMenu/ResultsScreen children and `get_tree()` are available, mirroring
## `test_delayed_load_ack_and_clock_reach_countdown_then_racing` in
## tests/integration/test_net_lobby.gd) without opening a real ENet socket —
## `NetSessionLobby.restart_to_lobby()`/`back_to_menu()` only need a non-null
## `session.peer`, never an actual connection.
func _hosted_manager() -> RaceManager:
	var session: NetSession = NetSession.new()
	add_child_autofree(session)
	session.peer = ENetMultiplayerPeer.new()
	session.players = [{"peer": 1, "driver": NetContentCatalog.default_driver_id(), "kart": NetContentCatalog.default_kart_id(), "ready": true}]
	GameState.net_session = session
	GameState.is_networked = true
	var slot: PlayerSlot = PlayerSlot.new()
	slot.grid_slot = 0
	slot.device_id = -1
	slot.driver_id = &"aurora_vale"
	slot.kart_id = &"basalt_crown"
	var config: RaceConfig = RaceConfigBuilder.build_local([slot], LocalLobby.DEFAULT_TRACK, LocalLobby.DEFAULT_DIFFICULTY, 4)
	config.laps = 1
	var manager: RaceManager = RACE_SCENE.instantiate() as RaceManager
	manager.configure(config)
	add_child_autofree(manager)
	return manager


func test_networked_pause_toggles_overlay_without_pausing_tree_or_race_state() -> void:
	var manager: RaceManager = _hosted_manager()
	await wait_process_frames(2)
	var pause_menu: PauseMenu = manager.get_node("PauseMenu") as PauseMenu
	var state_before: int = manager.get_state()
	pause_menu._toggle_network_pause(PlayerSlot.KEYBOARD_DEVICE_ID)
	assert_true(bool(pause_menu.get("_network_paused")))
	assert_true(pause_menu.visible)
	assert_false(get_tree().paused, "networked pause must not pause the tree")
	assert_eq(manager.get_state(), state_before, "networked pause must not touch RaceManager's state machine")
	assert_eq((pause_menu.get_node("Panel/VBox/ContinueButton") as Button).text, "RESUME")
	assert_eq((pause_menu.get_node("Panel/VBox/MenuButton") as Button).text, "LEAVE RACE")
	assert_false((pause_menu.get_node("Panel/VBox/RestartButton") as Button).visible)
	assert_false((pause_menu.get_node("Panel/VBox/SettingsButton") as Button).visible)
	pause_menu._toggle_network_pause(PlayerSlot.KEYBOARD_DEVICE_ID)
	assert_false(bool(pause_menu.get("_network_paused")))
	assert_false(pause_menu.visible)


## Review finding 4: `_unhandled_input` must gate opening the networked
## overlay to COUNTDOWN/RACING (same states the offline path's
## `RaceManager.pause_race()` guard allows), so it can no longer stack over
## RESULTS (or any other state) — only over the actual `_toggle_network_pause`
## call tested above, which the production code still reaches unconditionally
## once the gate passes.
func test_networked_pause_does_not_open_outside_countdown_or_racing() -> void:
	var manager: RaceManager = _hosted_manager()
	await wait_process_frames(2)
	var pause_menu: PauseMenu = manager.get_node("PauseMenu") as PauseMenu
	var pause_event: InputEventAction = InputEventAction.new()
	pause_event.device = PlayerSlot.KEYBOARD_DEVICE_ID
	pause_event.action = &"pause"
	pause_event.pressed = true
	manager._force_state(RaceState.RESULTS)
	pause_menu._unhandled_input(pause_event)
	assert_false(bool(pause_menu.get("_network_paused")), "must not open over RESULTS")
	assert_false(pause_menu.visible)
	manager._force_state(RaceState.COUNTDOWN)
	pause_menu._unhandled_input(pause_event)
	assert_true(bool(pause_menu.get("_network_paused")), "must still open during COUNTDOWN")
	assert_true(pause_menu.visible)


func test_leave_race_closes_the_session_and_requests_the_main_menu() -> void:
	var manager: RaceManager = _hosted_manager()
	await wait_process_frames(2)
	var pause_menu: PauseMenu = manager.get_node("PauseMenu") as PauseMenu
	pause_menu._toggle_network_pause(PlayerSlot.KEYBOARD_DEVICE_ID)
	var session_ref: WeakRef = weakref(GameState.net_session)
	pause_menu._on_menu_pressed() # "LEAVE RACE"
	assert_null(GameState.net_session)
	assert_false(get_tree().paused)
	assert_eq(_last_scene_path, "res://scenes/main.tscn")
	# Mirrors production: the real scene change frees the whole race scene
	# (RaceManager + its NetRace child) together with the session closing.
	# Free it here too, before another physics frame lets NetRace touch a
	# session that has already been `queue_free()`'d.
	manager.free()
	await wait_process_frames(1)
	assert_null(session_ref.get_ref(), "LEAVE RACE must close/free the session")


## Review finding 6: a listen host with other players still connected must
## not end everyone's session from a single keypress that reads as "only I
## leave". The button reads "END SESSION" and the first press only asks for
## confirmation; the session must survive until a second press.
func test_end_session_on_a_multiplayer_host_requires_confirmation() -> void:
	var manager: RaceManager = _hosted_manager()
	await wait_process_frames(2)
	var session: NetSession = GameState.net_session
	session.players.append({"peer": 2, "driver": NetContentCatalog.default_driver_id(), "kart": NetContentCatalog.default_kart_id(), "ready": true})
	var pause_menu: PauseMenu = manager.get_node("PauseMenu") as PauseMenu
	var menu_button: Button = pause_menu.get_node("Panel/VBox/MenuButton") as Button
	pause_menu._toggle_network_pause(PlayerSlot.KEYBOARD_DEVICE_ID)
	assert_eq(menu_button.text, "END SESSION")
	pause_menu._on_menu_pressed() # First press: confirmation only.
	assert_not_null(GameState.net_session, "the first press must not end the session")
	assert_ne(menu_button.text, "END SESSION", "the button must show a confirmation prompt")
	pause_menu._on_menu_pressed() # Second press: actually ends it.
	assert_null(GameState.net_session, "the second press must end the session")
	manager.free()
	await wait_process_frames(1)


func test_results_back_to_lobby_keeps_the_session_alive_and_reopens_it() -> void:
	var session: NetSession = NetSession.new()
	add_child_autofree(session)
	session.peer = ENetMultiplayerPeer.new()
	GameState.net_session = session
	session.started = true
	var manager: RaceManager = RaceManager.new()
	autofree(manager)
	var screen: ResultsScreen = RESULTS_SCENE.instantiate() as ResultsScreen
	add_child_autofree(screen)
	screen.show_results([], manager)
	assert_true((screen.get_node("Panel/VBox/Actions/BackToLobbyButton") as Button).visible)
	screen._on_back_to_lobby_pressed()
	assert_eq(_last_scene_path, "res://ui/menus/online_lobby.tscn")
	assert_same(GameState.net_session, session, "the session must stay alive, not be closed")
	assert_false(session.started, "restart_to_lobby must reopen the lobby for another race")


func test_results_hides_back_to_lobby_for_a_local_offline_race() -> void:
	var manager: RaceManager = RaceManager.new()
	autofree(manager)
	var screen: ResultsScreen = RESULTS_SCENE.instantiate() as ResultsScreen
	add_child_autofree(screen)
	screen.show_results([], manager)
	assert_false((screen.get_node("Panel/VBox/Actions/BackToLobbyButton") as Button).visible)
