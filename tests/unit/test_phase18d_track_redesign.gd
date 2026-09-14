extends GutTest

## Phase 18d: track_02 (Lumen Underpass) redesign regression + geometry checks.
##
## 1. authored_points() defaults to empty, and track_03/track_04 (which do not
##    override it) still build the exact same default rounded-rectangle curve
##    as before ContentTrack grew the authored_points() seam.
## 2. track_02's authored curve (chicanes -> sweeper -> compound hairpin ->
##    closing straight) satisfies the redesign's own constraints: minimum
##    curvature radius, no self-intersection with adequate road clearance,
##    and total length within +-25% of the old rounded-rectangle length.
## 3. ContentTrack.shortcut()'s per-segment trigger volume: a 2-point route
##    still builds exactly one box (unchanged from the old single-chord
##    box), and PrismAlley's curved multi-point route stays covered by its
##    trigger along its whole length instead of only near the chord.

## Closed-form perimeter of the pre-redesign track_02 rectangle:
## 4*half_width + 4*half_depth - 8*corner_radius + 2*PI*corner_radius,
## for half_width=300, half_depth=110, corner_radius=24.
const OLD_TRACK02_LENGTH: float = 1598.8

const MIN_CURVE_RADIUS: float = 22.0

const EXPECTED_DEFAULT_CURVE: Dictionary = {
	"track_03": {"points": 295, "length": 1667.726},
	"track_04": {"points": 319, "length": 1697.864},
}


func test_authored_points_empty_by_default_for_track03_and_track04() -> void:
	for id: String in EXPECTED_DEFAULT_CURVE.keys():
		var track: ContentTrack = _track(id)
		assert_true(track.authored_points().is_empty(), "%s should not override authored_points()" % id)
		var first: Vector3 = track.line.curve.get_point_position(0)
		var last: Vector3 = track.line.curve.get_point_position(track.line.curve.point_count - 1)
		assert_almost_eq(first.distance_to(last), 0.0, 0.01, "%s racing line must close" % id)


## Regression guard: the default rounded-rectangle path (point count and
## baked length) is unchanged by ContentTrack's new authored_points() seam.
func test_default_rectangle_curve_matches_pre_seam_values_for_track03_and_track04() -> void:
	for id: String in EXPECTED_DEFAULT_CURVE.keys():
		var track: ContentTrack = _track(id)
		var expected: Dictionary = EXPECTED_DEFAULT_CURVE[id]
		assert_eq(track.line.curve.point_count, int(expected["points"]), "%s point count changed" % id)
		assert_almost_eq(track.line.length(), float(expected["length"]), 1.0, "%s baked length changed" % id)


func test_track02_length_within_25_percent_of_old_rectangle() -> void:
	var track: ContentTrack = _track("track_02")
	var length: float = track.line.length()
	assert_gt(length, OLD_TRACK02_LENGTH * 0.75, "track_02 length shrank more than 25%% vs the old rectangle")
	assert_lt(length, OLD_TRACK02_LENGTH * 1.25, "track_02 length grew more than 25%% vs the old rectangle")


func test_track02_minimum_curvature_radius_is_at_least_22_metres() -> void:
	var track: ContentTrack = _track("track_02")
	var length: float = track.line.length()
	var max_curvature: float = 0.0
	var step: float = 2.0
	var offset: float = 0.0
	while offset < length:
		max_curvature = maxf(max_curvature, absf(track.line.curvature_at(offset)))
		offset += step
	var max_curvature_allowed: float = 1.0 / MIN_CURVE_RADIUS
	assert_lte(max_curvature, max_curvature_allowed,
		"track_02 curvature %.5f implies a radius under %.1fm" % [max_curvature, MIN_CURVE_RADIUS])


## A pure geometric self-intersection check on the (x, z) footprint: any two
## non-adjacent baked-point segments that cross means the loop overlaps
## itself. (A euclidean-distance-between-offsets heuristic was tried first
## but false-positives near the start/finish seam - both halves of the grid
## straight legitimately converge there - and on the hairpin's tight-radius
## tail, where consecutive points on a single continuous curve are closer
## together than their along-line offset gap suggests. Segment intersection
## has neither problem: it only fires on an actual crossing.)
func test_track02_racing_line_does_not_self_intersect() -> void:
	var track: ContentTrack = _track("track_02")
	var points3: PackedVector3Array = track.line.get_baked_points()
	assert_gt(points3.size(), 10, "track_02 racing line should have many baked points")
	var points: Array[Vector2] = []
	for point: Vector3 in points3:
		points.append(Vector2(point.x, point.z))
	var count: int = points.size()
	var crossings: int = 0
	for i: int in range(count - 1):
		for j: int in range(i + 2, count - 1):
			if i == 0 and j == count - 2:
				continue  # the closing segment and the first segment share the seam point
			if _segments_cross(points[i], points[i + 1], points[j], points[j + 1]):
				crossings += 1
	assert_eq(crossings, 0, "track_02 racing line crosses itself %d time(s)" % crossings)


## Regression guard: shortcut()'s per-segment trigger volume must still
## degenerate to exactly the old single chord box when given only 2 points
## (e.g. a straight shortcut), matching the pre-fix geometry exactly.
func test_shortcut_with_two_points_produces_a_single_unchanged_box() -> void:
	var track: ContentTrack = _track("track_03")
	var start: Vector3 = Vector3(20.0, 0.4, -30.0)
	var end: Vector3 = Vector3(60.0, 0.4, 10.0)
	var route: TrackShortcut = track.shortcut("TestChordShortcut", 0.0, 40.0, [start, end], 20.0, false)
	var trigger: Area3D = route.get_node("TriggerArea") as Area3D
	assert_eq(trigger.get_child_count(), 1, "a 2-point shortcut should still build exactly one trigger box")
	var shape_node: CollisionShape3D = trigger.get_child(0) as CollisionShape3D
	var box: BoxShape3D = shape_node.shape as BoxShape3D
	var expected_size: Vector3 = Vector3(8.0, 8.0, start.distance_to(end))
	assert_almost_eq(box.size.distance_to(expected_size), 0.0, 0.001, "2-point trigger box size changed")
	var expected_transform: Transform3D = Transform3D(Basis.looking_at(end - start), (start + end) * 0.5)
	assert_almost_eq(shape_node.global_transform.origin.distance_to(expected_transform.origin), 0.0, 0.001,
		"2-point trigger box origin changed")
	assert_almost_eq(shape_node.global_transform.basis.z.distance_to(expected_transform.basis.z), 0.0, 0.001,
		"2-point trigger box orientation changed")


## PrismAlley's alt route curves up to ~14m away from its own entry->exit
## chord, so the old single chord-box trigger left most of the curve
## uncovered. Every baked sample along the real alt route must land inside
## at least one of the fixed per-segment boxes.
func test_prism_alley_trigger_covers_samples_along_its_curved_alt_route() -> void:
	var track: ContentTrack = _track("track_02")
	var route: TrackShortcut = track.get_node("Shortcuts/PrismAlley") as TrackShortcut
	var trigger: Area3D = route.get_node("TriggerArea") as Area3D
	var boxes: Array[CollisionShape3D] = []
	for child: Node in trigger.get_children():
		boxes.append(child as CollisionShape3D)
	assert_gt(boxes.size(), 1, "PrismAlley's curved alt route should build more than one trigger box")
	var baked: PackedVector3Array = route.alt_curve.curve.get_baked_points()
	assert_gt(baked.size(), 20, "PrismAlley alt curve should have many baked samples")
	var margin: float = 0.05
	var uncovered: int = 0
	for local_point: Vector3 in baked:
		var global_point: Vector3 = route.alt_curve.to_global(local_point)
		var inside: bool = false
		for box: CollisionShape3D in boxes:
			var local_in_box: Vector3 = box.to_local(global_point)
			var half: Vector3 = (box.shape as BoxShape3D).size * 0.5
			if absf(local_in_box.x) <= half.x + margin and absf(local_in_box.y) <= half.y + margin \
					and absf(local_in_box.z) <= half.z + margin:
				inside = true
				break
		if not inside:
			uncovered += 1
	assert_eq(uncovered, 0, "%d of %d PrismAlley curve samples fall outside every trigger box" % [uncovered, baked.size()])


static func _segments_cross(p1: Vector2, p2: Vector2, p3: Vector2, p4: Vector2) -> bool:
	var d1: float = _ccw(p3, p4, p1)
	var d2: float = _ccw(p3, p4, p2)
	var d3: float = _ccw(p1, p2, p3)
	var d4: float = _ccw(p1, p2, p4)
	return (d1 > 0.0) != (d2 > 0.0) and (d3 > 0.0) != (d4 > 0.0)


static func _ccw(a: Vector2, b: Vector2, c: Vector2) -> float:
	return (c.y - a.y) * (b.x - a.x) - (b.y - a.y) * (c.x - a.x)


func _track(id: String) -> ContentTrack:
	var data: TrackData = load("res://data/tracks/%s.tres" % id) as TrackData
	var track: ContentTrack = data.scene.instantiate() as ContentTrack
	add_child_autofree(track)
	return track
