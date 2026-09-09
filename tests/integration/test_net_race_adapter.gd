extends GutTest

## In-process adapter verification, explicitly not an ENet loopback replacement.
class CaptureSession extends NetSession:
	var packets: Array[Dictionary] = []
	func send(method: StringName, target: int, args: Array, reliable: bool) -> void:
		packets.append({"method": method, "target": target, "args": args, "reliable": reliable})
	func bind_race(value: NetRace) -> void:
		race = value
	func local_slot() -> int:
		return 0

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
	snapshot.karts[0]["lap"] = 1
	snapshot.karts[0]["rank"] = 2
	_manager.network_replica = true
	state.apply(snapshot)
	assert_eq((_manager.get_node("LapTracker") as LapTracker).get_lap(_manager.get_karts()[0]), 1)
	assert_eq((_manager.get_node("PositionTracker") as PositionTracker).get_position(_manager.get_karts()[0]), 2)
	var entry: RaceResults.Entry = RaceResults.Entry.new()
	entry.grid_slot = 0
	entry.kart_name = "PlayerKart1"
	entry.total_time_seconds = 12.0
	entry.rank = 1
	var entries: Array[RaceResults.Entry] = NetResults.unpack(NetResults.pack([entry]), 0)
	_manager.apply_network_results(entries)
	assert_eq(_manager.get_state(), RaceState.RESULTS)
	assert_eq(_manager.get_results()[0].total_time_seconds, 12.0)
