extends GutTest

func test_online_lobby_has_shared_panels_and_enabled_connection_controls() -> void:
	var lobby: OnlineLobby = (load("res://ui/menus/online_lobby.tscn") as PackedScene).instantiate() as OnlineLobby
	add_child_autofree(lobby)
	await wait_process_frames(2)
	assert_eq(lobby.get_node("Panel/VBox/Players").get_child_count(), NetTuning.MAX_PLAYERS)
	assert_false((lobby.get("_host") as Button).disabled)
	assert_false((lobby.get("_join") as Button).disabled)
	assert_true((lobby.get("_ready_button") as Button).disabled)
	assert_eq(int((lobby.get("_port") as SpinBox).value), NetTuning.PORT)

## Real-UI acceptance testing caught a join showing "Connected" the instant
## the ENet socket opened, well before the server's handshake actually
## admitted the peer — a rejection moments later would leave a UI that had
## already claimed success. The status must stay "verifying" until a roster
## row for our own peer id actually appears.
func test_join_shows_verifying_until_handshake_admits_us() -> void:
	var lobby: OnlineLobby = (load("res://ui/menus/online_lobby.tscn") as PackedScene).instantiate() as OnlineLobby
	add_child_autofree(lobby)
	await wait_process_frames(2)
	var session: NetSession = NetSession.new()
	add_child_autofree(session)
	lobby.set("_session", session)
	lobby._handle_open(OK, true)
	var status: Label = lobby.get("_status") as Label
	assert_eq(status.text, "Connecting — verifying handshake…")
	assert_true(bool(lobby.get("_awaiting_handshake")))
	# Handshake admits us: the server-broadcast roster now has our own row.
	var local_id: int = session.multiplayer.get_unique_id()
	session.players = [{"peer": local_id, "driver": "", "kart": "", "ready": false}]
	lobby._refresh()
	assert_eq(status.text, "Connected — choose driver/kart, then READY. Host starts.")
	assert_false(bool(lobby.get("_awaiting_handshake")))

## Joining a dedicated server mid-race admits the peer as a waiting spectator
## with no roster row, so local_slot() never turns >= 0 during that race;
## the server's `_admitted` RPC (net_session.gd) must clear "verifying" instead.
func test_admitted_signal_clears_verifying_for_a_mid_race_waiting_join() -> void:
	var lobby: OnlineLobby = (load("res://ui/menus/online_lobby.tscn") as PackedScene).instantiate() as OnlineLobby
	add_child_autofree(lobby)
	await wait_process_frames(2)
	var session: NetSession = NetSession.new()
	add_child_autofree(session)
	lobby.set("_session", session)
	lobby._handle_open(OK, true)
	lobby._on_admitted(true)
	var status: Label = lobby.get("_status") as Label
	assert_eq(status.text, "Admitted — waiting for the current race to finish.")
	assert_false(bool(lobby.get("_awaiting_handshake")))

func test_main_menu_exposes_online_and_disconnection_message() -> void:
	GameState.network_message = "Host disconnected."
	var menu: MainMenu = (load("res://ui/menus/main_menu.tscn") as PackedScene).instantiate() as MainMenu
	add_child_autofree(menu)
	assert_false((menu.get_node("Panel/VBox/OnlineButton") as Button).disabled)
	assert_eq((menu.get_node("Panel/VBox/NetworkMessage") as Label).text, "Host disconnected.")
	assert_eq(GameState.network_message, "")

func test_authoritative_lobby_return_clears_the_previous_client_race() -> void:
	var session: NetSession = NetSession.new()
	add_child_autofree(session)
	session.players = [{"peer": 2, "ready": true}]
	session.started = true
	session.running = true
	session.race = NetRace.new()
	add_child_autofree(session.race)
	session._roster.preparing = true
	session._roster.loaded.append(2)
	session._return_to_lobby([{"peer": 2, "ready": false}])
	assert_false(session.started)
	assert_false(session.running)
	assert_null(session.race)
	assert_false(session._roster.preparing)
	assert_true(session._roster.loaded.is_empty())
	assert_false(bool(session.players[0]["ready"]))

func test_delayed_load_ack_and_clock_reach_countdown_then_racing() -> void:
	var session: NetSession = NetSession.new()
	session.automated = true
	session.players = [{"peer": 1}, {"peer": 2}]
	session.conditions.latency_seconds = 0.1
	session.conditions.loss = 0.02
	add_child_autofree(session)
	session.set_physics_process(false)
	GameState.net_session = session
	GameState.is_networked = true
	GameState.automation_mode = true
	var slots: Array[PlayerSlot] = []
	for index: int in range(2):
		var slot: PlayerSlot = PlayerSlot.new()
		slot.grid_slot = index
		slot.device_id = index - 1
		slot.driver_id = &"aurora_vale"
		slot.kart_id = &"basalt_crown"
		slots.append(slot)
	var config: RaceConfig = RaceConfigBuilder.build_local(slots, LocalLobby.DEFAULT_TRACK, LocalLobby.DEFAULT_DIFFICULTY, 8)
	config.laps = 1
	var manager: RaceManager = (load("res://race/race.tscn") as PackedScene).instantiate() as RaceManager
	manager.configure(config)
	add_child_autofree(manager)
	var countdown: Countdown = manager.get_node("Countdown") as Countdown
	assert_eq(manager.get_state(), RaceState.COUNTDOWN)
	assert_eq(countdown.get_phase_seconds(), 0.0)
	assert_false(session.running)
	var client_wire: NetDebugConditions = NetDebugConditions.new()
	client_wire.latency_seconds = 0.1
	client_wire.loss = 0.02
	var client_clock: NetClock = NetClock.new()
	# Inject transport time; no sockets or wall-clock waits are needed at fixed FPS.
	var sent: float = NetSession.now()
	client_wire.enqueue(sent, true, func() -> void:
		session.conditions.enqueue(sent + 0.1, true, client_clock.observe.bind(sent, sent + 0.1, sent + 0.2)))
	# The production RPC derives peer 2 from the sender before marking it loaded.
	client_wire.enqueue(sent, true, session._mark_loaded.bind(2))
	client_wire.advance(sent + 0.09)
	assert_false(session.running)
	assert_false(client_clock.initialized)
	client_wire.advance(sent + 0.1)
	assert_true(session.running)
	assert_gt(countdown.get_phase_seconds(), 0.0)
	session.conditions.advance(sent + 0.19)
	assert_false(client_clock.initialized)
	session.conditions.advance(sent + 0.2)
	assert_true(client_clock.initialized)
	assert_almost_eq(client_clock.rtt_seconds, 0.2, 0.00001)
	assert_almost_eq(client_clock.offset_seconds, 0.0, 0.00001)
	await wait_physics_frames(240)
	assert_eq(manager.get_state(), RaceState.RACING)
	assert_gt(manager.network.tick, 0)
	GameState.net_session = null
	GameState.is_networked = false
	GameState.automation_mode = false
