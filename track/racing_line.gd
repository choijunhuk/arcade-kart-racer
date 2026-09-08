class_name RacingLine
extends Path3D

## Bakes the closed `Curve3D` into a local point array once and answers
## offset-based queries used by LapTracker, PositionTracker, RespawnSystem,
## and (later) AI. Spec: §8, §14, §26 (hinted search, not a full scan per tick).

const TEST_OVAL_POINTS: Array[Vector3] = [
	Vector3(-30.0, 0.4, 22.0),
	Vector3(30.0, 0.4, 22.0),
	Vector3(45.0, 0.4, 16.0),
	Vector3(52.0, 0.4, 0.0),
	Vector3(45.0, 0.4, -16.0),
	Vector3(30.0, 0.4, -22.0),
	Vector3(-30.0, 0.4, -22.0),
	Vector3(-45.0, 0.4, -16.0),
	Vector3(-52.0, 0.4, 0.0),
	Vector3(-45.0, 0.4, 16.0),
	Vector3(-30.0, 0.4, 22.0),
]

## Distance in metres between baked sample points (`Curve3D.bake_interval`).
@export var bake_interval: float = 2.0
## Baked points searched on each side of a hint index before falling back to
## a full scan (spec §26: O(k) hinted search instead of O(n) every tick).
@export var hint_window: int = 12
## Sample span (metres) used to fit the 3-point circle in `curvature_at`.
@export var curvature_window: float = 8.0

var _baked: bool = false
var _points: PackedVector3Array = PackedVector3Array()
var _cumulative: PackedFloat32Array = PackedFloat32Array()
var _length: float = 0.0


func _ready() -> void:
	if curve == null or curve.point_count == 0:
		_build_test_oval()


## Rebuilds the local point/offset cache from `curve`. Idempotent queries
## call this lazily; call it again explicitly after mutating `curve` at
## runtime (e.g. a track-builder tool).
func bake() -> void:
	_points = PackedVector3Array()
	_cumulative = PackedFloat32Array()
	_length = 0.0
	_baked = true
	if curve == null or curve.point_count < 2:
		return
	curve.bake_interval = bake_interval
	_points = curve.get_baked_points()
	if _points.size() < 2:
		return
	var accumulated: float = 0.0
	_cumulative.append(0.0)
	for index: int in range(1, _points.size()):
		accumulated += _points[index - 1].distance_to(_points[index])
		_cumulative.append(accumulated)
	_length = accumulated


## Total baked length of the closed loop, in metres.
func length() -> float:
	_ensure_baked()
	return _length


## Returns a defensive local-space baked-point copy for minimap presentation.
func get_baked_points() -> PackedVector3Array:
	_ensure_baked()
	return _points.duplicate()


## Nearest-point search for the racing-line offset under `global_pos`. Full
## scan when `hint_offset < 0`, otherwise a local window search around the
## baked index for `hint_offset` (spec §26). Handles wrap around the seam.
func offset_at(global_pos: Vector3, hint_offset: float = -1.0) -> float:
	_ensure_baked()
	if _points.size() < 2 or _length <= 0.0:
		return 0.0
	var local_pos: Vector3 = to_local(global_pos)
	var index: int = _closest_index(local_pos, hint_offset)
	return fposmod(_refine_offset(local_pos, index), _length)


## Global-space point at `offset` along the baked line (wraps automatically).
func sample(offset: float) -> Vector3:
	_ensure_baked()
	if _points.size() < 2:
		return global_position
	return to_global(_sample_local(offset))


## Global-space normalized direction of travel at `offset`.
func tangent_at(offset: float) -> Vector3:
	_ensure_baked()
	if _points.size() < 2:
		return -global_transform.basis.z
	var segment: Dictionary = _segment_at_offset(fposmod(offset, maxf(_length, 0.001)))
	var local_dir: Vector3 = _points[segment["upper"]] - _points[segment["lower"]]
	if local_dir.length() < 0.0001:
		return -global_transform.basis.z
	return (global_transform.basis * local_dir).normalized()


## Global-space horizontal "right of travel" direction at `offset`.
func right_at(offset: float) -> Vector3:
	return tangent_at(offset).cross(Vector3.UP).normalized()


## Signed curvature (1/radius, from a 3-point circle fit) around `offset`:
## positive for a left turn, negative for a right turn (relative to the
## direction of travel, Y-up).
func curvature_at(offset: float) -> float:
	_ensure_baked()
	if _length <= 0.0:
		return 0.0
	var half: float = curvature_window * 0.5
	var before: Vector3 = _sample_local(offset - half)
	var middle: Vector3 = _sample_local(offset)
	var after: Vector3 = _sample_local(offset + half)
	return _circle_curvature(before, middle, after)


## Largest absolute curvature sampled across `[offset, offset + distance]`.
func max_curvature_in(offset: float, distance: float) -> float:
	_ensure_baked()
	if distance <= 0.0:
		return absf(curvature_at(offset))
	var step: float = maxf(bake_interval, 1.0)
	var steps: int = maxi(1, int(ceil(distance / step)))
	var result: float = 0.0
	for index: int in range(steps + 1):
		var sample_offset: float = offset + distance * (float(index) / float(steps))
		result = maxf(result, absf(curvature_at(sample_offset)))
	return result


func _ensure_baked() -> void:
	if not _baked:
		bake()


func _sample_local(offset: float) -> Vector3:
	var wrapped: float = fposmod(offset, maxf(_length, 0.001))
	var segment: Dictionary = _segment_at_offset(wrapped)
	var lower: int = segment["lower"]
	var upper: int = segment["upper"]
	return _points[lower].lerp(_points[upper], segment["t"])


## Returns the baked segment `{lower, upper, t}` containing `wrapped_offset`.
func _segment_at_offset(wrapped_offset: float) -> Dictionary:
	var upper: int = _index_at_offset(wrapped_offset)
	if upper <= 0:
		return {"lower": 0, "upper": mini(1, _points.size() - 1), "t": 0.0}
	var lower: int = upper - 1
	var segment_length: float = _cumulative[upper] - _cumulative[lower]
	var t: float = 0.0
	if segment_length > 0.000001:
		t = clampf((wrapped_offset - _cumulative[lower]) / segment_length, 0.0, 1.0)
	return {"lower": lower, "upper": upper, "t": t}


## Lower-bound binary search: first baked index whose cumulative distance is
## `>= offset`.
func _index_at_offset(offset: float) -> int:
	var low: int = 0
	var high: int = _cumulative.size() - 1
	while low < high:
		var mid: int = (low + high) / 2
		if _cumulative[mid] < offset:
			low = mid + 1
		else:
			high = mid
	return low


func _closest_index(local_pos: Vector3, hint_offset: float) -> int:
	var count: int = _points.size()
	if hint_offset < 0.0:
		var best_index: int = 0
		var best_dist: float = local_pos.distance_squared_to(_points[0])
		for index: int in range(1, count):
			var dist: float = local_pos.distance_squared_to(_points[index])
			if dist < best_dist:
				best_dist = dist
				best_index = index
		return best_index
	var hint_index: int = _index_at_offset(fposmod(hint_offset, _length))
	var best_index: int = hint_index
	var best_dist: float = local_pos.distance_squared_to(_points[hint_index])
	for delta: int in range(-hint_window, hint_window + 1):
		var index: int = ((hint_index + delta) % count + count) % count
		var dist: float = local_pos.distance_squared_to(_points[index])
		if dist < best_dist:
			best_dist = dist
			best_index = index
	return best_index


func _refine_offset(local_pos: Vector3, index: int) -> float:
	var count: int = _points.size()
	var best_offset: float = _cumulative[index]
	var best_dist: float = local_pos.distance_squared_to(_points[index])
	var next_index: int = (index + 1) % count
	if next_index != index:
		var forward: Dictionary = _project_segment(local_pos, index, next_index)
		if forward["dist"] < best_dist:
			best_dist = forward["dist"]
			best_offset = forward["offset"]
	var previous_index: int = (index - 1 + count) % count
	if previous_index != index:
		var backward: Dictionary = _project_segment(local_pos, previous_index, index)
		if backward["dist"] < best_dist:
			best_dist = backward["dist"]
			best_offset = backward["offset"]
	return best_offset


func _project_segment(local_pos: Vector3, a_index: int, b_index: int) -> Dictionary:
	var a: Vector3 = _points[a_index]
	var b: Vector3 = _points[b_index]
	var segment: Vector3 = b - a
	var segment_length_sq: float = segment.length_squared()
	var t: float = 0.0
	if segment_length_sq > 0.000001:
		t = clampf((local_pos - a).dot(segment) / segment_length_sq, 0.0, 1.0)
	var closest: Vector3 = a.lerp(b, t)
	var offset: float = _cumulative[a_index] + segment.length() * t
	return {"dist": local_pos.distance_squared_to(closest), "offset": offset}


static func _circle_curvature(p0: Vector3, p1: Vector3, p2: Vector3) -> float:
	var side_a: float = p1.distance_to(p2)
	var side_b: float = p0.distance_to(p2)
	var side_c: float = p0.distance_to(p1)
	var cross: Vector3 = (p1 - p0).cross(p2 - p0)
	var doubled_area: float = cross.length()
	if doubled_area < 0.000001:
		return 0.0
	var radius: float = (side_a * side_b * side_c) / (2.0 * doubled_area)
	if radius < 0.000001:
		return 0.0
	return signf(cross.y) * (1.0 / radius)


func _build_test_oval() -> void:
	# The flat/hills test fixtures use this oval. Hairpin and Track01 scripts
	# assign their own curve before use.
	curve = Curve3D.new()
	for point: Vector3 in TEST_OVAL_POINTS:
		curve.add_point(point)
