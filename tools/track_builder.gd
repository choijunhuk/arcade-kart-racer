class_name TrackBuilder
extends RefCounted

## V2: welded UV presentation ribbon with the proven physical chord boxes.
## Collision-preserving art avoids changing historical AI/ghost physics.

const DEFAULT_SEGMENT_LENGTH: float = 8.0


## Adds shared-edge visual and collision surfaces for every road chord.
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
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_material(TrackArt.surface(material.albedo_color))
	for index: int in range(steps):
		var a: float = length * float(index) / float(steps)
		var b: float = length * float(index + 1) / float(steps)
		var start: Vector3 = path.to_global(curve.sample_baked(a))
		var end: Vector3 = path.to_global(curve.sample_baked(b))
		var ra: Vector3 = path.global_basis * curve.sample_baked_with_rotation(a).basis.x * width * 0.5
		var rb: Vector3 = path.global_basis * curve.sample_baked_with_rotation(b).basis.x * width * 0.5
		var shape_node: CollisionShape3D = CollisionShape3D.new()
		var shape: ConvexPolygonShape3D = ConvexPolygonShape3D.new()
		var up: Vector3 = Vector3.UP * height * 0.5
		shape.points = PackedVector3Array([
			body.to_local(start - ra - up),
			body.to_local(start + ra - up),
			body.to_local(start - ra + up),
			body.to_local(start + ra + up),
			body.to_local(end - rb - up),
			body.to_local(end + rb - up),
			body.to_local(end - rb + up),
			body.to_local(end + rb + up),
		])
		shape_node.shape = shape
		body.add_child(shape_node)
		for vertex: Vector3 in [start - ra + up, end - rb + up, end + rb + up, start - ra + up, end + rb + up, start + ra + up]:
			surface.set_uv(Vector2(vertex.x, vertex.z) * 0.2)
			surface.add_vertex(body.to_local(vertex))
	surface.generate_normals()
	var mesh: ArrayMesh = surface.commit()
	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.mesh = mesh
	body.add_child(visual)



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
	var visual_size: Vector3 = Vector3(width, height, segment_length)

	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	var box_mesh: BoxMesh = BoxMesh.new()
	box_mesh.size = visual_size
	box_mesh.material = material
	mesh_instance.mesh = box_mesh
	body.add_child(mesh_instance)
	mesh_instance.global_transform = Transform3D(basis, center)

	var collision: CollisionShape3D = CollisionShape3D.new()
	var box_shape: BoxShape3D = BoxShape3D.new()
	box_shape.size = visual_size
	collision.shape = box_shape
	body.add_child(collision)
	collision.global_transform = Transform3D(basis, center)
