class_name MinimapProjection
extends RefCounted

const CENTER: Vector2 = Vector2(0.5, 0.5)
const MIN_SPAN: float = 0.000001


## Projects world X/Z points into centered, aspect-preserving normalized 2D.
static func normalize_points(points: PackedVector3Array) -> PackedVector2Array:
	var normalized: PackedVector2Array = PackedVector2Array()
	if points.is_empty():
		return normalized
	var bounds: Rect2 = _bounds(points)
	var span: float = maxf(bounds.size.x, bounds.size.y)
	if span <= MIN_SPAN:
		for _point: Vector3 in points:
			normalized.append(CENTER)
		return normalized
	for point: Vector3 in points:
		normalized.append(_project_with_bounds(point, bounds, span))
	return normalized


## Projects one world point using the same aspect-preserving reference bounds.
static func project_point(point: Vector3, reference_points: PackedVector3Array) -> Vector2:
	if reference_points.is_empty():
		return CENTER
	var bounds: Rect2 = _bounds(reference_points)
	var span: float = maxf(bounds.size.x, bounds.size.y)
	return CENTER if span <= MIN_SPAN else _project_with_bounds(point, bounds, span)


static func _bounds(points: PackedVector3Array) -> Rect2:
	var first: Vector2 = Vector2(points[0].x, points[0].z)
	var minimum: Vector2 = first
	var maximum: Vector2 = first
	for point: Vector3 in points:
		var projected: Vector2 = Vector2(point.x, point.z)
		minimum = minimum.min(projected)
		maximum = maximum.max(projected)
	return Rect2(minimum, maximum - minimum)


static func _project_with_bounds(point: Vector3, bounds: Rect2, span: float) -> Vector2:
	var projected: Vector2 = Vector2(point.x, point.z)
	return (projected - bounds.get_center()) / span + CENTER
