extends GutTest

const BUFFER_PATH: String = "res://effects/skid_strip_buffer.gd"
const SKID_PATH: String = "res://effects/skid_mark.gd"
const EPSILON: float = 0.001


func test_ring_buffer_caps_segment_count_and_keeps_newest_points() -> void:
	var buffer: RefCounted = _make_buffer(3)
	if buffer == null:
		return
	for index: int in range(6):
		buffer.call("add_point", Vector3(0.0, 0.0, float(index)))
	var points: Array[Vector3] = buffer.call("get_points") as Array[Vector3]
	assert_eq(int(buffer.call("get_segment_count")), 3)
	assert_eq(points.size(), 4)
	assert_eq(points[0], Vector3(0.0, 0.0, 2.0))
	assert_eq(points[3], Vector3(0.0, 0.0, 5.0))


func test_strip_geometry_joins_neighbor_quads_on_shared_edge_indices() -> void:
	var script: GDScript = _require_script(SKID_PATH)
	if script == null or not script.has_method("build_strip_geometry"):
		if script != null:
			fail_test("SkidMark.build_strip_geometry is missing")
		return
	var points: Array[Vector3] = [Vector3.ZERO, Vector3.FORWARD, Vector3.FORWARD * 2.0]
	var geometry: Dictionary = script.call("build_strip_geometry", points, 0.5, 0.8) as Dictionary
	var vertices: PackedVector3Array = geometry["vertices"] as PackedVector3Array
	var indices: PackedInt32Array = geometry["indices"] as PackedInt32Array
	assert_eq(vertices.size(), 6)
	assert_eq(indices.size(), 12)
	assert_eq(indices[2], indices[6])
	assert_eq(indices[5], indices[7])


func test_strip_geometry_fades_from_oldest_to_newest_vertex_pair() -> void:
	var script: GDScript = _require_script(SKID_PATH)
	if script == null or not script.has_method("build_strip_geometry"):
		if script != null:
			fail_test("SkidMark.build_strip_geometry is missing")
		return
	var points: Array[Vector3] = [Vector3.ZERO, Vector3.FORWARD, Vector3.FORWARD * 2.0]
	var geometry: Dictionary = script.call("build_strip_geometry", points, 0.5, 0.8) as Dictionary
	var colors: PackedColorArray = geometry["colors"] as PackedColorArray
	assert_almost_eq(colors[0].a, 0.0, EPSILON)
	assert_almost_eq(colors[1].a, 0.0, EPSILON)
	assert_almost_eq(colors[4].a, 0.8, EPSILON)
	assert_almost_eq(colors[5].a, 0.8, EPSILON)


func _make_buffer(max_segments: int) -> RefCounted:
	var script: GDScript = _require_script(BUFFER_PATH)
	if script == null:
		return null
	var buffer: RefCounted = script.new() as RefCounted
	buffer.call("configure", max_segments)
	return buffer


func _require_script(path: String) -> GDScript:
	if ResourceLoader.exists(path):
		return load(path) as GDScript
	fail_test("Required skid strip script is missing: %s" % path)
	return null
