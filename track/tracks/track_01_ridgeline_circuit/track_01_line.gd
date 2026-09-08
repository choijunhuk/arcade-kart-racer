extends RacingLine

## Track 01 "Ridgeline Circuit" racing line (spec §15.7): two ~650m straights
## joined by two 20m-radius end turns (west = the mandatory drift-Tier-3
## hairpin, east = the closing turn), with a mild S-curve chicane on the
## outbound straight. Total baked length lands in the 1,400-1,600m band.

const STRAIGHT_LENGTH: float = 680.0
const ARC_RADIUS: float = 20.0
const SOUTH_Z: float = -20.0
const NORTH_Z: float = 20.0
const CURVE_Y: float = 0.4
const S_CURVE_DIP: float = 14.0
const ARC_STEP_DEGREES: float = 15.0


func _ready() -> void:
	curve = Curve3D.new()
	for point: Vector3 in _build_points():
		curve.add_point(point)


## Builds one closed loop: south straight (start/finish + S-curve chicane),
## west hairpin, north straight (return), east arc closing back to start.
func _build_points() -> Array[Vector3]:
	var points: Array[Vector3] = []
	points.append(Vector3(0.0, CURVE_Y, SOUTH_Z))
	points.append(Vector3(-260.0, CURVE_Y, SOUTH_Z))
	points.append(Vector3(-300.0, CURVE_Y, SOUTH_Z + S_CURVE_DIP))
	points.append(Vector3(-340.0, CURVE_Y, SOUTH_Z - S_CURVE_DIP))
	points.append(Vector3(-380.0, CURVE_Y, SOUTH_Z))
	points.append(Vector3(-STRAIGHT_LENGTH, CURVE_Y, SOUTH_Z))
	points.append_array(_build_arc(-STRAIGHT_LENGTH, -90.0, -270.0))
	points.append(Vector3(-STRAIGHT_LENGTH, CURVE_Y, NORTH_Z))
	points.append(Vector3(-500.0, CURVE_Y, NORTH_Z))
	points.append(Vector3(-350.0, CURVE_Y, NORTH_Z))
	points.append(Vector3(-200.0, CURVE_Y, NORTH_Z))
	points.append(Vector3(-60.0, CURVE_Y, NORTH_Z))
	points.append(Vector3(0.0, CURVE_Y, NORTH_Z))
	points.append_array(_build_arc(0.0, 90.0, -90.0))
	points.append(Vector3(0.0, CURVE_Y, SOUTH_Z))
	return points


## Interior arc points (excluding both tangent endpoints, which the
## adjoining straights already provide) sweeping from `from_degrees` to
## `to_degrees` around `center_x` at `ARC_RADIUS`, matching
## `test_hairpin/hairpin_racing_line.gd`'s proven continuous-curvature pattern.
func _build_arc(center_x: float, from_degrees: float, to_degrees: float) -> Array[Vector3]:
	var points: Array[Vector3] = []
	var direction: float = signf(to_degrees - from_degrees)
	var angle: float = from_degrees + direction * ARC_STEP_DEGREES
	while direction * (to_degrees - angle) > 0.01:
		var radians: float = deg_to_rad(angle)
		points.append(Vector3(
			center_x + ARC_RADIUS * cos(radians), CURVE_Y, ARC_RADIUS * sin(radians),
		))
		angle += direction * ARC_STEP_DEGREES
	return points
