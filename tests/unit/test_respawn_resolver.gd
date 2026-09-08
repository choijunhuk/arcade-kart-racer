extends GutTest

## Spec §14.5: racing-line-oriented respawn transform, stepping back along the
## line when the last-checkpoint spot is occupied by another kart.


func _make_context() -> Dictionary:
	var track: Node = (load("res://track/tracks/test_loop/test_loop.tscn") as PackedScene).instantiate()
	add_child_autofree(track)
	var tracker: LapTracker = LapTracker.new()
	add_child_autofree(tracker)
	tracker.setup(track)
	var kart: KartController = (load("res://kart/kart.tscn") as PackedScene).instantiate()
	add_child_autofree(kart)
	tracker.register_kart(kart)
	return {"track": track, "tracker": tracker, "kart": kart}


func test_resolves_to_last_checkpoints_respawn_point_when_unoccupied() -> void:
	var context: Dictionary = _make_context()
	var track: TrackRoot = context["track"]
	var tracker: LapTracker = context["tracker"]
	var kart: KartController = context["kart"]
	var racing_line: RacingLine = track.get_racing_line()
	var expected_point: Marker3D = tracker.get_respawn_point(kart)

	var result: Transform3D = RespawnSystem.resolve_respawn_transform(kart, tracker, racing_line, [kart])
	assert_almost_eq(result.origin.distance_to(expected_point.global_position), 0.0, 1.0)


func test_steps_back_when_the_spot_is_occupied() -> void:
	var context: Dictionary = _make_context()
	var track: TrackRoot = context["track"]
	var tracker: LapTracker = context["tracker"]
	var kart: KartController = context["kart"]
	var racing_line: RacingLine = track.get_racing_line()
	var expected_point: Marker3D = tracker.get_respawn_point(kart)

	var blocker: KartController = (load("res://kart/kart.tscn") as PackedScene).instantiate()
	add_child_autofree(blocker)
	blocker.global_position = expected_point.global_position

	var result: Transform3D = RespawnSystem.resolve_respawn_transform(kart, tracker, racing_line, [kart, blocker])
	assert_gt(result.origin.distance_to(expected_point.global_position), 1.0)
