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

## Review finding 5: `_refresh_race_options` resyncing the controls (e.g. the
## host's own rebind after BACK TO LOBBY) must not clobber the session's
## real laps/bots/track/difficulty with the controls' stale defaults.
func test_refresh_race_options_does_not_clobber_non_default_session_settings() -> void:
	var lobby: OnlineLobby = (load("res://ui/menus/online_lobby.tscn") as PackedScene).instantiate() as OnlineLobby
	add_child_autofree(lobby)
	await wait_process_frames(2)
	var session: NetSession = NetSession.new()
	add_child_autofree(session)
	session.players = [{"peer": 1, "driver": NetContentCatalog.default_driver_id(), "kart": NetContentCatalog.default_kart_id(), "ready": true}]
	session.laps = 7
	session.ai_count = 4
	session.track_id = "track_04_ochre_rift"
	session.difficulty_id = "hard"
	lobby.set("_session", session)
	lobby._refresh()
	assert_eq(session.laps, 7, "resync must not clobber the host's laps")
	assert_eq(session.ai_count, 4, "resync must not clobber the host's bot count")
	assert_eq(session.track_id, "track_04_ochre_rift", "resync must not clobber the host's track")
	assert_eq(session.difficulty_id, "hard", "resync must not clobber the host's difficulty")

## Review finding 7: after a non-host BACK TO LOBBY the client re-enters the
## lobby while the server's race is still genuinely in progress (the host
## hasn't also returned yet) — READY must not look pressable while `started`
## is true, since every `_selection` it would send is dropped server-side.
func test_ready_is_disabled_and_explained_while_the_session_is_still_started() -> void:
	var lobby: OnlineLobby = (load("res://ui/menus/online_lobby.tscn") as PackedScene).instantiate() as OnlineLobby
	add_child_autofree(lobby)
	await wait_process_frames(2)
	var session: NetSession = NetSession.new()
	add_child_autofree(session)
	session.players = [{"peer": 1, "driver": NetContentCatalog.default_driver_id(), "kart": NetContentCatalog.default_kart_id(), "ready": false}]
	session.started = true
	lobby.set("_session", session)
	lobby._refresh()
	assert_true((lobby.get("_ready_button") as Button).disabled, "READY must not be pressable while the server's race is still started")
	assert_eq((lobby.get("_status") as Label).text, "Waiting for the host to reopen the lobby.")
	session.started = false
	lobby._refresh()
	assert_false((lobby.get("_ready_button") as Button).disabled, "READY must re-enable once the session actually returns to the lobby")

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

## Spec item 1: the host's laps/bots/track/difficulty choice must reach every
## client's lobby fields (extends the existing `_lobby` broadcast payload)
## and, from there, the race config each peer builds locally.
func test_host_set_race_options_updates_the_session_and_rebroadcasts_the_lobby() -> void:
	var session: NetSession = NetSession.new()
	add_child_autofree(session)
	session.players = [{"peer": 1, "ready": true}]
	# A single-element array, not a plain int: GDScript lambdas capture outer
	# locals by value, so `count += 1` inside one would not reach the caller.
	var broadcasts: Array[int] = [0]
	session.lobby_changed.connect(func() -> void: broadcasts[0] += 1)
	session.set_race_options(4, 3, "track_02_lumen_underpass", "hard")
	assert_eq(session.laps, 4)
	assert_eq(session.ai_count, 3)
	assert_eq(session.track_id, "track_02_lumen_underpass")
	assert_eq(session.difficulty_id, "hard")
	assert_eq(broadcasts[0], 1)
	# Ignored once the race has started: `_prepare_race` owns these fields then.
	session.started = true
	session.set_race_options(1, 0, "track_01_ridgeline_circuit", "easy")
	assert_eq(session.laps, 4)
	assert_eq(broadcasts[0], 1)

## A client applies whatever the authoritative `_lobby` broadcast carries
## (mirrors `test_authoritative_lobby_return_clears_the_previous_client_race`
## below: running the RPC body directly, as the client would on receipt).
func test_lobby_broadcast_applies_the_hosts_race_options_on_the_client() -> void:
	var session: NetSession = NetSession.new()
	add_child_autofree(session)
	session._lobby([{"peer": 1, "ready": true}], 5, 2, "track_04_ochre_rift", "easy")
	assert_eq(session.laps, 5)
	assert_eq(session.ai_count, 2)
	assert_eq(session.track_id, "track_04_ochre_rift")
	assert_eq(session.difficulty_id, "easy")

## Review finding 3: `apply_race_settings` must clamp, not the call sites, so
## a hostile `_lobby` broadcast (a compromised or buggy host) cannot hand a
## client an unbounded lap count or a negative bot count.
func test_lobby_broadcast_clamps_a_hostile_payload() -> void:
	var session: NetSession = NetSession.new()
	add_child_autofree(session)
	session._lobby([{"peer": 1, "ready": true}], 2147483647, -50, "track_01_ridgeline_circuit", "easy")
	assert_eq(session.laps, 9, "laps must clamp to the max of 9")
	assert_eq(session.ai_count, 0, "negative ai_count must clamp to 0")

## Review finding 3: the old call-site clamp in `_prepare_race` bounded
## `ai_count` against the roster BEFORE the roster replace, so a mid-race
## promoted joiner's stale/empty pre-replace roster could widen the cap and
## let `slots + ai_count` exceed `RaceSnapshot.MAX_KARTS` (rejected by
## `RaceSnapshot.unpack`, desyncing that peer for the whole race).
## `apply_race_settings` now clamps after `begin_prepare` has already
## replaced the roster, so it always reads the roster this call just saw.
func test_begin_prepare_clamps_ai_count_against_the_post_replace_roster() -> void:
	var session: NetSession = NetSession.new()
	add_child_autofree(session)
	session.players = [{"peer": 1, "ready": true}] # stale 1-player roster
	var roster: Array = [
		{"peer": 1, "driver": NetContentCatalog.default_driver_id(), "kart": NetContentCatalog.default_kart_id(), "ready": true},
		{"peer": 2, "driver": NetContentCatalog.default_driver_id(), "kart": NetContentCatalog.default_kart_id(), "ready": true},
		{"peer": 3, "driver": NetContentCatalog.default_driver_id(), "kart": NetContentCatalog.default_kart_id(), "ready": true},
	]
	# 11 fits the stale 1-player roster (12 - 1) but not the real 3-player one.
	session._roster.begin_prepare(roster, 4, 11, "track_01_ridgeline_circuit", "easy")
	assert_eq(session.players.size(), 3, "roster must have been replaced first")
	assert_eq(session.ai_count, RaceSnapshot.MAX_KARTS - 3, "ai_count must clamp against the post-replace roster, not the stale pre-replace one")

## `_prepare_race`'s roster/lobby half (NetSessionLobby.begin_prepare) and
## `NetRaceSetup.build` are what carry laps/bots/track/difficulty into the
## `RaceConfig` every peer builds identically (spec item 1); exercised
## directly rather than through `_prepare_race`, which also deferrably
## changes the active scene.
func test_prepare_race_settings_flow_into_the_built_race_config() -> void:
	var session: NetSession = NetSession.new()
	add_child_autofree(session)
	var roster: Array = [{"peer": 1, "driver": NetContentCatalog.default_driver_id(), "kart": NetContentCatalog.default_kart_id(), "ready": true}]
	session._roster.begin_prepare(roster, 4, 2, "track_03_glacier_crown", "hard")
	assert_eq(session.laps, 4)
	assert_eq(session.ai_count, 2)
	assert_eq(session.track_id, "track_03_glacier_crown")
	assert_eq(session.difficulty_id, "hard")
	assert_true(session._roster.preparing)
	var config: RaceConfig = NetRaceSetup.build(session.players, session.ai_count, session.laps, 42, session.track_id, session.difficulty_id)
	assert_eq(config.laps, 4)
	assert_eq(config.ai_difficulty.id, &"hard")
	assert_eq(config.track.id, &"track_03_glacier_crown")

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

## Review finding 7: a mid-race-promoted joiner only just received a roster
## row from `_return_to_lobby` — without also broadcasting the lobby, its
## controls stick on NetSession's constructor defaults instead of the host's
## real laps/bots/track/difficulty. `NetDebugConditions.delivered` counts
## queued sends (never a real socket), so 2 proves both `_return_to_lobby`
## and `_lobby` were queued, not just the one this method already sent.
func test_restart_to_lobby_also_broadcasts_the_lobby() -> void:
	var session: NetSession = NetSession.new()
	add_child_autofree(session)
	session.peer = ENetMultiplayerPeer.new()
	session.players = [{"peer": 1, "ready": true}]
	session.laps = 5
	session.ai_count = 2
	session.track_id = "track_04_ochre_rift"
	session.difficulty_id = "hard"
	session.started = true
	var before: int = session.conditions.delivered
	session.restart_to_lobby()
	session.conditions.advance(NetSession.now() + 1.0)
	assert_eq(session.conditions.delivered - before, 2, "restart_to_lobby must queue both _return_to_lobby and the _lobby broadcast")

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
