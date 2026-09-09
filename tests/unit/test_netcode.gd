extends GutTest

var _kart: KartController

class RetrySession extends NetSession:
	var targets: Array[int] = []
	func send(method: StringName, target: int, _args: Array, _reliable: bool) -> void:
		if method == &"_prepare_race":
			targets.append(target)

func before_each() -> void:
	_kart = (load("res://kart/kart.tscn") as PackedScene).instantiate() as KartController
	add_child_autofree(_kart)
	_kart.set_physics_process(false)

func _frame(tick: int, throttle: float = 0.5) -> InputFrame:
	var frame: InputFrame = InputFrame.new()
	frame.tick = tick
	frame.throttle = throttle
	return frame

func _snapshot() -> RaceSnapshot:
	var snapshot: RaceSnapshot = RaceSnapshot.new()
	snapshot.tick = 42
	snapshot.race_state = RaceState.RACING
	snapshot.karts.append({"state": _kart.capture_state(), "ack": 39, "lap": 2, "rank": 3})
	return snapshot

func test_snapshot_roundtrip_position_quantization() -> void:
	_kart.position = Vector3(12.345, -6.789, 567.123)
	var source: RaceSnapshot = _snapshot()
	var result: RaceSnapshot = RaceSnapshot.unpack(source.pack())
	assert_not_null(result)
	if result == null: return
	for axis: int in range(3):
		assert_almost_eq(float(result.karts[0]["state"]["position"][axis]), float(source.karts[0]["state"]["position"][axis]), 0.0051)
	assert_eq(result.tick, 42)
	assert_eq(result.karts[0]["ack"], 39)
	assert_eq(result.karts[0]["lap"], 2)

func test_snapshot_yaw_and_component_timers_roundtrip() -> void:
	_kart.rotation.y = 2.34567
	_kart.drift_controller.set("_charge", 0.87654)
	var result: RaceSnapshot = RaceSnapshot.unpack(_snapshot().pack())
	assert_not_null(result)
	if result == null: return
	assert_almost_eq(float(result.karts[0]["state"]["rotation"][1]), 2.34567, 0.00051)
	assert_almost_eq(float(result.karts[0]["state"]["components"]["DriftController"]["_charge"]), 0.87654, 0.00001)

func test_snapshot_rejects_truncation_extra_bytes_and_version() -> void:
	var bytes: PackedByteArray = _snapshot().pack()
	assert_null(RaceSnapshot.unpack(bytes.slice(0, bytes.size() - 1)))
	bytes.append(0)
	assert_null(RaceSnapshot.unpack(bytes))
	bytes = _snapshot().pack()
	bytes[0] = 255
	assert_null(RaceSnapshot.unpack(bytes))

func test_snapshot_projectile_transform_and_id_roundtrip() -> void:
	var source: RaceSnapshot = _snapshot()
	source.projectiles.append({"id": 45, "item": 2, "pose": Transform3D(Basis(Vector3.UP, 0.3), Vector3(1, 2, 3))})
	var result: RaceSnapshot = RaceSnapshot.unpack(source.pack())
	assert_not_null(result)
	if result != null:
		assert_eq(result.projectiles[0]["id"], 45)
		assert_eq((result.projectiles[0]["pose"] as Transform3D).origin, Vector3(1, 2, 3))

func test_buffer_orders_inputs_and_rejects_duplicates() -> void:
	var buffer: NetInputBuffer = NetInputBuffer.new()
	assert_true(buffer.insert(_frame(2, 0.9)))
	assert_true(buffer.insert(_frame(1, 0.4)))
	assert_false(buffer.insert(_frame(2)))
	assert_eq(buffer.consume(1).throttle, 0.4)
	assert_eq(buffer.consume(2).throttle, 0.9)

func test_buffer_gap_repeats_levels_and_clears_edges() -> void:
	var buffer: NetInputBuffer = NetInputBuffer.new()
	var input: InputFrame = _frame(1)
	input.item = true
	input.drift_pressed = true
	input.drift = true
	buffer.insert(input)
	buffer.consume(1)
	var repeated: InputFrame = buffer.consume(2)
	assert_eq(repeated.throttle, 0.5)
	assert_true(repeated.drift)
	assert_false(repeated.drift_pressed)
	assert_false(repeated.item)
	assert_eq(buffer.last_processed_tick, 2)

func test_buffer_rejects_late_and_far_future_inputs() -> void:
	var buffer: NetInputBuffer = NetInputBuffer.new()
	buffer.insert(_frame(5))
	buffer.consume(5)
	assert_false(buffer.insert(_frame(4)))
	assert_false(buffer.insert(_frame(NetTuning.HISTORY_TICKS + 6)))

func test_buffer_defensively_copies_and_clamps_input() -> void:
	var buffer: NetInputBuffer = NetInputBuffer.new()
	var input: InputFrame = _frame(1, 99.0)
	buffer.insert(input)
	input.throttle = 0.0
	assert_eq(buffer.consume(1).throttle, 1.0)
	input = _frame(2, NAN)
	assert_false(buffer.insert(input))

func test_clock_estimates_rtt_and_offset() -> void:
	var clock: NetClock = NetClock.new()
	clock.observe(10.0, 20.05, 10.1)
	assert_almost_eq(clock.rtt_seconds, 0.1, 0.00001)
	assert_almost_eq(clock.server_time(11.0), 21.0, 0.00001)

func test_clock_ignores_invalid_roundtrip() -> void:
	var clock: NetClock = NetClock.new()
	clock.observe(2.0, 4.0, 1.0)
	assert_false(clock.initialized)

func test_interpolation_midpoint_uses_shortest_yaw_arc() -> void:
	var interpolation: NetInterpolator = NetInterpolator.new()
	interpolation.push(1.0, Transform3D(Basis(Vector3.UP, deg_to_rad(179.0)), Vector3.ZERO))
	interpolation.push(1.1, Transform3D(Basis(Vector3.UP, deg_to_rad(-179.0)), Vector3(10, 0, 0)))
	var pose: Transform3D = interpolation.sample(1.05)
	assert_almost_eq(pose.origin.x, 5.0, 0.00001)
	assert_almost_eq(absf(pose.basis.get_euler().y), PI, 0.00001)

func test_interpolation_extrapolation_is_capped_at_50ms() -> void:
	var interpolation: NetInterpolator = NetInterpolator.new()
	interpolation.push(1.0, Transform3D.IDENTITY)
	interpolation.push(1.1, Transform3D(Basis.IDENTITY, Vector3(10, 0, 0)))
	assert_almost_eq(interpolation.sample(9.0).origin.x, 15.0, 0.00001)
	interpolation.push(1.0, Transform3D.IDENTITY)
	assert_almost_eq(interpolation.sample(1.1).origin.x, 10.0, 0.00001)

func test_reconciliation_replays_unacknowledged_inputs_deterministically() -> void:
	var initial: Dictionary = _kart.capture_state()
	var prediction: NetPrediction = NetPrediction.new()
	for tick: int in range(1, 6):
		var input: InputFrame = _frame(tick)
		prediction.record(input)
		_kart.step_input(input, NetTuning.STEP, true)
	var expected: Dictionary = _kart.capture_state()
	prediction.reconcile(_kart, initial, 0)
	assert_eq(_kart.capture_state(), expected)
	prediction.reconcile(_kart, initial, 3)
	assert_eq(prediction.frames.size(), 2)
	assert_eq(prediction.frames[0].tick, 4)

func test_visual_correction_decays_and_large_error_snaps() -> void:
	var prediction: NetPrediction = NetPrediction.new()
	var initial: Dictionary = _kart.capture_state()
	_kart.position.x = 1.0
	prediction.reconcile(_kart, initial, 0)
	assert_almost_eq(prediction.advance_visual(0.05).x, 0.5, 0.00001)
	assert_eq(prediction.advance_visual(0.05), Vector3.ZERO)
	_kart.position.x = 4.0
	prediction.reconcile(_kart, initial, 0)
	assert_eq(prediction.visual_offset, Vector3.ZERO)

func test_debug_delay_and_loss_preserve_reliable_delivery() -> void:
	var conditions: NetDebugConditions = NetDebugConditions.new()
	conditions.latency_seconds = 0.1
	conditions.loss = 1.0
	var calls: Array[int] = []
	conditions.enqueue(0.0, false, func() -> void: calls.append(1))
	conditions.enqueue(0.0, true, func() -> void: calls.append(2))
	conditions.advance(0.09)
	assert_true(calls.is_empty())
	conditions.advance(0.1)
	assert_eq(calls, [2])
	assert_eq(conditions.dropped, 1)

func test_network_hitstop_is_disabled() -> void:
	var stop: HitStop = HitStop.new()
	add_child_autofree(stop)
	assert_false(stop.request(true))
	assert_eq(Engine.time_scale, 1.0)

func test_active_boost_and_slipstream_roundtrip() -> void:
	_kart.request_boost(_kart.tuning.boost_pad_boost, &"boost_pad")
	_kart.get_node("SlipstreamSensor").set("_charge_time", 0.25)
	var source: RaceSnapshot = _snapshot()
	var result: RaceSnapshot = RaceSnapshot.unpack(source.pack())
	assert_not_null(result)
	if result != null:
		assert_eq(result.karts[0]["state"]["boost"]["source"], "boost_pad")
		assert_almost_eq(float(result.karts[0]["state"]["slip_charge"]), 0.25, 0.00001)

func test_replay_suppresses_item_edges_and_preserves_outer_signal_mute() -> void:
	var item: ItemData = load("res://data/items/nitro_can.tres") as ItemData
	_kart.item_slot.set_item(item)
	var frame: InputFrame = _frame(1)
	frame.item = true
	EventBus.set_block_signals(true)
	_kart.step_input(frame, NetTuning.STEP, true)
	assert_true(EventBus.is_blocking_signals())
	EventBus.set_block_signals(false)
	assert_false(_kart.item_slot.consume_use_request())

func test_replica_rejects_external_hits_respawns_and_boosts() -> void:
	_kart.network_replica = true
	var before: Dictionary = _kart.capture_state()
	assert_false(_kart.apply_hit(HitReactor.HitType.SPIN_OUT))
	_kart.begin_respawn()
	_kart.teleport_for_respawn(Transform3D(Basis.IDENTITY, Vector3(100, 0, 0)))
	_kart.request_boost(_kart.tuning.boost_pad_boost, &"boost_pad")
	assert_eq(_kart.capture_state(), before)

func test_state_codec_fixed_size_and_exact_reader_consumption() -> void:
	for active: bool in [false, true]:
		if active:
			_kart.request_boost(_kart.tuning.boost_pad_boost, &"boost_pad")
		var buffer: StreamPeerBuffer = StreamPeerBuffer.new()
		NetStateCodec.write(buffer, _kart.capture_state())
		assert_eq(buffer.get_position(), NetStateCodec.byte_size())
		buffer.seek(0)
		var decoded: Dictionary = NetStateCodec.read(buffer)
		assert_eq(buffer.get_position(), NetStateCodec.byte_size())
		assert_eq(buffer.get_available_bytes(), 0)
		var rewritten: StreamPeerBuffer = StreamPeerBuffer.new()
		NetStateCodec.write(rewritten, decoded)
		assert_eq(rewritten.data_array, buffer.data_array)

func test_respawn_snapshot_applies_teleport_without_replaying_falling_inputs() -> void:
	_kart.begin_respawn()
	_kart.teleport_for_respawn(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.9, -20.0)))
	var state: Dictionary = _kart.capture_state()
	_kart.position = Vector3(41.19, -15.62, -27.70)
	var prediction: NetPrediction = NetPrediction.new()
	prediction.record(_frame(5931))
	prediction.reconcile(_kart, state, 5930)
	assert_eq(_kart.global_position, Vector3(0.0, 0.9, -20.0))
	assert_eq(_kart.get_state(), KartState.RESPAWNING)
	assert_true(prediction.frames.is_empty())
	assert_eq(prediction.visual_offset, Vector3.ZERO)

func test_full_grid_with_max_projectiles_fits_unreliable_budget() -> void:
	var source: RaceSnapshot = _snapshot()
	source.karts.clear()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 1502
	_kart.request_boost(_kart.tuning.boost_pad_boost, &"boost_pad")
	for index: int in range(8):
		_kart.position = Vector3(567.123 + index * 12.345, -6.789 + index, -432.123 - index * 7.891)
		_kart.rotation.y = -2.34567 + index * 0.54321
		var state: Dictionary = _kart.capture_state()
		state["slip_charge"] = 0.12345 + index * 0.01234
		state["slip_exit"] = 0.45678 + index * 0.02345
		state["slip_active"] = true
		for path: String in KartReplayState.COMPONENT_FIELDS:
			for field: String in KartReplayState.COMPONENT_FIELDS[path]:
				if KartReplayState.BOOLEAN_FIELDS.has(field):
					state["components"][path][field] = true
				elif not KartReplayState.INTEGER_FIELDS.has(field):
					state["components"][path][field] = rng.randf_range(0.1, 2.0)
		source.karts.append({"state": state, "ack": 321 + index, "lap": 2, "rank": index + 1,
			"checkpoint": 3, "item": 2, "roulette": 0.12345, "cooldown": 0.56789,
			"finish": 123.45678 + index, "progress": 987.65432 + index})
	for index: int in range(ItemManager.DEFAULT_MAX_ACTIVE_PROJECTILES):
		source.projectiles.append({"id": 12345 + index, "item": index % 4 + 1, "owner": index % 8,
			"pose": Transform3D(Basis.from_euler(Vector3(0.12345, index * 0.23456, -0.34567)),
				Vector3(432.123 + index * 6.789, 2.345 + index, -567.891 - index * 3.456))})
	var bytes: PackedByteArray = source.pack()
	print("FULL_SNAPSHOT_BYTES=%d" % bytes.size())
	assert_lte(bytes.size(), 1200)
	assert_lte(var_to_bytes([bytes]).size() + NetTuning.RPC_OVERHEAD_BYTES, NetTuning.MAX_UNRELIABLE_BYTES)
	var result: RaceSnapshot = RaceSnapshot.unpack(bytes)
	assert_not_null(result)
	if result == null: return
	assert_eq(result.karts.size(), 8)
	assert_eq(result.projectiles.size(), 16)
	for index: int in range(8):
		var before: Dictionary = source.karts[index]["state"]
		var after: Dictionary = result.karts[index]["state"]
		for axis: int in range(3):
			assert_almost_eq(float(after["position"][axis]), float(before["position"][axis]), 0.0051)
		assert_almost_eq(float(after["rotation"][1]), float(before["rotation"][1]), 0.00051)
		for path: String in KartReplayState.COMPONENT_FIELDS:
			for field: String in KartReplayState.COMPONENT_FIELDS[path]:
				var expected: Variant = before["components"][path][field]
				if expected is float:
					assert_almost_eq(float(after["components"][path][field]), float(expected), 0.00001)
				else:
					assert_eq(after["components"][path][field], expected)
		assert_eq(after["boost"]["source"], before["boost"]["source"])
		for key: String in NetStateCodec.BOOST_FLOAT_FIELDS:
			assert_almost_eq(float(after["boost"][key]), float(before["boost"][key]), 0.00001)
		for key: String in NetStateCodec.SLIP_FLOAT_FIELDS:
			assert_almost_eq(float(after[key]), float(before[key]), 0.00001)
		assert_true(after["slip_active"])
	for index: int in range(16):
		assert_eq(result.projectiles[index]["id"], source.projectiles[index]["id"])
		assert_eq(result.projectiles[index]["owner"], source.projectiles[index]["owner"])
		var before: Transform3D = source.projectiles[index]["pose"]
		var after: Transform3D = result.projectiles[index]["pose"]
		assert_lt(after.origin.distance_to(before.origin), 0.009)
		assert_lt(after.basis.get_rotation_quaternion().angle_to(before.basis.get_rotation_quaternion()), 0.002)

func test_unreliable_delivery_rejects_oversize_and_reserves_rpc_framing() -> void:
	var session: NetSession = NetSession.new()
	add_child_autofree(session)
	var bytes: PackedByteArray = []
	bytes.resize(NetTuning.MAX_UNRELIABLE_BYTES)
	session.send(&"_snapshot", 0, [bytes], false)
	session.conditions.advance(NetSession.now() + 1.0)
	assert_push_error("Unreliable RPC _snapshot exceeds 1200 bytes")
	# The payload alone fits, but RPC arguments and command framing do not.
	bytes.resize(NetTuning.MAX_UNRELIABLE_BYTES - 1)
	session._deliver(&"_snapshot", 0, [bytes], false)
	assert_push_error("Unreliable RPC _snapshot exceeds 1200 bytes")
	bytes.resize(1000)
	session._deliver(&"_snapshot", 0, [bytes], false)
	assert_push_error_count(2)
	bytes.resize(2400)
	session._deliver(&"_event", 0, ["results", bytes], true)
	assert_push_error_count(2)

func test_snapshot_rejects_unbounded_decompression_size() -> void:
	var bytes: PackedByteArray = _snapshot().pack()
	bytes.encode_u16(1, 65535)
	assert_null(RaceSnapshot.unpack(bytes))
	bytes.encode_u16(1, 0)
	assert_null(RaceSnapshot.unpack(bytes))

func test_start_retry_targets_only_unacknowledged_peers_and_stops_after_ack() -> void:
	var session: RetrySession = RetrySession.new()
	add_child_autofree(session)
	session.players = [{"peer": 1}, {"peer": 2}, {"peer": 3}]
	assert_has_method(session, "retry_start")
	if not session.has_method("retry_start"):
		return
	session.call("retry_start")
	assert_true(session.targets.is_empty())
	session.started = true
	session._mark_loaded(1)
	session._mark_loaded(2)
	session.call("retry_start")
	session.call("retry_start")
	assert_eq(session.targets, [3, 3])
	session._mark_loaded(3)
	assert_true(session.running)
	session.call("retry_start")
	assert_eq(session.targets, [3, 3])
