extends GutTest

## Spec items C and D coverage, split out of test_net_race_adapter.gd to
## keep both files under the 400-line rule. Same in-process adapter fixture.
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

## Spec item D, delivery order 1: an unreliable RACING-state snapshot can
## arrive before the reliable 3-2-1 tick events under real latency. The
## snapshot's own countdown-zero emission must route through NetRace's
## descending-value filter so the late reliable ticks (arriving afterwards)
## cannot replay 3/2/1 past GO.
func test_racing_snapshot_before_reliable_ticks_suppresses_late_ticks() -> void:
	watch_signals(EventBus)
	_manager.network_replica = true
	_manager.apply_network_state(RaceState.RACING)
	assert_signal_emit_count(EventBus, "countdown_tick", 1)
	_manager.network._receive_event("countdown_tick", [3])
	_manager.network._receive_event("countdown_tick", [2])
	_manager.network._receive_event("countdown_tick", [1])
	assert_signal_emit_count(EventBus, "countdown_tick", 1)

## Spec item D, delivery order 2: the ordinary case where reliable 3-2-1-0
## ticks arrive first must not have its zero duplicated when the (redundant)
## RACING-state snapshot transition arrives afterwards.
func test_reliable_ticks_before_racing_snapshot_do_not_duplicate_zero() -> void:
	watch_signals(EventBus)
	_manager.network_replica = true
	_manager.network._receive_event("countdown_tick", [3])
	_manager.network._receive_event("countdown_tick", [2])
	_manager.network._receive_event("countdown_tick", [1])
	_manager.network._receive_event("countdown_tick", [0])
	assert_signal_emit_count(EventBus, "countdown_tick", 4)
	_manager.apply_network_state(RaceState.RACING)
	assert_signal_emit_count(EventBus, "countdown_tick", 4)

## Spec item C: a snapshot too large for one unreliable packet is split into
## several chunks; NetRace must reassemble them into one logical snapshot
## regardless of arrival order, never partially applying a subset.
func test_chunked_snapshot_assembles_regardless_of_arrival_order() -> void:
	var state: NetRaceState = NetRaceState.new(_manager)
	var snapshot: RaceSnapshot = state.capture(9, [0, 0])
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 4477
	for index: int in range(64):
		snapshot.projectiles.append({"id": 5000 + index, "item": index % 4 + 1, "owner": index % 2,
			"pose": Transform3D(Basis.from_euler(Vector3(rng.randf_range(-PI, PI), rng.randf_range(-PI, PI), rng.randf_range(-PI, PI))),
				Vector3(rng.randf_range(-600.0, 600.0), rng.randf_range(-10.0, 10.0), rng.randf_range(-600.0, 600.0)))})
	var chunks: Array[PackedByteArray] = snapshot.pack_chunked()
	assert_gt(chunks.size(), 1, "2 karts + 64 items must not fit in one unreliable packet")
	var unpacked: Array[RaceSnapshot] = []
	for chunk: PackedByteArray in chunks:
		unpacked.append(RaceSnapshot.unpack(chunk))
	unpacked.reverse() # Arrival order is not guaranteed by an unordered/unreliable channel.
	for one: RaceSnapshot in unpacked:
		_manager.network._receive_snapshot(one)
	var pending: RaceSnapshot = _manager.network.get("_pending")
	assert_not_null(pending)
	if pending == null:
		return
	assert_eq(pending.karts.size(), 2)
	assert_eq(pending.projectiles.size(), 64)
	for index: int in range(2):
		assert_eq(int(pending.karts[index]["slot"]), index)

## A chunk lost to unreliable delivery must drop only that tick's snapshot,
## never crash or corrupt a later, fully-delivered tick's assembly.
func test_missing_chunk_drops_only_that_ticks_snapshot() -> void:
	var state: NetRaceState = NetRaceState.new(_manager)
	var incomplete: RaceSnapshot = state.capture(9, [0, 0])
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 8899
	for index: int in range(64):
		incomplete.projectiles.append({"id": 6000 + index, "item": 1, "owner": 0,
			"pose": Transform3D(Basis.from_euler(Vector3(rng.randf_range(-PI, PI), rng.randf_range(-PI, PI), rng.randf_range(-PI, PI))),
				Vector3(rng.randf_range(-600.0, 600.0), rng.randf_range(-10.0, 10.0), rng.randf_range(-600.0, 600.0)))})
	var incomplete_chunks: Array[PackedByteArray] = incomplete.pack_chunked()
	assert_gt(incomplete_chunks.size(), 1)
	_manager.network._receive_snapshot(RaceSnapshot.unpack(incomplete_chunks[0])) # Drop the rest.
	assert_null(_manager.network.get("_pending"))
	var complete: RaceSnapshot = state.capture(12, [0, 0])
	_manager.network._receive_snapshot(complete)
	var pending: RaceSnapshot = _manager.network.get("_pending")
	assert_not_null(pending)
	if pending != null:
		assert_eq(pending.tick, 12)
