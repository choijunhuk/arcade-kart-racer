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
		shape_node.set_meta(&"driveable_surface", true)
		body.add_child(shape_node)
		var half: float = width * 0.5
		var kerb_a: float = _kerb_mask(curve, a)
		var kerb_b: float = _kerb_mask(curve, b)
		var corners: Array = [
			[start - ra + up, Vector2(-half, a), kerb_a], [end - rb + up, Vector2(-half, b), kerb_b],
			[end + rb + up, Vector2(half, b), kerb_b], [start - ra + up, Vector2(-half, a), kerb_a],
			[end + rb + up, Vector2(half, b), kerb_b], [start + ra + up, Vector2(half, a), kerb_a],
		]
		for corner: Array in corners:
			# UV: lateral/along metres; UV2: half width + corner kerb mask (road.gdshader).
			surface.set_uv(corner[1])
			surface.set_uv2(Vector2(half, corner[2]))
			surface.add_vertex(body.to_local(corner[0]))
	surface.generate_normals()
	var mesh: ArrayMesh = surface.commit()
	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.name = "RoadVisual"
	visual.mesh = mesh
	visual.add_to_group(&"road_visual")
	visual.set_meta(&"main_road", path is RacingLine)
	body.add_child(visual)


## Road-shader kerb mask from the heading change over +-2 m of the curve.
static func _kerb_mask(curve: Curve3D, offset: float) -> float:
	var length: float = curve.get_baked_length()
	var before: Vector3 = curve.sample_baked(clampf(offset - 2.0, 0.0, length))
	var here: Vector3 = curve.sample_baked(clampf(offset, 0.0, length))
	var after: Vector3 = curve.sample_baked(clampf(offset + 2.0, 0.0, length))
	var first: Vector3 = Vector3(here.x - before.x, 0.0, here.z - before.z)
	var second: Vector3 = Vector3(after.x - here.x, 0.0, after.z - here.z)
	if first.length() < 0.01 or second.length() < 0.01:
		return 0.0
	return 1.0 if first.angle_to(second) / 2.0 >= RoadRibbon.KERB_CURVATURE_MIN else 0.0



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


## Adds a zero-overlap prism whose start/end width axes can follow a curved path.
static func add_connected_segment(
	body: StaticBody3D, start: Vector3, end: Vector3, start_width_axis: Vector3,
	end_width_axis: Vector3, width: float, height: float, material: StandardMaterial3D,
) -> void:
	if start.distance_to(end) < 0.001 or start_width_axis.length() < 0.001 or end_width_axis.length() < 0.001:
		return
	var half_width: float = width * 0.5
	var up: Vector3 = Vector3.UP * height * 0.5
	var start_right: Vector3 = start_width_axis.normalized() * half_width
	var end_right: Vector3 = end_width_axis.normalized() * half_width
	var points: PackedVector3Array = PackedVector3Array([
		body.to_local(start - start_right - up),
		body.to_local(start + start_right - up),
		body.to_local(start - start_right + up),
		body.to_local(start + start_right + up),
		body.to_local(end - end_right - up),
		body.to_local(end + end_right - up),
		body.to_local(end - end_right + up),
		body.to_local(end + end_right + up),
	])
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_material(material)
	for vertex_index: int in [
		2, 6, 7, 2, 7, 3,
		0, 1, 5, 0, 5, 4,
		0, 4, 6, 0, 6, 2,
		1, 3, 7, 1, 7, 5,
		0, 2, 3, 0, 3, 1,
		4, 5, 7, 4, 7, 6,
	]:
		surface.add_vertex(points[vertex_index])
	surface.generate_normals()
	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.mesh = surface.commit()
	body.add_child(visual)
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: ConvexPolygonShape3D = ConvexPolygonShape3D.new()
	shape.points = points
	collision.shape = shape
	body.add_child(collision)
