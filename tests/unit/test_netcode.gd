extends GutTest

var _kart: KartController

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
