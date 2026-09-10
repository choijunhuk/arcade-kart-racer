extends GutTest


class WireSession extends NetSession:
	var slot: int = 0
	var input_packets: int = 0
	var burst_packets: int = 0
	var burst_start: int = -1
	var wire_time: float = 0.0
	var packets: Array[Dictionary] = []
	var max_snapshot_bytes: int = 0
	var max_full_snapshot_bytes: int = 0
	var oversize_packets: int = 0
	func _ready() -> void:
		set_physics_process(false)
	func local_slot() -> int:
		return slot
	func bind_race(value: NetRace) -> void:
		race = value
	func send(method: StringName, target: int, args: Array, reliable: bool) -> void:
		if method == &"_receive_input":
			input_packets += 1
			if burst_start >= 0 and input_packets >= burst_start and input_packets < burst_start + 20:
				burst_packets += 1
				return
		conditions.enqueue(wire_time, reliable, _deliver.bind(method, target, args.duplicate(true), reliable))
	func _deliver(method: StringName, target: int, args: Array, reliable: bool) -> void:
		if not reliable and var_to_bytes(args).size() + NetTuning.RPC_OVERHEAD_BYTES > NetTuning.MAX_UNRELIABLE_BYTES:
			oversize_packets += 1
			return
		if method == &"_snapshot":
			max_snapshot_bytes = maxi(max_snapshot_bytes, args[0].size())
			var snapshot: RaceSnapshot = RaceSnapshot.unpack(args[0])
			snapshot.projectiles.clear()
			for index: int in range(16):
				var position: Array = snapshot.karts[index % 8]["state"]["position"]
				snapshot.projectiles.append({"id": 100 + index, "item": index % 4 + 1, "owner": index % 8,
					"pose": Transform3D(Basis.from_euler(Vector3(index * 0.0123, index * 0.3456, index * -0.0234)),
						Vector3(position[0] + index, position[1] + 0.456, position[2] - index))})
			max_full_snapshot_bytes = maxi(max_full_snapshot_bytes, snapshot.pack().size())
		packets.append({"method": method, "args": args})

class ReplicaManager extends RaceManager:
	func _ready() -> void:
		network_replica = true
		_hazard_relay = HazardRelay.new()
		modes = RaceModes.new()
		add_child(_hazard_relay)
		add_child(modes)
		_begin_loading(false)
		network = NetRace.new()
		add_child(network)
		network.configure(self, GameState.net_session)
		network.set_physics_process(false)

func test_race_without_transport_delay() -> void:
	await _run_race(0.0, 0.0, -1)

func test_race_with_latency_and_two_percent_loss() -> void:
	await _run_race(0.1, 0.02, -1)

func test_race_with_latency_loss_and_twenty_packet_burst() -> void:
	await _run_race(0.1, 0.02, 900)

func test_native_roster_delayed_start_recovers_wall_contacts_and_input_burst() -> void:
	await _run_race(0.1, 0.02, 2500, true)

func _run_race(latency: float, loss: float, burst_start: int, native_start: bool = false) -> void:
	GameState.automation_mode = true
	GameState.is_networked = true
	var host: WireSession = WireSession.new()
	var client: WireSession = WireSession.new()
	client.slot = 1
	client.burst_start = burst_start
	for session: WireSession in [host, client]:
		session.players = [{"peer": 1}, {"peer": 2}]
		session.automated = true
		session.conditions.latency_seconds = latency
		session.conditions.loss = loss
		add_child_autofree(session)
	var slots: Array[PlayerSlot] = []
	for index: int in range(2):
		var slot: PlayerSlot = PlayerSlot.new()
		slot.grid_slot = index
		slot.device_id = index - 1
		slot.driver_id = &"nova"
		slot.kart_id = &"medium"
		if native_start:
			var defaults: Dictionary = host._new_player(index + 1)
			slot.driver_id = StringName(defaults["driver"])
			slot.kart_id = StringName(defaults["kart"])
		slots.append(slot)
	var config: RaceConfig = RaceConfigBuilder.build_local(slots, LocalLobby.DEFAULT_TRACK, LocalLobby.DEFAULT_DIFFICULTY, 8)
	config.laps = 1
	config.seed = 15
	var managers: Array[RaceManager] = []
	for session: WireSession in [host, client]:
		var viewport: SubViewport = SubViewport.new()
		viewport.own_world_3d = true
		add_child_autofree(viewport)
		GameState.net_session = session
		var manager: RaceManager = (load("res://race/race.tscn") as PackedScene).instantiate() as RaceManager
		if session == client:
			manager.set_script(ReplicaManager)
		manager.configure(config.duplicate(true))
		viewport.add_child(manager)
		managers.append(manager)
	var maximum: float = 0.0
	client.running = not native_start
	if native_start:
		host.send(&"_begin_race", 0, [], true)
	host.running = true
	host.race.begin()
	var diagnostics: NetTestRun = NetTestRun.new()
	diagnostics.session = host
	for tick: int in range(1, 14400):
		host.wire_time = tick / 60.0
		client.wire_time = tick / 60.0
		await get_tree().physics_frame
		host.conditions.advance(host.wire_time)
		client.conditions.advance(client.wire_time)
		for packet: Dictionary in host.packets:
			if packet["method"] == &"_begin_race":
				client.running = true
			elif packet["method"] == &"_snapshot":
				var snapshot: RaceSnapshot = RaceSnapshot.unpack(packet["args"][0])
				client.snapshot_received.emit(snapshot)
			elif packet["method"] == &"_event" and packet["args"][0] == "results":
				client.event_received.emit(packet["args"][0], packet["args"][1])
		host.packets.clear()
		if client.running:
			client.race._client_step()
		for packet: Dictionary in client.packets:
			if packet["method"] == &"_receive_input":
				host.race.receive_input(2, packet["args"][0])
		client.packets.clear()
		if not client.race.statistics.is_empty():
			maximum = float(client.race.statistics[1]["max"])
		if tick % 300 == 0:
			diagnostics._log_progress()
		if managers[1].get_state() == RaceState.RESULTS:
			break
	print("IN_PROCESS_DIAGNOSTIC max=%s stats=%s server_state=%s" % [maximum, client.race.statistics, managers[0].get_state()])
	assert_false(client.race.statistics.is_empty())
	if client.race.statistics.has(1):
		var stats: Dictionary = client.race.statistics[1]
		var mean: float = float(stats["sum"]) / maxi(1, int(stats["count"]))
		print("IN_PROCESS_LIMITS latency=%s loss=%s burst=%d mean=%s max=%s" % [latency, loss, client.burst_packets, mean, maximum])
		assert_lt(mean, NetTestRun.MEAN_LIMIT)
		assert_lt(maximum, NetTuning.SNAP_METERS)
	assert_eq(client.burst_packets, 20 if burst_start >= 0 else 0)
	if loss > 0.0:
		assert_gt(client.conditions.dropped, 0)
	assert_eq(managers[0].get_state(), RaceState.RESULTS)
	assert_eq(managers[1].get_state(), RaceState.RESULTS)
	assert_eq(managers[0].get_results().size(), 8)
	assert_eq(managers[1].get_results().size(), 8)
	for manager: RaceManager in managers:
		for entry: RaceResults.Entry in manager.get_results():
			assert_gte(entry.total_time_seconds, 0.0)
	assert_eq(host.oversize_packets + client.oversize_packets, 0)
	assert_lte(host.max_full_snapshot_bytes + 80, NetTuning.MAX_UNRELIABLE_BYTES)
	print("SERIALIZED_MTU max_snapshot=%d max_with_16_projectiles=%d oversized=%d host_results=%d client_results=%d" % [host.max_snapshot_bytes, host.max_full_snapshot_bytes, host.oversize_packets + client.oversize_packets, managers[0].get_results().size(), managers[1].get_results().size()])

	diagnostics.free()
	GameState.net_session = null
	GameState.is_networked = false
	GameState.automation_mode = false
