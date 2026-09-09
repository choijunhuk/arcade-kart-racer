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


## Regressions for sustained input lag and real motion versus drivetrain speed.
func test_late_fresh_input_recovers_after_server_repeated_missing_ticks() -> void:
	var buffer: NetInputBuffer = NetInputBuffer.new()
	var frame: InputFrame = InputFrame.new()
	frame.tick = 1
	frame.throttle = 0.8
	buffer.insert(frame)
	buffer.consume(1)
	for tick: int in range(2, 30):
		buffer.consume(tick)
	frame.tick = 20
	frame.throttle = 0.3
	assert_true(buffer.insert(frame), "Fresh input must survive server/client tick drift")
	assert_eq(buffer.consume(30).throttle, 0.3)
	frame.tick = 19
	assert_false(buffer.insert(frame), "Out-of-order input must not rewind the controls")
	frame.tick = 21
	frame.throttle = 1.0
	assert_true(buffer.insert(frame))
	assert_eq(buffer.consume(31).throttle, 1.0)

func test_due_inputs_survive_skipped_consumer_tick() -> void:
	var buffer: NetInputBuffer = NetInputBuffer.new()
	var frame: InputFrame = InputFrame.new()
	frame.tick = 2
	frame.throttle = 0.7
	buffer.insert(frame)
	assert_eq(buffer.consume(3).throttle, 0.7)
	assert_eq(buffer.consume(4).throttle, 0.7)

func test_client_recovers_two_dropped_packets_with_three_tick_batch() -> void:
	var network: NetRace = _manager.network
	for index: int in range(4):
		network._client_step()
	var packet: Dictionary = _session.packets.back()
	var batch: Dictionary = packet["args"][0]
	assert_true(batch.get("frames") is Array, "Each packet must resend the last three input ticks")
	if not batch.get("frames") is Array:
		return
	assert_eq(batch["frames"].size(), 3)
	assert_eq(batch["frames"][0]["tick"], 2)
	assert_eq(batch["frames"][2]["tick"], 4)
	assert_lte(var_to_bytes(packet["args"]).size() + NetTuning.RPC_OVERHEAD_BYTES, NetTuning.MAX_UNRELIABLE_BYTES)
	network.receive_input(2, batch)
	var buffer: NetInputBuffer = network.get("_buffers")[1]
	assert_gt(buffer.consume(2).throttle, 0.0)
	assert_gt(buffer.consume(3).throttle, 0.0)
	assert_gt(buffer.consume(4).throttle, 0.0)

func test_server_recovers_stationary_network_human_with_high_scalar_speed() -> void:
	var kart: KartController = _manager.get_karts()[1]
	var respawn: RespawnSystem = _manager.get_node("RespawnSystem") as RespawnSystem
	kart.set_frozen(false)
	var frame: InputFrame = InputFrame.new()
	frame.tick = 1
	frame.throttle = 1.0
	_manager.network.receive_input(2, frame.to_dict())
	_manager.network.tick = NetTuning.INPUT_DELAY
	_manager.network._server_step()
	# Continuous wall contact can leave drivetrain speed high without body travel.
	kart.get_node("KartPhysics").set("speed", 10.0)
	for tick: int in range(ceili(respawn.tuning.stuck_duration / NetTuning.STEP) + 2):
		respawn._physics_process(NetTuning.STEP)
	assert_eq(kart.get_state(), KartState.RESPAWNING)
	respawn._physics_process(respawn.tuning.respawn_fade_duration)
	respawn._physics_process(respawn.tuning.respawn_frozen_duration)
	assert_ne(kart.get_state(), KartState.RESPAWNING)

func test_twenty_packet_gap_repeats_levels_once_then_accepts_fresh_controls() -> void:
	var buffer: NetInputBuffer = NetInputBuffer.new()
	var frame: InputFrame = InputFrame.new()
	frame.tick = 1
	frame.throttle = 0.8
	frame.drift = true
	frame.item = true
	frame.drift_pressed = true
	buffer.insert(frame)
	assert_true(buffer.consume(1).item)
	for tick: int in range(2, 22):
		var repeated: InputFrame = buffer.consume(tick)
		assert_eq(repeated.throttle, 0.8)
		assert_true(repeated.drift)
		assert_false(repeated.item)
		assert_false(repeated.drift_pressed)
		assert_eq(buffer.last_processed_tick, tick)
	frame.tick = 22
	frame.throttle = 0.2
	frame.drift = false
	buffer.insert(frame)
	assert_eq(buffer.consume(22).throttle, 0.2)
	assert_false(buffer.consume(22).item)
	assert_false(buffer.insert(frame))

func test_batch_recovers_missing_edge_without_replaying_it_on_duplicate() -> void:
	var frames: Array[Dictionary] = []
	for tick: int in range(1, 4):
		var frame: InputFrame = InputFrame.new()
		frame.tick = tick
		frame.item = tick == 2
		frame.drift_pressed = tick == 2
		frames.append(frame.to_dict())
	_manager.network.receive_input(2, {"frames": frames})
	var buffer: NetInputBuffer = _manager.network.get("_buffers")[1]
	assert_false(buffer.consume(1).item)
	assert_true(buffer.consume(2).item)
	_manager.network.receive_input(2, {"frames": frames})
	assert_false(buffer.consume(3).item)
	assert_false(buffer.consume(4).drift_pressed)

func test_malformed_or_oversized_batches_and_unknown_senders_do_not_drive() -> void:
	var frame: InputFrame = InputFrame.new()
	frame.tick = 1
	frame.throttle = 1.0
	var row: Dictionary = frame.to_dict()
	_manager.network.receive_input(2, {"frames": "bad"})
	_manager.network.receive_input(2, {"frames": [row, row, row, row]})
	_manager.network.receive_input(99, {"frames": [row]})
	row["steer"] = NAN
	_manager.network.receive_input(2, {"frames": [null, row]})
	var buffer: NetInputBuffer = _manager.network.get("_buffers")[1]
	assert_eq(buffer.consume(1).throttle, 0.0)
	assert_eq(buffer.last_received_tick, 0)

func test_moving_network_human_does_not_respawn() -> void:
	var kart: KartController = _manager.get_karts()[1]
	var respawn: RespawnSystem = _manager.get_node("RespawnSystem") as RespawnSystem
	kart.set_frozen(false)
	var frame: InputFrame = InputFrame.new()
	frame.throttle = 1.0
	kart.step_input(frame, NetTuning.STEP)
	kart.get_node("KartPhysics").set("speed", 10.0)
	for tick: int in range(ceili(respawn.tuning.stuck_duration / NetTuning.STEP) + 2):
		kart.position.z -= 10.0 * NetTuning.STEP
		respawn._physics_process(NetTuning.STEP)
	assert_ne(kart.get_state(), KartState.RESPAWNING)

func test_idle_network_human_does_not_respawn_without_throttle() -> void:
	var kart: KartController = _manager.get_karts()[1]
	var respawn: RespawnSystem = _manager.get_node("RespawnSystem") as RespawnSystem
	kart.set_frozen(false)
	kart.step_input(InputFrame.zero(), NetTuning.STEP)
	respawn._physics_process(respawn.tuning.stuck_duration + NetTuning.STEP)
	assert_ne(kart.get_state(), KartState.RESPAWNING)

func test_repeated_wall_bumps_cannot_reset_network_human_stuck_timer() -> void:
	var kart: KartController = _manager.get_karts()[1]
	var respawn: RespawnSystem = _manager.get_node("RespawnSystem") as RespawnSystem
	kart.set_frozen(false)
	var frame: InputFrame = InputFrame.new()
	frame.throttle = 0.12
	var anchor: Vector3 = kart.global_position
	for tick: int in range(ceili((respawn.tuning.stuck_duration + 1.0) / NetTuning.STEP)):
		# Exercise the real wall-hit/invulnerability path while the body is blocked.
		if tick % 90 == 0:
			kart._on_wall_head_on()
		kart.step_input(frame, NetTuning.STEP)
		kart.global_position = anchor
		kart.reset_motion_arcade()
		respawn._physics_process(NetTuning.STEP)
		if kart.get_state() == KartState.RESPAWNING:
			break
	assert_eq(kart.get_state(), KartState.RESPAWNING)

func test_network_human_recovers_despite_periodic_wall_hits() -> void:
	var kart: KartController = _manager.get_karts()[1]
	var respawn: RespawnSystem = _manager.get_node("RespawnSystem") as RespawnSystem
	kart.set_frozen(false)
	var frame: InputFrame = InputFrame.new()
	frame.throttle = 0.12
	for tick: int in range(ceili(respawn.tuning.stuck_duration / NetTuning.STEP) + 60):
		kart.get_node("KartPhysics").set("speed", 0.0)
		if tick % 30 == 0:
			(kart.get_node("HitReactor") as HitReactor).clear()
			kart.apply_hit(HitReactor.HitType.BUMP)
		kart.step_input(frame, NetTuning.STEP, true)
		respawn._physics_process(NetTuning.STEP)
		if kart.get_state() == KartState.RESPAWNING:
			break
	assert_eq(kart.get_state(), KartState.RESPAWNING)

## Spec item E: item-hit chains (SPIN_OUT/TUMBLE) are a different cause from
## a wall/self BUMP jam. Unlike the BUMP case above, this must keep resetting
## the network human's stuck timer through the whole chain, so being
## incapacitated by items never forces a respawn on its own.
func test_item_hit_chain_does_not_respawn_network_human() -> void:
	var kart: KartController = _manager.get_karts()[1]
	var respawn: RespawnSystem = _manager.get_node("RespawnSystem") as RespawnSystem
	kart.set_frozen(false)
	var frame: InputFrame = InputFrame.new()
	frame.throttle = 0.12
	for tick: int in range(ceili((respawn.tuning.stuck_duration + 1.0) / NetTuning.STEP)):
		kart.get_node("KartPhysics").set("speed", 0.0)
		if tick % 30 == 0:
			(kart.get_node("HitReactor") as HitReactor).clear()
			kart.apply_hit(HitReactor.HitType.SPIN_OUT)
		kart.step_input(frame, NetTuning.STEP, true)
		respawn._physics_process(NetTuning.STEP)
		if kart.get_state() == KartState.RESPAWNING:
			break
	assert_ne(kart.get_state(), KartState.RESPAWNING)

## Spec item A regression: a network human passing all 8 of track_01's real
## checkpoints must complete its lap, and a mid-lap server-owned respawn
## (the stuck-recovery path) must never reset LapTracker's own record of
## progress (`last_checkpoint_index`/`next_checkpoint_index`) — investigation
## found no such reset in the current code (register_kart is idempotent and
## respawn never re-registers), but this locks the invariant in against
## regressions in either system.
func test_network_human_passing_eight_checkpoints_completes_lap_and_respawn_keeps_checkpoint_index() -> void:
	var kart: KartController = _manager.get_karts()[1]
	var lap_tracker: LapTracker = _manager.get_node("LapTracker") as LapTracker
	var respawn: RespawnSystem = _manager.get_node("RespawnSystem") as RespawnSystem
	kart.set_frozen(false)
	for index: int in range(4):
		lap_tracker._on_body_passed(kart, index)
	assert_eq(lap_tracker.get_last_checkpoint_index(kart), 3)
	assert_eq(lap_tracker.get_next_checkpoint_index(kart), 4)
	# Mid-lap server-owned stuck recovery must preserve checkpoint progress.
	respawn.request_respawn(kart)
	respawn._physics_process(respawn.tuning.respawn_fade_duration)
	respawn._physics_process(respawn.tuning.respawn_frozen_duration)
	assert_ne(kart.get_state(), KartState.RESPAWNING)
	assert_eq(lap_tracker.get_last_checkpoint_index(kart), 3)
	assert_eq(lap_tracker.get_next_checkpoint_index(kart), 4)
	assert_false(lap_tracker.is_finished(kart))
	for index: int in range(4, 8):
		lap_tracker._on_body_passed(kart, index)
	lap_tracker._on_body_passed(kart, 0)
	assert_eq(lap_tracker.get_lap(kart), 1)
	assert_true(lap_tracker.is_finished(kart))
