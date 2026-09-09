extends ContentTrack

## Ochre Rift: enclosed sandstone canyon, sand shoulders and an aerial cutoff.

const SAND: TerrainData = preload("res://data/terrain/sand.tres")
const STORM_SCRIPT: Script = preload("res://track/elements/timed_hazard.gd")
const CANYON_ELEVATION: float = 12.0
const SHORTCUT_HEIGHT: float = 3.5
const SHORTCUT_SPEED: float = 35.0


func surface_height(point: Vector3) -> float:
	return ROAD_HEIGHT + CANYON_ELEVATION * (1.0 + cos(point.x / half_width * PI)) * 0.5


func open_inner_wall(point: Vector3) -> bool:
	return point.x < -240.0 and point.z > 50.0


func build_theme() -> void:
	# The enclosed canyon has a real basin beneath all shoulders and the skybridge.
	TrackBuilder.add_box_segment(geometry, Vector3(-half_width - 20.0, -4.0, 0.0),
		Vector3(half_width + 20.0, -4.0, 0.0), half_depth * 2.0 + 40.0, 2.0, road_material)
	for index: int in range(2):
		var offset: float = line.offset_at(Vector3(-120.0 + float(index) * 240.0, 0.0, half_depth))
		for side: float in [-1.0, 1.0]:
			terrain_patch("SandShoulder%d_%d" % [index, int(side)], offset,
				Vector3(8.0, 8.0, 95.0), SAND, side * 12.0)
	for index: int in range(3):
		place(BOOST_SCENE, "BoostPads", "ChainBoost%d" % index, 90.0 + float(index) * 12.0)
	_build_storm()
	_build_elevated_cutoff()


func _build_storm() -> void:
	var storm: TimedHazard = STORM_SCRIPT.new() as TimedHazard
	storm.name = "Sandstorm"
	storm.collision_layer = 64
	storm.collision_mask = 2
	storm.hit_type = HitReactor.HitType.SQUASH
	storm.phase_seconds = 3.0
	var shape_node: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(road_width, 7.0, 24.0)
	shape_node.shape = shape
	storm.add_child(shape_node)
	var mesh: MeshInstance3D = MeshInstance3D.new()
	mesh.name = "Mesh"
	var box: BoxMesh = BoxMesh.new()
	box.size = shape.size
	mesh.mesh = box
	var sand_material: StandardMaterial3D = material(Color(0.9, 0.58, 0.18, 0.3))
	sand_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material_override = sand_material
	storm.add_child(mesh)
	$Hazards.add_child(storm)
	var offset: float = line.offset_at(Vector3(half_width, ROAD_HEIGHT, 0.0))
	storm.global_transform = Transform3D(Basis.looking_at(line.tangent_at(offset)), line.sample(offset) + Vector3.UP * 2.0)


func _build_elevated_cutoff() -> void:
	var entry: Vector3 = Vector3(-half_width, ROAD_HEIGHT, 52.0)
	entry.y = surface_height(entry)
	var exit: Vector3 = Vector3(-242.0, ROAD_HEIGHT, half_depth)
	exit.y = surface_height(exit)
	var start: Vector3 = entry.lerp(exit, 0.18) + Vector3.UP * SHORTCUT_HEIGHT
	var end: Vector3 = entry.lerp(exit, 0.82) + Vector3.UP * SHORTCUT_HEIGHT
	var pad: JumpPad = place(JUMP_SCENE, "JumpPads", "SunbridgeLaunch", line.offset_at(entry), -12.0) as JumpPad
	pad.launch_velocity = Vector3(-14.0, 14.0, -28.0)
	var shoulder_exit: Vector3 = Vector3(-225.0, surface_height(Vector3(-225.0, 0.0, half_depth)), half_depth - 13.0)
	var approach: float = line.offset_at(entry) - 24.0
	shortcut("Sunbridge", approach, line.offset_at(shoulder_exit),
		[line.sample(approach), pad.global_position, start, end, shoulder_exit], SHORTCUT_SPEED, false)
	# There is no ramp from the approach to the raised deck: the jump is required.
	TrackBuilder.add_box_segment(geometry, start, end, 8.0, ROAD_HEIGHT, wall_material)
	TrackBuilder.add_box_segment(geometry, end, shoulder_exit, 6.0, ROAD_HEIGHT, wall_material)
