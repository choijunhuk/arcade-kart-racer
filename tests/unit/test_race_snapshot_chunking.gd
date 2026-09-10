extends GutTest

## Spec item C: `RaceSnapshot.pack_chunked()` bounded packetization. Split
## out of test_netcode.gd to keep both files under the 400-line rule.

var _kart: KartController

func before_each() -> void:
	_kart = (load("res://kart/kart.tscn") as PackedScene).instantiate() as KartController
	add_child_autofree(_kart)
	_kart.set_physics_process(false)

func _snapshot() -> RaceSnapshot:
	var snapshot: RaceSnapshot = RaceSnapshot.new()
	snapshot.tick = 42
	snapshot.race_state = RaceState.RACING
	snapshot.karts.append({"state": _kart.capture_state(), "ack": 39, "lap": 2, "rank": 3})
	return snapshot

## A busy 12-kart race with many active items exceeds the unreliable budget
## as one packet (spec item C): `pack_chunked()` must split it into several
## chunks that each individually fit, and losslessly cover every kart slot
## and item once between them (never silently dropped for size).
func test_pack_chunked_splits_twelve_karts_and_forty_items_within_budget() -> void:
	var source: RaceSnapshot = _snapshot()
	source.karts.clear()
	# High-entropy per-kart/per-item data, matching
	# `test_full_grid_with_max_projectiles_fits_unreliable_budget`'s rigor:
	# a busy race's actual component timers vary per kart, so a synthetic
	# fixture built from repetitive/near-identity values would compress far
	# better than real traffic and could misleadingly fit in one packet.
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 90210
	for index: int in range(12):
		_kart.position = Vector3(567.123 + index * 12.345, -6.789 + index, -432.123 - index * 7.891)
		_kart.rotation.y = -2.34567 + index * 0.54321
		var state: Dictionary = _kart.capture_state()
		state["slip_charge"] = rng.randf_range(0.1, 2.0)
		state["slip_exit"] = rng.randf_range(0.1, 2.0)
		state["slip_active"] = true
		for path: String in KartReplayState.COMPONENT_FIELDS:
			for field: String in KartReplayState.COMPONENT_FIELDS[path]:
				if KartReplayState.BOOLEAN_FIELDS.has(field):
					state["components"][path][field] = true
				elif not KartReplayState.INTEGER_FIELDS.has(field):
					state["components"][path][field] = rng.randf_range(0.1, 2.0)
		source.karts.append({"state": state, "ack": 321 + index, "lap": 1,
			"rank": index + 1, "checkpoint": 2, "item": 0, "roulette": rng.randf_range(0.0, 1.0),
			"cooldown": rng.randf_range(0.0, 1.0), "finish": -1.0, "progress": rng.randf_range(0.0, 2000.0)})
	for index: int in range(40):
		source.projectiles.append({"id": 9000 + index, "item": index % 4 + 1, "owner": index % 12,
			"pose": Transform3D(Basis.from_euler(Vector3(rng.randf_range(-PI, PI), rng.randf_range(-PI, PI), rng.randf_range(-PI, PI))),
				Vector3(rng.randf_range(-600.0, 600.0), rng.randf_range(-10.0, 10.0), rng.randf_range(-600.0, 600.0)))})
	var chunks: Array[PackedByteArray] = source.pack_chunked()
	assert_gt(chunks.size(), 1, "12 karts + 40 items must not fit in one unreliable packet")
	var seen_karts: Dictionary[int, bool] = {}
	var seen_items: Dictionary[int, bool] = {}
	for chunk: PackedByteArray in chunks:
		assert_lte(var_to_bytes([chunk]).size() + NetTuning.RPC_OVERHEAD_BYTES, NetTuning.MAX_UNRELIABLE_BYTES)
		var unpacked: RaceSnapshot = RaceSnapshot.unpack(chunk)
		assert_not_null(unpacked)
		if unpacked == null:
			continue
		assert_eq(unpacked.chunk_count, chunks.size())
		for row: Dictionary in unpacked.karts:
			seen_karts[int(row["slot"])] = true
		for row: Dictionary in unpacked.projectiles:
			seen_items[int(row["id"])] = true
	assert_eq(seen_karts.size(), 12)
	assert_eq(seen_items.size(), 40)

## A roster small enough to fit one packet must not be split (`pack()` and a
## single-element `pack_chunked()` agree, chunk_count 1).
func test_pack_chunked_returns_one_chunk_for_a_small_snapshot() -> void:
	var source: RaceSnapshot = _snapshot()
	var chunks: Array[PackedByteArray] = source.pack_chunked()
	assert_eq(chunks.size(), 1)
	var unpacked: RaceSnapshot = RaceSnapshot.unpack(chunks[0])
	assert_not_null(unpacked)
	if unpacked != null:
		assert_eq(unpacked.chunk_count, 1)
		assert_eq(unpacked.chunk_index, 0)
		assert_eq(unpacked.karts.size(), 1)
