extends GutTest

const NEW_TRACKS: Array[String] = ["track_02", "track_03", "track_04"]


func test_new_tracks_have_required_gates_grid_rows_previews_and_music() -> void:
	for id: String in NEW_TRACKS:
		var data: TrackData = load("res://data/tracks/%s.tres" % id) as TrackData
		var track: ContentTrack = data.scene.instantiate() as ContentTrack
		add_child(track)
		assert_gte(track.get_checkpoints().size(), 8)
		assert_eq(track.get_start_grid().size(), 8)
		assert_gte(track.get_item_box_anchors().size(), 12)
		assert_not_null(data.preview)
		assert_not_null(data.bgm)
		assert_false(data.bgm_id.is_empty())
		assert_not_null(track.get_node_or_null("Geometry/RoadSurface"))
		for transform: Transform3D in track.get_start_grid():
			assert_almost_eq(transform.basis.y.distance_to(Vector3.UP), 0.0, 0.00001)
		track.free()


func test_ice_has_real_chasm_banking_and_three_racing_line_ice_sheets() -> void:
	var track: ContentTrack = _track("track_03")
	await wait_physics_frames(1)
	var gap: Vector3 = Vector3(-210.0, 0.0, -140.0)
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(gap + Vector3.UP * 10.0, gap + Vector3.DOWN * 10.0, 1)
	assert_true(track.get_world_3d().direct_space_state.intersect_ray(query).is_empty())
	assert_gt(track.bank_at(track.line.offset_at(Vector3(-300.0, 0.4, -100.0))), 0.0)
	assert_eq(track.get_node("OffroadZones").get_child_count(), 3)
	for zone: Node in track.get_node("OffroadZones").get_children():
		assert_almost_eq((zone as OffroadZone).terrain.grip, 0.25, 0.00001)
	assert_true(track.get_node("Hazards/MoraineA") is RollingBoulder)
	assert_true(track.get_node("Hazards/MoraineB") is RollingBoulder)


func test_shortcuts_do_not_bypass_required_checkpoints() -> void:
	for id: String in ["track_02", "track_04"]:
		var track: ContentTrack = _track(id)
		for route: Node in track.get_node("Shortcuts").get_children():
			var shortcut: TrackShortcut = route as TrackShortcut
			assert_not_null(shortcut.alt_curve)
			for checkpoint: Checkpoint in track.get_checkpoints():
				assert_false(checkpoint.offset > shortcut.entry_offset and checkpoint.offset < shortcut.exit_offset)


func test_sandstorm_hits_once_per_active_phase_then_rearms() -> void:
	var track: ContentTrack = _track("track_04")
	var storm: TimedHazard = track.get_node("Hazards/Sandstorm") as TimedHazard
	storm.set_physics_process(false)
	var body: Node3D = Node3D.new()
	add_child_autofree(body)
	watch_signals(storm)
	storm.active = true
	storm._on_body_entered(body)
	storm._on_body_entered(body)
	assert_signal_emit_count(storm, "body_hazard_hit", 1)
	storm.phase_seconds = storm.active_seconds
	storm._physics_process(0.0)
	assert_false(storm.active)
	storm.phase_seconds = 0.0
	storm._physics_process(0.0)
	storm._on_body_entered(body)
	assert_signal_emit_count(storm, "body_hazard_hit", 2)
	assert_eq(storm.hit_type, int(HitReactor.HitType.SQUASH))


func test_kill_plane_validation_rejects_thin_or_above_road_coverage() -> void:
	var validator: Script = load("res://track/track_validator.gd") as Script
	assert_false(bool(validator.call("kill_plane_is_safe", AABB(Vector3(-10, -5, -10), Vector3(20, 1, 20)), 0.0)))
	assert_false(bool(validator.call("kill_plane_is_safe", AABB(Vector3(-10, -10, -10), Vector3(20, 32, 20)), 0.0)))
	assert_true(bool(validator.call("kill_plane_is_safe", AABB(Vector3(-10, -205, -10), Vector3(20, 200, 20)), 0.0)))


func _track(id: String) -> ContentTrack:
	var data: TrackData = load("res://data/tracks/%s.tres" % id) as TrackData
	var track: ContentTrack = data.scene.instantiate() as ContentTrack
	add_child_autofree(track)
	return track
