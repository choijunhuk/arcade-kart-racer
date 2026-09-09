extends GutTest

## Spec item B regression: `RacingLine.offset_at()` is ambiguously tied right
## at the start/finish seam (the closing baked point duplicates the first
## one), and an unhinted, fresh-every-tick search can snap the reported
## offset to the wrong side early. That previously made the follower's own
## look-ahead target (`sample(offset + LOOKAHEAD_DISTANCE)`) land far from
## where it should — sometimes effectively behind the kart — driving
## spurious corner braking and a near-stationary crawl right before the
## finish line (see native evidence at ~1440-1470m of a ~1499m lap).
## `ScriptedRaceInputProvider._current_offset()` now hints the search with
## its own previous tick's offset so it stays anchored on the correct side.


func _make_context() -> Dictionary:
	var track: TrackRoot = (load("res://track/tracks/test_loop/test_loop.tscn") as PackedScene).instantiate()
	add_child_autofree(track)
	var kart: KartController = (load("res://kart/kart.tscn") as PackedScene).instantiate()
	add_child_autofree(kart)
	var racing_line: RacingLine = track.get_racing_line()
	var provider: ScriptedRaceInputProvider = ScriptedRaceInputProvider.new(kart, racing_line)
	return {"kart": kart, "racing_line": racing_line, "provider": provider}


func test_lookahead_target_stays_ahead_of_the_kart_across_the_seam() -> void:
	var context: Dictionary = _make_context()
	var kart: KartController = context["kart"]
	var racing_line: RacingLine = context["racing_line"]
	var provider: ScriptedRaceInputProvider = context["provider"]
	var length: float = racing_line.length()
	# Sweep the kart's true racing-line offset from 2m before the seam to 2m
	# after it, one small step at a time (as a real race tick-to-tick motion
	# would), and check the follower's own look-ahead target against the
	# ground-truth target computed directly from the known true offset.
	for step: int in range(-10, 11):
		var true_offset: float = fposmod(float(step) * 0.2, length)
		kart.global_transform = Transform3D(Basis.IDENTITY, racing_line.sample(true_offset))
		var reported_offset: float = provider._current_offset()
		var target: Vector3 = racing_line.sample(reported_offset + ScriptedRaceInputProvider.LOOKAHEAD_DISTANCE)
		var expected_target: Vector3 = racing_line.sample(true_offset + ScriptedRaceInputProvider.LOOKAHEAD_DISTANCE)
		assert_lt(target.distance_to(expected_target), 1.0,
			"step %d (true_offset=%.2f): look-ahead target drifted from the true lookahead point" % [step, true_offset])


func test_current_offset_hint_keeps_full_lap_progress_monotonic() -> void:
	var context: Dictionary = _make_context()
	var kart: KartController = context["kart"]
	var racing_line: RacingLine = context["racing_line"]
	var provider: ScriptedRaceInputProvider = context["provider"]
	var length: float = racing_line.length()
	var unwrapped_previous: float = -1.0
	var total_steps: int = int(length / 0.5) + 4
	for step: int in range(total_steps):
		var true_offset: float = fposmod(float(step) * 0.5, length)
		kart.global_transform = Transform3D(Basis.IDENTITY, racing_line.sample(true_offset))
		var reported_offset: float = provider._current_offset()
		var unwrapped: float = reported_offset
		while unwrapped_previous >= 0.0 and unwrapped < unwrapped_previous - length * 0.5:
			unwrapped += length
		if unwrapped_previous >= 0.0:
			assert_gt(unwrapped, unwrapped_previous - 0.5,
				"step %d: reported offset moved backward across the seam" % step)
		unwrapped_previous = unwrapped
