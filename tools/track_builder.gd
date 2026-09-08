class_name TrackBuilder
extends RefCounted

## Generates straight-box road/wall segments along a track's `RacingLine`
## (spec §15.6/§24 Phase 4): builds oriented boxes chord-approximating the
## curve at `segment_length` resolution. Used by procedurally-built tracks
## (e.g. track_01) so their Geometry does not need hand-placed meshes for
## every metre of road.

const DEFAULT_SEGMENT_LENGTH: float = 8.0


## Adds one mesh+collision box per chord along `path`'s baked curve, `width`
## wide (X) and `height` tall (Y), to `body`.
static func build_road_segments(
	body: StaticBody3D, path: Path3D, width: float, height: float,
	material: StandardMaterial3D, segment_length: float = DEFAULT_SEGMENT_LENGTH,
) -> void:
	var curve: Curve3D = path.curve
	if curve == null:
		return
	var length: float = curve.get_baked_length()
	if length <= 0.0:
		return
	var steps: int = maxi(1, int(ceil(length / segment_length)))
	for index: int in range(steps):
		var start: Vector3 = path.to_global(curve.sample_baked(length * float(index) / float(steps)))
		var end: Vector3 = path.to_global(curve.sample_baked(length * float(index + 1) / float(steps)))
		add_box_segment(body, start, end, width, height, material)


## Adds a single oriented box (mesh + collision) spanning `start` to `end`
## in world space, `width` wide and `height` tall, to `body`.
static func add_box_segment(
	body: StaticBody3D, start: Vector3, end: Vector3, width: float, height: float, material: StandardMaterial3D,
) -> void:
	var direction: Vector3 = end - start
	var segment_length: float = direction.length()
	if segment_length < 0.001:
		return
	var center: Vector3 = (start + end) * 0.5
	var basis: Basis = Basis.looking_at(direction.normalized(), Vector3.UP)
	var size: Vector3 = Vector3(width, height, segment_length)

	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	var box_mesh: BoxMesh = BoxMesh.new()
	box_mesh.size = size
	box_mesh.material = material
	mesh_instance.mesh = box_mesh
	body.add_child(mesh_instance)
	mesh_instance.global_transform = Transform3D(basis, center)

	var collision: CollisionShape3D = CollisionShape3D.new()
	var box_shape: BoxShape3D = BoxShape3D.new()
	box_shape.size = size
	collision.shape = box_shape
	body.add_child(collision)
	collision.global_transform = Transform3D(basis, center)
