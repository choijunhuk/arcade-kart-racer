extends ContentTrack

## Glacier Crown: banked ice sweepers, a descending jump and rolling rock hazards.

const ICE: TerrainData = preload("res://data/terrain/ice.tres")
const BOULDER_SCRIPT: Script = preload("res://track/elements/rolling_boulder.gd")
const GAP_MIN_X: float = -216.0
const GAP_MAX_X: float = -204.0
const PEAK_HEIGHT: float = 16.0
const BANK_DEGREES: float = 5.0


func surface_height(point: Vector3) -> float:
	if point.z < -100.0:
		# Smooth ascent to x=-70, then downhill to the launch at x=-198.
		return ROAD_HEIGHT + PEAK_HEIGHT * maxf(0.0, 1.0 - absf(point.x + 70.0) / 125.0)
	return ROAD_HEIGHT


func is_gap(point: Vector3) -> bool:
	return point.z < -100.0 and point.x > GAP_MIN_X and point.x < GAP_MAX_X


func bank_at(offset: float) -> float:
	var curvature: float = line.curvature_at(offset)
	return deg_to_rad(BANK_DEGREES) * clampf(curvature * corner_radius, 0.0, 1.0)


func build_theme() -> void:
	var jump_offset: float = line.offset_at(Vector3(-199.0, ROAD_HEIGHT, -half_depth))
	var pad: JumpPad = place(JUMP_SCENE, "JumpPads", "ChasmLaunch", jump_offset) as JumpPad
	pad.launch_velocity = Vector3(0.0, 14.0, -27.0)
	pad.scale.x = road_width / 5.0
	for index: int in range(3):
		var offset: float = line.offset_at(Vector3(-130.0 + float(index) * 100.0, ROAD_HEIGHT, half_depth))
		terrain_patch("GlacierSheet%d" % index, offset, Vector3(road_width, 4.0, 65.0), ICE)
	_add_boulder("MoraineA", Vector3(-75.0, 1.8, half_depth))
	_add_boulder("MoraineB", Vector3(110.0, 1.8, half_depth))


func _add_boulder(node_name: String, center: Vector3) -> void:
	var boulder: RollingBoulder = BOULDER_SCRIPT.new() as RollingBoulder
	boulder.name = node_name
	boulder.collision_layer = 64
	boulder.collision_mask = 2
	boulder.speed = 3.0
	boulder.path = make_path("Hazards", node_name + "Path", [center + Vector3(0, 0, -11), center + Vector3(0, 0, 11)])
	var shape_node: CollisionShape3D = CollisionShape3D.new()
	var sphere: SphereShape3D = SphereShape3D.new()
	sphere.radius = boulder.radius
	shape_node.shape = sphere
	boulder.add_child(shape_node)
	var mesh: MeshInstance3D = MeshInstance3D.new()
	mesh.name = "Mesh"
	var sphere_mesh: SphereMesh = SphereMesh.new()
	sphere_mesh.radius = boulder.radius
	sphere_mesh.height = boulder.radius * 2.0
	mesh.mesh = sphere_mesh
	mesh.material_override = material(Color(0.28, 0.38, 0.48))
	boulder.add_child(mesh)
	$Hazards.add_child(boulder)
	boulder.position = center
