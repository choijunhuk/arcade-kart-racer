class_name Track01
extends TrackRoot

## Track 01 "Ridgeline Circuit" (spec §15.7): builds its road/wall geometry
## procedurally from RacingLine's baked curve once the base class has
## validated the scene contract and configured checkpoints (both require
## RacingLine already baked, which is guaranteed here since Track._ready()
## runs after every child's own _ready(), spec: children ready before parents).

const ROAD_WIDTH: float = 14.0
const ROAD_HEIGHT: float = 0.4
const WALL_HEIGHT: float = 2.0
const WALL_THICKNESS: float = 1.0
const WALL_HALF_OFFSET: float = 7.5
## Fraction of the lap (from the end) with no outer wall: the mandatory
## "cliff corner" (spec §15.7) sits on the closing (east) arc.
const CLIFF_SPAN_FRACTION: float = 0.09

@onready var _geometry: StaticBody3D = $Geometry

var _road_material: StandardMaterial3D = _make_material(Color(0.27, 0.29, 0.33))
var _wall_material: StandardMaterial3D = _make_material(Color(0.95, 0.35, 0.08))


func _ready() -> void:
	super._ready()
	_build_geometry()


func _build_geometry() -> void:
	var racing_line: RacingLine = get_racing_line()
	if racing_line == null:
		return
	TrackBuilder.build_road_segments(_geometry, racing_line, ROAD_WIDTH, ROAD_HEIGHT, _road_material)
	_build_wall_ribbon(racing_line, WALL_HALF_OFFSET, true)
	_build_wall_ribbon(racing_line, -WALL_HALF_OFFSET, false)
	_build_local_curve("MovingObstacles/BarrierPathA", [Vector3(0.0, 0.0, -5.0), Vector3(0.0, 0.0, 5.0)])
	_build_local_curve("MovingObstacles/BarrierPathB", [Vector3(0.0, 0.0, -4.0), Vector3(0.0, 0.0, 4.0)])
	_build_local_curve("Shortcuts/HairpinCutoff/AltCurve", [Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.0, 40.0)])


## Assigns a straight-line `Curve3D` (in the node's own local space) to the
## `Path3D` at `path`. Kept out of the scene file itself: every other track
## in this project builds its curves from code rather than hand-serializing
## `Curve3D` resources, whose text-scene format is undocumented/fragile.
func _build_local_curve(path: NodePath, points: Array[Vector3]) -> void:
	var target: Path3D = get_node_or_null(path) as Path3D
	if target == null:
		return
	var curve: Curve3D = Curve3D.new()
	for point: Vector3 in points:
		curve.add_point(point)
	target.curve = curve


func _build_wall_ribbon(racing_line: RacingLine, lateral_offset: float, skip_cliff: bool) -> void:
	var length: float = racing_line.length()
	if length <= 0.0:
		return
	var step: float = 8.0
	var steps: int = maxi(1, int(ceil(length / step)))
	var cliff_start: float = length * (1.0 - CLIFF_SPAN_FRACTION)
	for index: int in range(steps):
		var start_offset: float = length * float(index) / float(steps)
		var end_offset: float = length * float(index + 1) / float(steps)
		if skip_cliff and start_offset >= cliff_start:
			continue
		var start_point: Vector3 = racing_line.sample(start_offset) + racing_line.right_at(start_offset) * lateral_offset
		var end_point: Vector3 = racing_line.sample(end_offset) + racing_line.right_at(end_offset) * lateral_offset
		TrackBuilder.add_box_segment(_geometry, start_point, end_point, WALL_THICKNESS, WALL_HEIGHT, _wall_material)


static func _make_material(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	return material
