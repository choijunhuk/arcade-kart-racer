extends GutTest

## Synthetic-circle coverage for RacingLine's offset/curvature math (spec
## §24 Phase 4 DoD: "unit tests: racing line math").

const RADIUS: float = 25.0
const SEGMENTS: int = 90
const CURVATURE_TOLERANCE: float = 0.1 # relative; polygon-approximated circle


func _build_circle_line() -> RacingLine:
	var line: RacingLine = RacingLine.new()
	var curve: Curve3D = Curve3D.new()
	for index: int in range(SEGMENTS + 1):
		var angle: float = TAU * float(index) / float(SEGMENTS)
		curve.add_point(Vector3(RADIUS * cos(angle), 0.0, RADIUS * sin(angle)))
	line.curve = curve
	line.bake_interval = 1.0
	add_child_autofree(line)
	return line


func test_curvature_matches_one_over_radius_at_multiple_offsets() -> void:
	var line: RacingLine = _build_circle_line()
	# `_build_circle_line`'s winding (angle increasing around +y) puts the
	# circle's center to the right of travel (see RacingLine.right_at), i.e.
	# a right turn, which is negative by the documented sign convention
	# (positive = left turn, negative = right turn).
	var expected: float = -1.0 / RADIUS
	for offset: float in [0.0, line.length() * 0.25, line.length() * 0.5, line.length() * 0.75]:
		var curvature: float = line.curvature_at(offset)
		assert_almost_eq(curvature, expected, absf(expected) * CURVATURE_TOLERANCE)


func test_curvature_sign_flips_for_opposite_winding() -> void:
	var ccw_line: RacingLine = _build_circle_line()
	var cw_curve: Curve3D = Curve3D.new()
	for index: int in range(SEGMENTS + 1):
		var angle: float = -TAU * float(index) / float(SEGMENTS)
		cw_curve.add_point(Vector3(RADIUS * cos(angle), 0.0, RADIUS * sin(angle)))
	var cw_line: RacingLine = RacingLine.new()
	cw_line.curve = cw_curve
	cw_line.bake_interval = 1.0
	add_child_autofree(cw_line)

	var ccw_curvature: float = ccw_line.curvature_at(0.0)
	var cw_curvature: float = cw_line.curvature_at(0.0)
	assert_lt(ccw_curvature * cw_curvature, 0.0, "opposite winding must flip the curvature sign")
	assert_almost_eq(absf(ccw_curvature), absf(cw_curvature), absf(ccw_curvature) * CURVATURE_TOLERANCE)


func test_max_curvature_in_matches_curvature_at_on_a_uniform_circle() -> void:
	var line: RacingLine = _build_circle_line()
	var expected: float = 1.0 / RADIUS
	var result: float = line.max_curvature_in(0.0, 20.0)
	assert_almost_eq(result, expected, expected * CURVATURE_TOLERANCE)


func test_offsets_are_monotonic_along_the_line() -> void:
	var line: RacingLine = _build_circle_line()
	var length: float = line.length()
	var previous_offset: float = -1.0
	for step: int in range(10):
		var target_offset: float = length * float(step) / 10.0
		var point: Vector3 = line.sample(target_offset)
		var recovered: float = line.offset_at(point)
		assert_almost_eq(recovered, target_offset, length * 0.02)
		assert_gt(recovered, previous_offset - 0.001)
		previous_offset = recovered


func test_offset_wraps_correctly_across_the_seam() -> void:
	var line: RacingLine = _build_circle_line()
	var length: float = line.length()
	var near_end_point: Vector3 = line.sample(length - 0.5)
	var recovered: float = line.offset_at(near_end_point)
	# Accept either side of the seam: near `length` or wrapped near 0.
	var distance_to_seam: float = minf(absf(recovered - (length - 0.5)), absf(recovered - (length - 0.5) + length))
	assert_lt(distance_to_seam, 1.0)


func test_hinted_search_matches_full_search() -> void:
	var line: RacingLine = _build_circle_line()
	var length: float = line.length()
	var target_offset: float = length * 0.4
	var point: Vector3 = line.sample(target_offset)
	var full_search_offset: float = line.offset_at(point, -1.0)
	var hinted_offset: float = line.offset_at(point, target_offset)
	assert_almost_eq(hinted_offset, full_search_offset, 0.01)


func test_hinted_search_finds_correct_answer_from_a_nearby_wrong_hint() -> void:
	var line: RacingLine = _build_circle_line()
	var length: float = line.length()
	var target_offset: float = length * 0.6
	var point: Vector3 = line.sample(target_offset)
	var full_search_offset: float = line.offset_at(point, -1.0)
	var wrong_hint: float = fposmod(target_offset - 5.0, length)
	var hinted_offset: float = line.offset_at(point, wrong_hint)
	assert_almost_eq(hinted_offset, full_search_offset, 0.01)


func test_tangent_and_right_are_perpendicular_unit_vectors() -> void:
	var line: RacingLine = _build_circle_line()
	var tangent: Vector3 = line.tangent_at(0.0)
	var right: Vector3 = line.right_at(0.0)
	assert_almost_eq(tangent.length(), 1.0, 0.01)
	assert_almost_eq(right.length(), 1.0, 0.01)
	assert_almost_eq(tangent.dot(right), 0.0, 0.01)


func test_baked_points_returns_a_defensive_copy_for_minimap_consumers() -> void:
	var line: RacingLine = _build_circle_line()
	assert_true(line.has_method("get_baked_points"))
	if not line.has_method("get_baked_points"):
		return
	var points: PackedVector3Array = line.call("get_baked_points") as PackedVector3Array
	var original_size: int = points.size()
	points.clear()

	var second_read: PackedVector3Array = line.call("get_baked_points") as PackedVector3Array

	assert_gt(original_size, 8)
	assert_eq(second_read.size(), original_size)
