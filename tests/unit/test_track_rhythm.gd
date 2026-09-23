extends GutTest

## 19-D item 5: the added dash panels / kicker ramp on tracks 1-3 exist, sit on
## the racing line over real road, and point along the direction of travel.

const ON_LINE_TOLERANCE: float = 1.0
const EXPECTED: Dictionary = {
	"res://track/tracks/track_01_ridgeline_circuit/track_01_ridgeline_circuit.tscn": ["BoostPads/HairpinExitDash"],
	"res://track/tracks/track_02_lumen_underpass/track_02_lumen_underpass.tscn": ["BoostPads/SweeperDash0", "BoostPads/SweeperDash1"],
	"res://track/tracks/track_03_glacier_crown/track_03_glacier_crown.tscn": ["BoostPads/CrownDash0", "BoostPads/CrownDash1", "JumpPads/WestKicker"],
}


func test_rhythm_elements_are_on_the_racing_line_over_road() -> void:
	for scene_path: String in EXPECTED:
		var track: TrackRoot = (load(scene_path) as PackedScene).instantiate() as TrackRoot
		add_child_autofree(track)
		await wait_physics_frames(2)
		var line: RacingLine = track.get_racing_line()
		for node_path: String in EXPECTED[scene_path]:
			var pad: Area3D = track.get_node_or_null(node_path) as Area3D
			assert_not_null(pad, "%s missing in %s" % [node_path, scene_path])
			if pad == null:
				continue
			var offset: float = line.offset_at(pad.global_position)
			var on_line: Vector3 = line.sample(offset)
			var flat: Vector3 = Vector3(pad.global_position.x - on_line.x, 0.0, pad.global_position.z - on_line.z)
			assert_lt(flat.length(), ON_LINE_TOLERANCE, "%s sits on the racing line" % node_path)
			assert_gt((-pad.global_basis.z).dot(line.tangent_at(offset)), 0.95, "%s faces the direction of travel" % node_path)
			var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
				pad.global_position + Vector3.UP, pad.global_position + Vector3.DOWN * 2.0, 1)
			var hit: Dictionary = track.get_world_3d().direct_space_state.intersect_ray(query)
			assert_false(hit.is_empty(), "%s has road under it" % node_path)


## Regression: Track01's pads sat at y 0.3 (box top 0.5) under a 0.6 road top,
## so no kart body ever overlapped them and they never fired.
func test_every_pad_trigger_rises_above_the_road_surface() -> void:
	for scene_path: String in [
		"res://track/tracks/track_01_ridgeline_circuit/track_01_ridgeline_circuit.tscn",
		"res://track/tracks/track_02_lumen_underpass/track_02_lumen_underpass.tscn",
		"res://track/tracks/track_03_glacier_crown/track_03_glacier_crown.tscn",
		"res://track/tracks/track_04_ochre_rift/track_04_ochre_rift.tscn",
	]:
		var track: TrackRoot = (load(scene_path) as PackedScene).instantiate() as TrackRoot
		add_child_autofree(track)
		await wait_physics_frames(2)
		for container: String in ["BoostPads", "JumpPads"]:
			for pad: Node in track.get_node(container).get_children():
				var shape: CollisionShape3D = (pad as Node3D).find_children("", "CollisionShape3D", true, false)[0] as CollisionShape3D
				var top: float = shape.global_position.y + (shape.shape as BoxShape3D).size.y * 0.5 * shape.global_basis.get_scale().y
				var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
					shape.global_position, shape.global_position + Vector3.DOWN * 2.0, 1)
				var hit: Dictionary = track.get_world_3d().direct_space_state.intersect_ray(query)
				if hit.is_empty():
					fail_test("%s/%s has no road under it" % [scene_path.get_file(), pad.name])
					continue
				assert_gt(top - (hit["position"] as Vector3).y, 0.2, "%s/%s reaches a grounded kart body" % [scene_path.get_file(), pad.name])


func test_track03_kicker_launch_is_a_short_hop() -> void:
	var script: GDScript = load("res://track/tracks/track_03_glacier_crown/track_03_track.gd") as GDScript
	var launch: Vector3 = script.get_script_constant_map()["KICKER_LAUNCH"]
	var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	var apex: float = launch.y * launch.y / (2.0 * gravity)
	assert_lt(apex, 2.0, "kicker stays a hop, well under any overhead")
