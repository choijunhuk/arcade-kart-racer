extends GutTest

## Spec §14.4: pure ranking with fake progress providers, plus TrackShortcut's
## progress interpolation used as a substitute progress source.


func test_finished_karts_rank_before_unfinished_by_finish_time() -> void:
	var order: Array[int] = PositionTracker.rank_karts(
		[], [1, 2, 3],
		{1: 10.0, 2: 999.0, 3: 5.0},
		{1: false, 2: true, 3: true},
		{2: 12.0, 3: 8.0},
		0.5,
	)
	# 3 finished first (8.0s), then 2 (12.0s), then 1 (unfinished, only entry).
	assert_eq(order, [3, 2, 1])


func test_unfinished_karts_rank_by_progress_descending() -> void:
	var order: Array[int] = PositionTracker.rank_karts(
		[], [1, 2, 3],
		{1: 5.0, 2: 20.0, 3: 12.0},
		{1: false, 2: false, 3: false},
		{},
		0.5,
	)
	assert_eq(order, [2, 3, 1])


func test_hysteresis_keeps_previous_order_for_near_equal_progress() -> void:
	var previous: Array[int] = [1, 2]
	var order: Array[int] = PositionTracker.rank_karts(
		previous, [1, 2],
		{1: 10.0, 2: 10.3}, # gap 0.3m < 0.5m hysteresis
		{1: false, 2: false},
		{},
		0.5,
	)
	assert_eq(order, [1, 2])


func test_hysteresis_still_swaps_once_the_gap_exceeds_the_threshold() -> void:
	var previous: Array[int] = [1, 2]
	var order: Array[int] = PositionTracker.rank_karts(
		previous, [1, 2],
		{1: 10.0, 2: 10.6}, # gap 0.6m > 0.5m hysteresis
		{1: false, 2: false},
		{},
		0.5,
	)
	assert_eq(order, [2, 1])


func test_new_kart_is_appended_after_previously_known_order() -> void:
	var previous: Array[int] = [1]
	var order: Array[int] = PositionTracker.rank_karts(
		previous, [1, 2],
		{1: 5.0, 2: 1.0},
		{1: false, 2: false},
		{},
		0.5,
	)
	assert_eq(order, [1, 2])


func test_shortcut_progress_at_interpolates_between_entry_and_exit_offset() -> void:
	var shortcut: TrackShortcut = (load("res://track/elements/shortcut.tscn") as PackedScene).instantiate() as TrackShortcut
	add_child_autofree(shortcut)
	shortcut.entry_offset = 100.0
	shortcut.exit_offset = 140.0
	var alt_curve: Path3D = Path3D.new()
	var curve: Curve3D = Curve3D.new()
	curve.add_point(Vector3(0, 0, 0))
	curve.add_point(Vector3(20, 0, 0))
	alt_curve.curve = curve
	shortcut.add_child(alt_curve)
	shortcut.alt_curve = alt_curve

	var midpoint_progress: float = shortcut.progress_at(alt_curve.to_global(Vector3(10, 0, 0)))
	assert_almost_eq(midpoint_progress, 120.0, 0.5)
	var end_progress: float = shortcut.progress_at(alt_curve.to_global(Vector3(20, 0, 0)))
	assert_almost_eq(end_progress, 140.0, 0.5)


func test_shortcut_progress_at_unwraps_across_the_lap_seam() -> void:
	var shortcut: TrackShortcut = (load("res://track/elements/shortcut.tscn") as PackedScene).instantiate() as TrackShortcut
	add_child_autofree(shortcut)
	var lap_length: float = 200.0
	shortcut.entry_offset = 190.0
	shortcut.exit_offset = 10.0 # rejoins past the start/finish line
	var alt_curve: Path3D = Path3D.new()
	var curve: Curve3D = Curve3D.new()
	curve.add_point(Vector3(0, 0, 0))
	curve.add_point(Vector3(20, 0, 0))
	alt_curve.curve = curve
	shortcut.add_child(alt_curve)
	shortcut.alt_curve = alt_curve

	# Unwrapped exit = 10 + 200 = 210. Midpoint = lerp(190, 210, 0.5) = 200,
	# which wraps to 0.
	var midpoint_progress: float = shortcut.progress_at(alt_curve.to_global(Vector3(10, 0, 0)), lap_length)
	assert_almost_eq(midpoint_progress, 0.0, 0.5)
	var end_progress: float = shortcut.progress_at(alt_curve.to_global(Vector3(20, 0, 0)), lap_length)
	assert_almost_eq(end_progress, 10.0, 0.5)


func _build_progress_test_circle(radius: float, segments: int) -> RacingLine:
	var line: RacingLine = RacingLine.new()
	var curve: Curve3D = Curve3D.new()
	for index: int in range(segments + 1):
		var angle: float = TAU * float(index) / float(segments)
		curve.add_point(Vector3(radius * cos(angle), 0.0, radius * sin(angle)))
	line.curve = curve
	line.bake_interval = 1.0
	add_child_autofree(line)
	return line


func test_progress_continues_monotonically_after_leaving_a_shortcut() -> void:
	var racing_line: RacingLine = _build_progress_test_circle(50.0, 120)
	var lap_length: float = racing_line.length()

	var tracker: PositionTracker = PositionTracker.new()
	add_child_autofree(tracker)
	tracker._racing_line = racing_line
	tracker._checkpoints = []
	tracker._lap_length = lap_length

	var kart: KartController = (load("res://kart/kart.tscn") as PackedScene).instantiate()
	add_child_autofree(kart)
	tracker.register_kart(kart)

	var entry_offset: float = lap_length * 0.1
	var exit_offset: float = lap_length * 0.6

	# Prime `cached_offset` at the entry point via a normal (non-shortcut) update.
	kart.global_position = racing_line.sample(entry_offset)
	tracker._update_all()
	var progress_before_shortcut: float = tracker.get_progress(kart)

	var shortcut: TrackShortcut = (load("res://track/elements/shortcut.tscn") as PackedScene).instantiate() as TrackShortcut
	add_child_autofree(shortcut)
	shortcut.entry_offset = entry_offset
	shortcut.exit_offset = exit_offset
	var alt_curve: Path3D = shortcut.get_node("AltCurve") as Path3D
	var alt: Curve3D = Curve3D.new()
	alt.add_point(Vector3(0, 0, 0))
	alt.add_point(Vector3(20, 0, 0))
	alt_curve.curve = alt
	shortcut.alt_curve = alt_curve

	tracker._on_shortcut_entered(kart, shortcut)
	kart.global_position = alt_curve.to_global(Vector3(10, 0, 0))
	tracker._update_all()
	var progress_mid_shortcut: float = tracker.get_progress(kart)
	assert_gt(progress_mid_shortcut, progress_before_shortcut)

	# Rejoin the main line far from the entry point (well outside the
	# racing line's hinted-search window), the way a real shortcut would.
	kart.global_position = alt_curve.to_global(Vector3(20, 0, 0))
	tracker._on_shortcut_exited(kart, shortcut)
	kart.global_position = racing_line.sample(exit_offset)
	tracker._update_all()
	var progress_after_exit: float = tracker.get_progress(kart)

	assert_gt(progress_after_exit, progress_mid_shortcut, "progress must not jump backwards once the kart rejoins the main line")
