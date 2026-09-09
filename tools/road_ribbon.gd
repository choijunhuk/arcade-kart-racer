class_name RoadRibbon
extends RefCounted

## Continuous road surface: shared chord edges prevent box end-face wall impacts.

const SEGMENT_LENGTH: float = 4.0


## Builds one mesh/trimesh with matching banked edges and explicitly omitted gaps.
static func build(track: ContentTrack) -> void:
	var line: RacingLine = track.line
	var count: int = ceili(line.length() / SEGMENT_LENGTH)
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_material(track.road_material)
	for index: int in range(count):
		var from_offset: float = line.length() * float(index) / float(count)
		var to_offset: float = line.length() * float(index + 1) / float(count)
		var start: Vector3 = line.sample(from_offset)
		var end: Vector3 = line.sample(to_offset)
		if track.is_gap((start + end) * 0.5):
			continue
		var from_right: Vector3 = _banked_right(track, from_offset)
		var to_right: Vector3 = _banked_right(track, to_offset)
		var up: Vector3 = Vector3.UP * ContentTrack.ROAD_HEIGHT * 0.5
		var left_start: Vector3 = start - from_right + up
		var right_start: Vector3 = start + from_right + up
		var left_end: Vector3 = end - to_right + up
		var right_end: Vector3 = end + to_right + up
		for vertex: Vector3 in [left_start, left_end, right_end, left_start, right_end, right_start]:
			surface.set_uv(Vector2(vertex.x, vertex.z) * 0.2)
			surface.add_vertex(track.geometry.to_local(vertex))
	surface.generate_normals()
	var mesh: ArrayMesh = surface.commit()
	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.name = "RoadRibbon"
	visual.mesh = mesh
	track.geometry.add_child(visual)
	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.name = "RoadSurface"
	collision.shape = mesh.create_trimesh_shape()
	track.geometry.add_child(collision)


static func _banked_right(track: ContentTrack, offset: float) -> Vector3:
	var right: Vector3 = track.line.right_at(offset)
	return right.rotated(track.line.tangent_at(offset), track.bank_at(offset)) * track.road_width * 0.5
