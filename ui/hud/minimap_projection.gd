class_name MinimapProjection
extends RefCounted

const CENTER: Vector2 = Vector2(0.5, 0.5)
const MIN_SPAN: float = 0.000001


## Projects world X/Z points into centered, aspect-preserving normalized 2D.
static func normalize_points(points: PackedVector3Array) -> PackedVector2Array:
	var normalized: PackedVector2Array = PackedVector2Array()
	if points.is_empty():
		return normalized
	var first: Vector2 = Vector2(points[0].x, points[0].z)
	var minimum: Vector2 = first
	var maximum: Vector2 = first
	for point: Vector3 in points:
		var projected: Vector2 = Vector2(point.x, point.z)
		minimum = minimum.min(projected)
		maximum = maximum.max(projected)
	var size: Vector2 = maximum - minimum
	var span: float = maxf(size.x, size.y)
	if span <= MIN_SPAN:
		for _point: Vector3 in points:
			normalized.append(CENTER)
		return normalized
	var center: Vector2 = (minimum + maximum) * 0.5
	for point: Vector3 in points:
		var projected: Vector2 = Vector2(point.x, point.z)
		normalized.append((projected - center) / span + CENTER)
	return normalized
