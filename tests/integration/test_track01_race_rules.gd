extends GutTest

## Spec §24 Phase 4 DoD, exercised on the actual Track 01 greybox: wrong-way
## detection toggles on/off, skipping a checkpoint withholds the lap, and
## falling off the cliff corner respawns at the last passed checkpoint.

const TRACK_SCENE: String = "res://track/tracks/track_01_ridgeline_circuit/track_01_ridgeline_circuit.tscn"
const WRONG_WAY_DWELL_TICKS: int = 91


func _make_context() -> Dictionary:
	var track: Node = (load(TRACK_SCENE) as PackedScene).instantiate()
	add_child_autofree(track)
	var lap_tracker: LapTracker = LapTracker.new()
	lap_tracker.total_laps = 3
	add_child_autofree(lap_tracker)
	lap_tracker.setup(track as TrackRoot)
	var kart: KartController = (load("res://kart/kart.tscn") as PackedScene).instantiate()
	add_child_autofree(kart)
	lap_tracker.register_kart(kart)
	return {"track": track, "tracker": lap_tracker, "kart": kart}


func test_driving_backward_on_track01_sets_and_clears_wrong_way() -> void:
	var context: Dictionary = _make_context()
	var tracker: LapTracker = context["tracker"]
	var kart: KartController = context["kart"]
	var racing_line: RacingLine = (context["track"] as TrackRoot).get_racing_line()
	var offset: float = racing_line.length() * 0.1
	kart.global_position = racing_line.sample(offset)
	kart.look_at(kart.global_position + (-racing_line.tangent_at(offset)), Vector3.UP)

	for _tick: int in range(WRONG_WAY_DWELL_TICKS):
		tracker._physics_process(1.0 / 60.0)
	assert_true(tracker.is_wrong_way(kart))

	kart.look_at(kart.global_position + racing_line.tangent_at(offset), Vector3.UP)
	tracker._physics_process(1.0 / 60.0)
	assert_false(tracker.is_wrong_way(kart))


func test_skipping_a_checkpoint_on_track01_withholds_the_lap() -> void:
	var context: Dictionary = _make_context()
	var tracker: LapTracker = context["tracker"]
	var kart: KartController = context["kart"]
	var checkpoints: Array[Checkpoint] = (context["track"] as TrackRoot).get_checkpoints()
	assert_gte(checkpoints.size(), 8)
	# Skip checkpoint 1 entirely; jump straight to the last checkpoint, then
	# try to cross the start/finish line.
	checkpoints[checkpoints.size() - 1].body_passed.emit(kart, checkpoints.size() - 1)
	checkpoints[0].body_passed.emit(kart, 0)
	assert_eq(tracker.get_lap(kart), 0)


func test_falling_off_the_cliff_respawns_at_last_passed_checkpoint() -> void:
	var context: Dictionary = _make_context()
	var track: TrackRoot = context["track"]
	var tracker: LapTracker = context["tracker"]
	var kart: KartController = context["kart"]
	var checkpoints: Array[Checkpoint] = track.get_checkpoints()
	var racing_line: RacingLine = track.get_racing_line()

	# Pass checkpoints 1..6 (not the finish line yet) so "last passed" is cp6.
	for index: int in range(1, 7):
		checkpoints[index].body_passed.emit(kart, index)
	assert_eq(tracker.get_last_checkpoint_index(kart), 6)

	# Simulate the cliff fall: drop the kart below the world, then resolve a
	# respawn transform the same way RespawnSystem would on a KillZone hit.
	kart.global_position = Vector3(0.0, -50.0, 0.0)
	var respawn_transform: Transform3D = RespawnSystem.resolve_respawn_transform(kart, tracker, racing_line, [kart])
	var expected_point: Marker3D = checkpoints[6].get_respawn_point()
	assert_almost_eq(respawn_transform.origin.distance_to(expected_point.global_position), 0.0, 1.0)
