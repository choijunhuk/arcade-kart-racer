extends ContentTrack

## Lumen Underpass: two S-chicanes lead into a long sweeping bend, then a
## tightening compound hairpin with a shortcut cutting its inner apex.
##
## The layout is a closed "stadium" loop (chicanes -> 180 deg sweeper ->
## back straight -> 180 deg compound hairpin -> closing straight) authored
## as exact circular arcs so it closes without drift. Radii/angles below are
## solved offline (see docs/phase18d track-redesign notes) so SWEEPER_RADIUS
## and CLOSING_STRAIGHT carry fractional precision on purpose - rounding
## them would reopen the seam gap.

const START_Z: float = -130.0
const GRID_STRAIGHT: float = 85.0
const LINK_A: float = 11.0
const LINK_B: float = 18.0
const LINK_C: float = 21.0
const CHICANE_RADIUS: float = 40.0
const CHICANE_ANGLE: float = 19.0
const SWEEPER_RADIUS: float = 87.51342217980729
const SWEEPER_ANGLE: float = 180.0
const BACK_STRAIGHT: float = 378.0
const HAIRPIN_RADIUS_WIDE: float = 95.0
const HAIRPIN_ANGLE_WIDE: float = 140.0
const HAIRPIN_RADIUS_TIGHT: float = 31.0
const HAIRPIN_ANGLE_TIGHT: float = 40.0
const CLOSING_STRAIGHT: float = 232.04750230679346

## Offsets (metres along the racing line) where the PrismAlley shortcut cuts
## the inner (left) apex of the compound hairpin: from 85% through the wide
## stage to 10% into the closing straight. Solved alongside the layout above.
const ALLEY_ENTRY_OFFSET: float = 1038.292338
const ALLEY_EXIT_OFFSET: float = 1117.957773
const ALLEY_LATERAL: float = -10.0
const ALLEY_SPEED: float = 30.0

const TUNNEL_START_FRACTION: float = 0.39
const TUNNEL_END_FRACTION: float = 0.60
const TUNNEL_HEIGHT: float = 7.0
const GATE_FRACTIONS: Array[float] = [0.45, 0.54]
const BOOST_BASE_FRACTION: float = 0.87
const BOOST_COUNT: int = 3
const BOOST_SPACING: float = 12.0

const OBSTACLE_SCENE: PackedScene = preload("res://track/elements/moving_obstacle.tscn")

var _cursor: Vector2 = Vector2.ZERO
var _heading: float = 0.0


## Opens the main road's left wall over the hairpin apex the alley cuts.
func open_inner_wall(point: Vector3) -> bool:
	var offset: float = line.offset_at(point)
	return offset > ALLEY_ENTRY_OFFSET and offset < ALLEY_EXIT_OFFSET


func authored_points() -> Array[Vector3]:
	var points: Array[Vector3] = []
	_cursor = Vector2(0.0, START_Z)
	_heading = 0.0
	points.append(_here())
	_straight(GRID_STRAIGHT, points)
	_straight(LINK_A, points)
	_arc(CHICANE_RADIUS, -CHICANE_ANGLE, points)
	_arc(CHICANE_RADIUS, CHICANE_ANGLE, points)
	_straight(LINK_B, points)
	_arc(CHICANE_RADIUS, CHICANE_ANGLE, points)
	_arc(CHICANE_RADIUS, -CHICANE_ANGLE, points)
	_straight(LINK_C, points)
	_arc(SWEEPER_RADIUS, -SWEEPER_ANGLE, points)
	_straight(BACK_STRAIGHT, points)
	_arc(HAIRPIN_RADIUS_WIDE, -HAIRPIN_ANGLE_WIDE, points)
	_arc(HAIRPIN_RADIUS_TIGHT, -HAIRPIN_ANGLE_TIGHT, points)
	_straight(CLOSING_STRAIGHT, points)
	return points


func build_theme() -> void:
	_build_tunnel()
	_build_sliding_gates()
	_build_boost_pads()
	_add_alley()


func _build_tunnel() -> void:
	var start_offset: float = line.length() * TUNNEL_START_FRACTION
	var end_offset: float = line.length() * TUNNEL_END_FRACTION
	var tunnel_start: Vector3 = line.sample(start_offset)
	var tunnel_end: Vector3 = line.sample(end_offset)
	TrackBuilder.add_box_segment(geometry, tunnel_start + Vector3.UP * TUNNEL_HEIGHT,
		tunnel_end + Vector3.UP * TUNNEL_HEIGHT, road_width + 2.0, 1.0, road_material)
	for side: float in [-1.0, 1.0]:
		var lateral: Vector3 = line.right_at(start_offset) * side * (road_width + 1.0) * 0.5
		TrackBuilder.add_box_segment(geometry,
			tunnel_start + lateral + Vector3.UP * TUNNEL_HEIGHT * 0.5,
			tunnel_end + lateral + Vector3.UP * TUNNEL_HEIGHT * 0.5,
			1.0, TUNNEL_HEIGHT, wall_material)


func _build_sliding_gates() -> void:
	for index: int in range(GATE_FRACTIONS.size()):
		var offset: float = line.length() * GATE_FRACTIONS[index]
		var gate: MovingObstacle = place(OBSTACLE_SCENE, "MovingObstacles", "SlidingGate%d" % index, offset) as MovingObstacle
		var side: float = -1.0 if index == 0 else 1.0
		gate.path = make_path("MovingObstacles", "GatePath%d" % index, [
			line.sample(offset) + line.right_at(offset) * 7.0 * side + Vector3.UP,
			line.sample(offset) + line.right_at(offset) * 11.0 * side + Vector3.UP,
		])
		gate.loop = false
		gate.speed = 2.0


func _build_boost_pads() -> void:
	var base_offset: float = line.length() * BOOST_BASE_FRACTION
	for index: int in range(BOOST_COUNT):
		place(BOOST_SCENE, "BoostPads", "NeonBoost%d" % index, base_offset + float(index) * BOOST_SPACING)


func _add_alley() -> void:
	var entry_point: Vector3 = line.sample(ALLEY_ENTRY_OFFSET) + line.right_at(ALLEY_ENTRY_OFFSET) * ALLEY_LATERAL
	var exit_point: Vector3 = line.sample(ALLEY_EXIT_OFFSET) + line.right_at(ALLEY_EXIT_OFFSET) * ALLEY_LATERAL
	shortcut("PrismAlley", ALLEY_ENTRY_OFFSET, ALLEY_EXIT_OFFSET, [entry_point, exit_point], ALLEY_SPEED)


func _here() -> Vector3:
	return Vector3(_cursor.x, 0.0, _cursor.y)


func _straight(length: float, points: Array[Vector3]) -> void:
	var direction: Vector2 = Vector2(cos(deg_to_rad(_heading)), sin(deg_to_rad(_heading)))
	_cursor += direction * length
	points.append(_here())


## Exact circular arc (matches ContentTrack's own corner math): turn_degrees
## is signed (positive left/CCW, negative right/CW). Appends one point per
## ARC_STEP degrees so curvature and self-intersection read correctly.
func _arc(radius: float, turn_degrees: float, points: Array[Vector3]) -> void:
	var sign_t: float = 1.0 if turn_degrees > 0.0 else -1.0
	var center: Vector2 = _cursor + radius * Vector2(cos(deg_to_rad(_heading + 90.0 * sign_t)), sin(deg_to_rad(_heading + 90.0 * sign_t)))
	var start_angle: float = _heading - 90.0 * sign_t
	var steps: int = maxi(1, roundi(absf(turn_degrees) / ARC_STEP))
	for step: int in range(1, steps + 1):
		var angle: float = deg_to_rad(start_angle + turn_degrees * float(step) / float(steps))
		_cursor = center + radius * Vector2(cos(angle), sin(angle))
		points.append(_here())
	_heading += turn_degrees
