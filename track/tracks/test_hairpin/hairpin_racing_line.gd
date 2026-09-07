extends RacingLine

## A ~90 m paperclip oval: two straights (each carrying a mild S-curve chicane)
## joined by two `HAIRPIN_RADIUS` 180-degree hairpins built from evenly spaced
## arc points so sampled curvature stays continuous through the turn instead
## of spiking at a single vertex (spec §24 Phase 3 delivery contract item 4/8).

const HAIRPIN_RADIUS: float = 18.0
const ARC_STEP_DEGREES: float = 30.0
const NORTH_STRAIGHT_Z: float = 18.0
const SOUTH_STRAIGHT_Z: float = -18.0
const EAST_ARC_CENTER_X: float = 45.0
const WEST_ARC_CENTER_X: float = -45.0
const S_CURVE_DIP: float = 4.0
const CURVE_Y: float = 0.4

const STRAIGHT_INNER_X: float = 20.0
const STRAIGHT_OUTER_X: float = 45.0
const S_CURVE_X: float = 5.0


func _ready() -> void:
	curve = Curve3D.new()
	for point: Vector3 in _build_points():
		curve.add_point(point)


## Builds one closed loop: north straight (with chicane), east hairpin arc,
## south straight (with mirrored chicane), west hairpin arc, loop close.
func _build_points() -> Array[Vector3]:
	var points: Array[Vector3] = []
	points.append(Vector3(-STRAIGHT_OUTER_X, CURVE_Y, NORTH_STRAIGHT_Z))
	points.append(Vector3(-STRAIGHT_INNER_X, CURVE_Y, NORTH_STRAIGHT_Z))
	points.append(Vector3(-S_CURVE_X, CURVE_Y, NORTH_STRAIGHT_Z - S_CURVE_DIP))
	points.append(Vector3(S_CURVE_X, CURVE_Y, NORTH_STRAIGHT_Z))
	points.append(Vector3(STRAIGHT_OUTER_X, CURVE_Y, NORTH_STRAIGHT_Z))
	points.append_array(_build_arc(EAST_ARC_CENTER_X, 90.0, -90.0))
	points.append(Vector3(STRAIGHT_OUTER_X, CURVE_Y, SOUTH_STRAIGHT_Z))
	points.append(Vector3(STRAIGHT_INNER_X, CURVE_Y, SOUTH_STRAIGHT_Z))
	points.append(Vector3(S_CURVE_X, CURVE_Y, SOUTH_STRAIGHT_Z + S_CURVE_DIP))
	points.append(Vector3(-S_CURVE_X, CURVE_Y, SOUTH_STRAIGHT_Z))
	points.append(Vector3(-STRAIGHT_OUTER_X, CURVE_Y, SOUTH_STRAIGHT_Z))
	# -270 (not 90) so the sweep goes the long way around through the outer
	# apex at 180 degrees instead of cutting back through the track's middle.
	points.append_array(_build_arc(WEST_ARC_CENTER_X, -90.0, -270.0))
	points.append(Vector3(-STRAIGHT_OUTER_X, CURVE_Y, NORTH_STRAIGHT_Z))
	return points


## Returns the interior arc points (excluding both tangent endpoints, which
## the adjoining straights already provide) sweeping from `from_degrees` to
## `to_degrees` around `center_x` at `HAIRPIN_RADIUS`. `to_degrees` may exceed
## +/-180 so the caller can force the sweep the long way around the circle.
func _build_arc(center_x: float, from_degrees: float, to_degrees: float) -> Array[Vector3]:
	var points: Array[Vector3] = []
	var direction: float = signf(to_degrees - from_degrees)
	var angle: float = from_degrees + direction * ARC_STEP_DEGREES
	while direction * (to_degrees - angle) > 0.01:
		var radians: float = deg_to_rad(angle)
		points.append(Vector3(
			center_x + HAIRPIN_RADIUS * cos(radians), CURVE_Y, HAIRPIN_RADIUS * sin(radians),
		))
		angle += direction * ARC_STEP_DEGREES
	return points
