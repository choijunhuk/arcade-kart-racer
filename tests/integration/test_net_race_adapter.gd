extends GutTest

## In-process adapter verification, explicitly not an ENet loopback replacement.
class CaptureSession extends NetSession:
	var packets: Array[Dictionary] = []
	var slot: int = 0
	func send(method: StringName, target: int, args: Array, reliable: bool) -> void:
		packets.append({"method": method, "target": target, "args": args, "reliable": reliable})
	func bind_race(value: NetRace) -> void:
		super.bind_race(value)
	func local_slot() -> int:
		return slot

var _manager: RaceManager
var _session: CaptureSession

func before_each() -> void:
	_session = CaptureSession.new()
	_session.automated = true
	_session.players = [{"peer": 1}, {"peer": 2}]
	add_child_autofree(_session)
	_session.set_physics_process(false)
	GameState.net_session = _session
	GameState.is_networked = true
	GameState.automation_mode = true
	var config: RaceConfig = RaceConfig.new()
	config.track = preload("res://data/tracks/track_01.tres")
	config.player_kart = preload("res://data/karts/medium.tres")
	config.kart_count = 2
	config.laps = 1
	for index: int in range(2):
		var player: PlayerSlot = PlayerSlot.new()
		player.grid_slot = index
		player.device_id = index - 1
		player.driver_id = &"nova"
		player.kart_id = &"medium"
		config.players.append(player)
	_manager = (load("res://race/race.tscn") as PackedScene).instantiate() as RaceManager
	_manager.configure(config)
	add_child_autofree(_manager)

func after_each() -> void:
	GameState.net_session = null
	GameState.is_networked = false
	GameState.automation_mode = false

func test_loading_barrier_freezes_countdown_until_begin() -> void:
	await wait_physics_frames(5)
	assert_eq(_manager.get_state(), RaceState.COUNTDOWN)
	assert_eq((_manager.get_node("Countdown") as Countdown).get_phase_seconds(), 0.0)
	assert_eq(_manager.network.tick, 0)
	_session.running = true
	_manager.network.begin()
	await wait_physics_frames(5)
	assert_gt(_manager.network.tick, 0)
	assert_gt((_manager.get_node("Countdown") as Countdown).get_phase_seconds(), 0.0)

func test_server_consumes_remote_input_after_two_tick_delay() -> void:
	_session.running = true
	_manager.network.begin()
	var remote: InputFrame = InputFrame.new()
	remote.tick = 1
	remote.throttle = 0.7
	_manager.network.receive_input(2, remote.to_dict())
	await wait_physics_frames(8)
	assert_almost_eq(_manager.get_karts()[1].get_throttle_input(), 0.7, 0.00001)
	assert_false(_session.packets.is_empty())
	for packet: Dictionary in _session.packets:
		if packet["method"] == &"_snapshot":
			var snapshot: RaceSnapshot = RaceSnapshot.unpack(packet["args"][0])
			assert_not_null(snapshot)
			if snapshot != null:
				assert_eq(snapshot.karts.size(), 2)

func test_replica_snapshot_updates_hud_reads_and_results_without_authority() -> void:
	var state: NetRaceState = NetRaceState.new(_manager)
	var snapshot: RaceSnapshot = state.capture(3, [0, 0])
	snapshot.karts[0]["state"]["components"]["."]["state"] = KartState.GROUNDED
	snapshot.karts[0]["state"]["components"]["."]["_race_frozen"] = false
	snapshot.karts[0]["lap"] = 1
	snapshot.karts[0]["rank"] = 2
	_manager.network_replica = true
	state.apply(snapshot)
	assert_eq((_manager.get_node("LapTracker") as LapTracker).get_lap(_manager.get_karts()[0]), 1)
	assert_eq((_manager.get_node("PositionTracker") as PositionTracker).get_position(_manager.get_karts()[0]), 2)
	for kart: KartController in _manager.get_karts():
		kart.network_replica = true
	_manager.network._receive_snapshot(snapshot)
	_manager.network._client_step()
	assert_eq(_manager.network.prediction.frames.size(), 1)
	assert_eq(_session.packets.back()["method"], &"_receive_input")
	var entry: RaceResults.Entry = RaceResults.Entry.new()
	entry.grid_slot = 0
	entry.kart_name = "PlayerKart1"
	entry.total_time_seconds = 12.0
	entry.rank = 1
	var entries: Array[RaceResults.Entry] = NetResults.unpack(NetResults.pack([entry]), 0)
	_manager.apply_network_results(entries)
	assert_eq(_manager.get_state(), RaceState.RESULTS)
	assert_eq(_manager.get_results()[0].total_time_seconds, 12.0)

func test_event_mirror_encodes_grid_identity_and_actual_signal_name() -> void:
	EventBus.item_used.emit(_manager.get_karts()[1], &"nitro_can")
	var packet: Dictionary = _session.packets.back()
	assert_eq(packet["method"], &"_event")
	assert_eq(packet["args"][0], "item_used")
	assert_eq(packet["args"][1][0], {"kart": 1})
	EventBus.boost_started.emit(_manager.get_karts()[0], _manager.get_karts()[0].tuning.boost_pad_boost)
	packet = _session.packets.back()
	assert_eq(packet["args"][0], "boost_started")
	assert_true(KartReplayState.valid_event(packet["args"][1][1]))

func test_race_events_and_countdown_use_reliable_rpc() -> void:
	var kart: KartController = _manager.get_karts()[0]
	EventBus.lap_completed.emit(kart, 1, 12.0)
	EventBus.kart_finished.emit(kart, 12.0)
	EventBus.roulette_stopped.emit(kart)
	EventBus.item_hit.emit(kart, kart, &"nitro_can")
	EventBus.countdown_tick.emit(3)
	var kinds: Array[String] = []
	for packet: Dictionary in _session.packets:
		if packet["method"] == &"_event":
			assert_true(packet["reliable"])
			kinds.append(packet["args"][0])
	for kind: String in ["lap_completed", "kart_finished", "roulette_stopped", "item_hit", "countdown_tick"]:
		assert_has(kinds, kind)
	var rpc_config: Dictionary = _session.get_script().get_base_script().get_rpc_config()
	assert_eq(rpc_config["_event"]["transfer_mode"], MultiplayerPeer.TRANSFER_MODE_RELIABLE)
	assert_eq(rpc_config["_event"]["rpc_mode"], MultiplayerAPI.RPC_MODE_AUTHORITY)

func test_reliable_countdown_does_not_repeat_predicted_or_delayed_ticks() -> void:
	watch_signals(EventBus)
	_manager.network._receive_event("countdown_tick", [3])
	_manager.network._receive_event("countdown_tick", [2])
	_manager.network._receive_event("countdown_tick", [3])
	_manager.network._receive_event("countdown_tick", [2])
	assert_signal_emit_count(EventBus, "countdown_tick", 2)

func test_results_cannot_be_rewound_by_an_older_unreliable_snapshot() -> void:
	_manager.network_replica = true
	_manager.apply_network_results([])
	_manager.apply_network_state(RaceState.FINISHING)
	assert_eq(_manager.get_state(), RaceState.RESULTS)

func test_server_completes_two_human_lap_through_buffered_inputs() -> void:
	_session.running = true
	_manager.network.begin()
	var remote: ScriptedRaceInputProvider = ScriptedRaceInputProvider.new(
		_manager.get_karts()[1], (_manager.get_node("Track") as TrackRoot).get_racing_line())
	const MAX_RACE_TICKS: int = NetTuning.TICK_RATE * 240
	for tick: int in range(1, MAX_RACE_TICKS):
		if _manager.get_state() == RaceState.RESULTS:
			break
		var frame: InputFrame = remote.get_frame()
		frame.tick = tick
		_manager.network.receive_input(2, frame.to_dict())
		await get_tree().physics_frame
	assert_eq(_manager.get_state(), RaceState.RESULTS)
	assert_eq(_manager.get_results().size(), 2)
	for entry: RaceResults.Entry in _manager.get_results():
		assert_gt(entry.total_time_seconds, 0.0)

func test_finished_server_human_uses_installed_safe_provider() -> void:
	var kart: KartController = _manager.get_karts()[1]
	var remote: InputFrame = InputFrame.new()
	remote.tick = 1
	remote.throttle = 1.0
	_manager.network.receive_input(2, remote.to_dict())
	_manager.network.tick = NetTuning.INPUT_DELAY
	_manager.network._server_step()
	assert_eq(kart.get_throttle_input(), 1.0)
	kart.set_finished(InputProvider.new())
	_manager.network.tick = NetTuning.INPUT_DELAY + 1
	_manager.network._server_step()
	assert_eq(kart.get_throttle_input(), 0.0)
	remote.tick = 2
	_manager.network.receive_input(2, remote.to_dict())
	assert_eq((_manager.network.get("_buffers")[1] as NetInputBuffer).last_processed_tick, 1)

func test_finished_client_stops_input_and_replay() -> void:
	var kart: KartController = _manager.get_karts()[0]
	kart.set_finished(InputProvider.new())
	var state: NetRaceState = NetRaceState.new(_manager)
	var snapshot: RaceSnapshot = state.capture(3, [0, 0])
	var frame: InputFrame = InputFrame.new()
	frame.tick = 1
	frame.throttle = 1.0
	_manager.network.prediction.record(frame)
	_session.packets.clear()
	_manager.network._receive_snapshot(snapshot)
	_manager.network._client_step()
	assert_true(_session.packets.is_empty())
	assert_true(_manager.network.prediction.frames.is_empty())
	assert_eq(kart.global_position, Vector3(snapshot.karts[0]["state"]["position"][0], snapshot.karts[0]["state"]["position"][1], snapshot.karts[0]["state"]["position"][2]))

func test_non_host_local_audio_has_primary_gain_and_filter() -> void:
	_session.slot = 1
	_manager._begin_loading(true)
	var host_audio: KartAudio = _manager.get_karts()[0].get_node("KartAudio") as KartAudio
	var local_audio: KartAudio = _manager.get_karts()[1].get_node("KartAudio") as KartAudio
	assert_false(host_audio.player_audio)
	assert_true(local_audio.player_audio)
	assert_eq(float(local_audio.get("_local_player_gain")), 1.0)
	assert_true(bool(local_audio.get("_controls_engine_filter")))

func test_client_departure_removes_kart_and_keeps_race_running() -> void:
	_session.started = true
	_session.running = true
	var remote: KartController = _manager.get_karts()[1]
	_session._peer_disconnected(2)
	assert_false(_session.is_queued_for_deletion())
	assert_true(_session.running)
	assert_eq(_session.players.size(), 1)
	assert_eq(_manager.get_karts().size(), 1)
	assert_eq(_manager.get_human_karts().size(), 1)
	assert_false(is_instance_valid(remote))
	assert_eq((_manager.network.get("_buffers") as Array).size(), 1)
	assert_true(_session.packets.any(func(packet: Dictionary) -> bool: return packet["method"] == &"_player_left"))

func test_host_departure_ends_session() -> void:
	watch_signals(_session)
	_session._server_disconnected()
	assert_signal_emitted_with_parameters(_session, "disconnected", ["Host disconnected."])
	assert_true(_session.is_queued_for_deletion())
	assert_false(GameState.is_networked)

func test_departure_preserves_surviving_remote_input_and_result_identity() -> void:
	_manager.network.free()
	var config: RaceConfig = _manager.get("_config")
	config.kart_count = 3
	var player: PlayerSlot = config.players[1].copy()
	player.grid_slot = 2
	config.players.append(player)
	_session.players.append({"peer": 3})
	_session.slot = 2
	_manager._begin_loading(true)
	_manager.network = NetRace.new()
	_manager.add_child(_manager.network)
	_manager.network.configure(_manager, _session)
	_session.started = true
	var survivor: KartController = _manager.get_karts()[2]
	var old_snapshot: RaceSnapshot = NetRaceState.new(_manager).capture(3, [0, 0, 0])
	_manager.network._receive_snapshot(old_snapshot)
	_session._player_left(2)
	assert_eq(_manager.get_karts()[1], survivor)
	assert_eq(int(_manager.network.get("_local")), 1)
	assert_eq(int(_manager.network.get("_local_grid_slot")), 2)
	assert_null(_manager.network.get("_pending"))
	var frame: InputFrame = InputFrame.new()
	frame.tick = 1
	frame.throttle = 0.65
	_manager.network.receive_input(3, frame.to_dict())
	_manager.network.tick = NetTuning.INPUT_DELAY
	_manager.network._server_step()
	assert_eq(survivor.get_throttle_input(), 0.65)
	_manager.network._receive_snapshot(old_snapshot)
	assert_null(_manager.network.get("_pending"))
	var snapshot: RaceSnapshot = NetRaceState.new(_manager).capture(6, [0, 1])
	_manager.network._receive_snapshot(snapshot)
	assert_not_null(_manager.network.get("_pending"))
	_manager.network._apply_snapshot(snapshot)
	var results: Array[RaceResults.Entry] = (_manager.get_node("RaceResults") as RaceResults).finalize(_manager.get_karts(), {})
	assert_eq(results[1].grid_slot, 2)
	assert_true(NetResults.unpack(NetResults.pack(results), int(_manager.network.get("_local_grid_slot")))[1].is_human)
	_manager.network._advance_render_samples(1000000.0)
	assert_eq((_manager.network.get("_interpolators") as Array).size(), 2)

func test_departure_during_countdown_does_not_leave_freed_registrations() -> void:
	_session.started = true
	_session.running = true
	_manager.network.begin()
	_session._peer_disconnected(2)
	await wait_physics_frames(240)
	assert_eq(_manager.get_state(), RaceState.RACING)
	assert_eq(_manager.get_karts().size(), 1)

func test_departure_releases_loading_barrier_for_survivors() -> void:
	_session.started = true
	_session.set("_loaded", [NetSession.SERVER_ID] as Array[int])
	_session._peer_disconnected(2)
	assert_true(_session.running)
	assert_gt((_manager.get_node("Countdown") as Countdown).get_phase_seconds(), 0.0)

func test_respawn_teleport_does_not_count_as_driving_divergence() -> void:
	var kart: KartController = _manager.get_karts()[0]
	kart.set_frozen(false)
	kart.begin_respawn()
	kart.teleport_for_respawn(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.9, -20.0)))
	var snapshot: RaceSnapshot = NetRaceState.new(_manager).capture(5931, [5930, 0])
	var history: Dictionary = _manager.network.get("_predicted_positions")
	history[5930] = Vector3(40.94, -15.15, -27.51)
	kart.position = Vector3(41.19, -15.62, -27.70)
	_manager.network._apply_snapshot(snapshot)
	assert_true(_manager.network.statistics.is_empty())
	assert_true(history.is_empty())
	assert_eq(kart.global_position, Vector3(0.0, 0.9, -20.0))
	_manager.network._client_step()
	assert_eq(_session.packets.back()["method"], &"_receive_input")
	assert_eq(kart.global_position, Vector3(0.0, 0.9, -20.0))

func test_finished_server_keeps_last_input_acknowledgement() -> void:
	var frame: InputFrame = InputFrame.new()
	frame.tick = 1
	frame.throttle = 1.0
	_manager.network.receive_input(2, frame.to_dict())
	_manager.network.tick = NetTuning.INPUT_DELAY
	_manager.network._server_step()
	_manager.get_karts()[1].set_finished(InputProvider.new())
	_manager.network.tick = NetTuning.SNAPSHOT_INTERVAL
	_manager.network._server_step()
	for packet: Dictionary in _session.packets:
		if packet["method"] == &"_snapshot":
			var snapshot: RaceSnapshot = RaceSnapshot.unpack(packet["args"][0])
			assert_eq(snapshot.karts[1]["ack"], 1)

func test_normal_driving_still_records_large_prediction_errors() -> void:
	var kart: KartController = _manager.get_karts()[0]
	kart.set_frozen(false)
	var snapshot: RaceSnapshot = NetRaceState.new(_manager).capture(9, [8, 0])
	var history: Dictionary = _manager.network.get("_predicted_positions")
	history[8] = kart.global_position + Vector3(4.0, 0.0, 0.0)
	_manager.network._apply_snapshot(snapshot)
	assert_eq(float(_manager.network.statistics[0]["max"]), 4.0)

func test_offline_split_screen_keeps_secondary_audio_attenuation() -> void:
	GameState.net_session = null
	GameState.is_networked = false
	_manager._begin_loading(true)
	var primary: KartAudio = _manager.get_karts()[0].get_node("KartAudio") as KartAudio
	var secondary: KartAudio = _manager.get_karts()[1].get_node("KartAudio") as KartAudio
	assert_eq(float(primary.get("_local_player_gain")), 1.0)
	assert_true(bool(primary.get("_controls_engine_filter")))
	assert_eq(float(secondary.get("_local_player_gain")), KartAudio.SECONDARY_PLAYER_GAIN)
	assert_false(bool(secondary.get("_controls_engine_filter")))

func test_departure_before_scene_binding_waits_for_matching_grid() -> void:
	_session.started = true
	_session.race = null
	_session._player_left(2)
	assert_eq(_session.players.size(), 2)
	assert_eq(_session.get("_pending_departures"), [2])
	_session.bind_race(_manager.network)
	assert_true((_session.get("_pending_departures") as Array).is_empty())
	assert_eq(_session.players.size(), 1)
	assert_eq(_manager.get_karts().size(), 1)
