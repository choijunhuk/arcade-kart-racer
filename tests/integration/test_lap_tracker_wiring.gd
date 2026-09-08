extends GutTest

## Wires LapTracker to a real track's Checkpoints/RacingLine and checks the
## event surface: sequential passes advance the lap, a skipped checkpoint
## withholds it, and sustained backward driving flags wrong_way.

const WRONG_WAY_DWELL_TICKS: int = 91 # > 1.5s at 60Hz with margin


func _make_tracker() -> Dictionary:
	var track: Node = (load("res://track/tracks/test_loop/test_loop.tscn") as PackedScene).instantiate()
	add_child_autofree(track)
	var tracker: LapTracker = LapTracker.new()
	tracker.total_laps = 3
	add_child_autofree(tracker)
	tracker.setup(track)
	var kart: KartController = (load("res://kart/kart.tscn") as PackedScene).instantiate()
	add_child_autofree(kart)
	tracker.register_kart(kart)
	return {"track": track, "tracker": tracker, "kart": kart}


func test_passing_all_checkpoints_in_order_completes_a_lap() -> void:
	var context: Dictionary = _make_tracker()
	var tracker: LapTracker = context["tracker"]
	var kart: KartController = context["kart"]
	var checkpoints: Array[Checkpoint] = (context["track"] as TrackRoot).get_checkpoints()
	for index: int in range(1, checkpoints.size()):
		checkpoints[index].body_passed.emit(kart, index)
	checkpoints[0].body_passed.emit(kart, 0)
	assert_eq(tracker.get_lap(kart), 1)


func test_skipping_a_checkpoint_withholds_the_lap() -> void:
	var context: Dictionary = _make_tracker()
	var tracker: LapTracker = context["tracker"]
	var kart: KartController = context["kart"]
	var checkpoints: Array[Checkpoint] = (context["track"] as TrackRoot).get_checkpoints()
	# Skip checkpoint 1 entirely; jump straight to the last checkpoint.
	checkpoints[checkpoints.size() - 1].body_passed.emit(kart, checkpoints.size() - 1)
	checkpoints[0].body_passed.emit(kart, 0)
	assert_eq(tracker.get_lap(kart), 0)


func test_driving_backward_sets_wrong_way_after_dwell_then_clears() -> void:
	var context: Dictionary = _make_tracker()
	var tracker: LapTracker = context["tracker"]
	var kart: KartController = context["kart"]
	var racing_line: RacingLine = (context["track"] as TrackRoot).get_racing_line()
	var offset: float = racing_line.length() * 0.1
	kart.global_position = racing_line.sample(offset)
	# Face directly opposite the racing line's tangent at this offset.
	var backward: Vector3 = -racing_line.tangent_at(offset)
	kart.look_at(kart.global_position + backward, Vector3.UP)

	for _tick: int in range(WRONG_WAY_DWELL_TICKS):
		tracker._physics_process(1.0 / 60.0)
	assert_true(tracker.is_wrong_way(kart))

	kart.look_at(kart.global_position + racing_line.tangent_at(offset), Vector3.UP)
	tracker._physics_process(1.0 / 60.0)
	assert_false(tracker.is_wrong_way(kart))
