extends GutTest

## Phase 18k item 12: ContentTrack.shortcut() must give every bypassed
## checkpoint its own rejoin slot (exit + SHORTCUT_GATE_MARGIN * n) so two or
## more bypassed gates keep strictly increasing offsets, and the track
## validator's shortcut invariants must report the failure modes by cause.

const VALIDATOR: GDScript = preload("res://track/track_validator.gd")


func _track(id: String) -> ContentTrack:
	var data: TrackData = load("res://data/tracks/%s.tres" % id) as TrackData
	var track: ContentTrack = data.scene.instantiate() as ContentTrack
	add_child_autofree(track)
	return track


func _gate_offsets(track: ContentTrack) -> Array[float]:
	var offsets: Array[float] = []
	for gate: Checkpoint in track.get_checkpoints():
		offsets.append(track.line.offset_at(gate.global_position))
	return offsets


## Spans from just before gate 2 to just past gate 3 so exactly two gates are
## bypassed, then re-runs the offset assignment Track._ready() normally does
## after build_theme().
func _two_gate_shortcut(track: ContentTrack) -> float:
	var before: Array[float] = _gate_offsets(track)
	var entry: float = before[2] - 5.0
	var exit: float = before[3] + 5.0
	track.shortcut("TwoGateShortcut", entry, exit, [track.line.sample(entry), track.line.sample(exit)], 20.0, false)
	track._configure_checkpoints()
	return exit


func test_validator_margin_mirrors_content_track_margin() -> void:
	assert_eq(VALIDATOR.REJOIN_GATE_MARGIN, ContentTrack.SHORTCUT_GATE_MARGIN)


func test_shortcut_bypassing_two_checkpoints_spaces_their_rejoin_gates() -> void:
	var track: ContentTrack = _track("track_03")
	var exit: float = _two_gate_shortcut(track)
	var after: Array[float] = _gate_offsets(track)
	assert_almost_eq(after[2], exit + ContentTrack.SHORTCUT_GATE_MARGIN, 1.0, "first bypassed gate sits one margin past rejoin")
	assert_almost_eq(after[3], exit + ContentTrack.SHORTCUT_GATE_MARGIN * 2.0, 1.0, "second bypassed gate sits two margins past rejoin")
	assert_gt(after[3], after[2], "bypassed gates must not collapse onto the same offset")
	for index: int in range(1, after.size()):
		assert_gt(after[index], after[index - 1], "checkpoint offsets stay strictly increasing at %d" % index)
	assert_eq(VALIDATOR.shortcut_errors(track).size(), 0, "validator accepts spaced rejoin gates")


func test_validator_reports_collapsed_rejoin_gates_by_shortcut_name() -> void:
	var track: ContentTrack = _track("track_03")
	_two_gate_shortcut(track)
	var gates: Array[Checkpoint] = track.get_checkpoints()
	# Simulate the pre-fix behaviour: both bypassed gates on the same rejoin slot.
	gates[3].global_transform = gates[2].global_transform
	track._configure_checkpoints()
	var errors: PackedStringArray = VALIDATOR.shortcut_errors(track)
	assert_eq(errors.size(), 1)
	if errors.is_empty():
		return
	assert_string_contains(errors[0], "TwoGateShortcut")
	assert_string_contains(errors[0], "collapsed")


func test_validator_reports_entry_after_exit() -> void:
	var track: ContentTrack = _track("track_03")
	var inverted: TrackShortcut = TrackShortcut.new()
	inverted.name = "Inverted"
	inverted.entry_offset = 50.0
	inverted.exit_offset = 10.0
	var trigger: Area3D = Area3D.new()
	trigger.name = "TriggerArea"
	inverted.add_child(trigger)
	track.get_node("Shortcuts").add_child(inverted)
	var errors: PackedStringArray = VALIDATOR.shortcut_errors(track)
	assert_eq(errors.size(), 1)
	if errors.is_empty():
		return
	assert_string_contains(errors[0], "Inverted")
	assert_string_contains(errors[0], "entry_offset")


func test_shipped_tracks_satisfy_the_shortcut_invariants() -> void:
	for id: String in ["track_02", "track_04"]:
		var track: ContentTrack = _track(id)
		assert_gt(track.get_node("Shortcuts").get_child_count(), 0, "%s ships a shortcut" % id)
		assert_eq(VALIDATOR.shortcut_errors(track).size(), 0, "%s shortcut invariants hold" % id)
