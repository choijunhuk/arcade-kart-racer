class_name RaceMinimap
extends Control

const UPDATE_INTERVAL_SECONDS: float = 0.1
const CONTENT_MARGIN: float = 10.0
const RIVAL_DOT_SCALE: Vector2 = Vector2.ONE
const PLAYER_DOT_SCALE: Vector2 = Vector2.ONE * 1.6
const DOT_RADIUS: float = 4.5
const DOT_OUTLINE: float = 1.8
const DOT_SEGMENTS: int = 12
const OUTLINE_COLOR: Color = Color(0.02, 0.03, 0.07, 1.0)
const PLAYER_RING_COLOR: Color = Color(1.0, 1.0, 1.0, 1.0)
## Grid-slot palette used when a kart's driver exposes no livery colour.
const FALLBACK_COLORS: Array[Color] = [
	Color(1.0, 0.82, 0.12), Color(0.18, 0.78, 1.0), Color(1.0, 0.28, 0.12), Color(0.24, 0.82, 0.35),
	Color(0.95, 0.22, 0.72), Color(0.58, 0.34, 1.0), Color(0.12, 0.88, 0.72), Color(0.92, 0.92, 0.95),
]
## DriverData colour properties in preference order (livery_primary is
## added by the kart-visuals lane; driver_color is the existing field).
const LIVERY_PROPERTIES: Array[StringName] = [&"livery_primary", &"driver_color"]
## Ribbon widths as a fraction of the drawable height (scale with split screen).
const RIBBON_EDGE_RATIO: float = 0.1
const RIBBON_ROAD_RATIO: float = 0.065
const RIBBON_CENTER_RATIO: float = 0.012

@onready var _track_edge: Line2D = $TrackEdge
@onready var _track_line: Line2D = $TrackLine
@onready var _track_center: Line2D = $TrackCenter
@onready var _start_marker: Polygon2D = $StartMarker
@onready var _dots_root: Node2D = $Dots

var _world_points: PackedVector3Array = PackedVector3Array()
var _karts: Array[KartController] = []
var _player_kart: KartController
var _dots: Dictionary[int, Polygon2D] = {}
var _elapsed: float = 0.0


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < UPDATE_INTERVAL_SECONDS:
		return
	_elapsed = fmod(_elapsed, UPDATE_INTERVAL_SECONDS)
	force_update()


## Bakes the track line once and registers fixed race participants for 10 Hz dots.
func bind(line: RacingLine, karts: Array[KartController], player_kart: KartController) -> void:
	_world_points = PackedVector3Array()
	if line != null:
		for local_point: Vector3 in line.get_baked_points():
			_world_points.append(line.to_global(local_point))
	_karts = karts.duplicate()
	_player_kart = player_kart
	_rebuild_track_line()
	_rebuild_dots()
	force_update()


## Refreshes every registered kart dot using the cached track bounds.
func force_update() -> void:
	if _world_points.is_empty():
		return
	for kart: KartController in _karts:
		if not is_instance_valid(kart):
			continue
		var dot: Polygon2D = _dots.get(kart.get_instance_id()) as Polygon2D
		if dot == null:
			continue
		dot.position = _to_canvas(MinimapProjection.project_point(kart.global_position, _world_points))


## Reprojects cached geometry after a split-screen viewport resize.
func refresh_layout() -> void:
	_rebuild_track_line()
	force_update()


func _rebuild_track_line() -> void:
	var canvas_points: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in MinimapProjection.normalize_points(_world_points):
		canvas_points.append(_to_canvas(point))
	var span: float = maxf(minf(size.x, size.y) - CONTENT_MARGIN * 2.0, 40.0)
	for pair: Array in [[_track_edge, RIBBON_EDGE_RATIO], [_track_line, RIBBON_ROAD_RATIO], [_track_center, RIBBON_CENTER_RATIO]]:
		var line: Line2D = pair[0] as Line2D
		line.points = canvas_points
		line.width = maxf(1.0, span * float(pair[1]))
	_start_marker.visible = canvas_points.size() > 1
	if _start_marker.visible:
		var tangent: Vector2 = (canvas_points[1] - canvas_points[0]).normalized()
		_start_marker.position = canvas_points[0]
		_start_marker.rotation = tangent.angle()
		_start_marker.scale = Vector2.ONE * span * RIBBON_EDGE_RATIO / 16.0


func _rebuild_dots() -> void:
	for child: Node in _dots_root.get_children():
		child.free()
	_dots.clear()
	for index: int in range(_karts.size()):
		var kart: KartController = _karts[index]
		var is_player: bool = kart == _player_kart
		# The dot node itself is the outline ring; the livery fill sits on top.
		var dot: Polygon2D = Polygon2D.new()
		dot.name = "Player" if is_player else "Rival"
		dot.polygon = _circle(DOT_RADIUS + DOT_OUTLINE)
		dot.color = PLAYER_RING_COLOR if is_player else OUTLINE_COLOR
		dot.scale = PLAYER_DOT_SCALE if is_player else RIVAL_DOT_SCALE
		dot.z_index = 2 if is_player else 1
		var fill: Polygon2D = Polygon2D.new()
		fill.name = "Fill"
		fill.polygon = _circle(DOT_RADIUS - (0.6 if is_player else 0.0))
		fill.color = kart_color(kart, index)
		dot.add_child(fill)
		_dots_root.add_child(dot)
		_dots[kart.get_instance_id()] = dot


## Livery colour of a kart's driver, read defensively: `livery_primary`
## when DriverData exposes it, else `driver_color`, else a fixed palette
## entry by grid order. An unset (white) colour falls through.
static func kart_color(kart: KartController, index: int) -> Color:
	var driver: Resource = kart.get(&"driver_data") as Resource
	if driver != null:
		for property: StringName in LIVERY_PROPERTIES:
			if not property in driver:
				continue
			var color: Variant = driver.get(property)
			if color is Color and color != Color.WHITE:
				return color as Color
	return FALLBACK_COLORS[index % FALLBACK_COLORS.size()]


static func _circle(radius: float) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	for step: int in range(DOT_SEGMENTS):
		points.append(Vector2.from_angle(TAU * float(step) / float(DOT_SEGMENTS)) * radius)
	return points


func _to_canvas(normalized: Vector2) -> Vector2:
	var drawable: Vector2 = Vector2(
		maxf(size.x - CONTENT_MARGIN * 2.0, 1.0),
		maxf(size.y - CONTENT_MARGIN * 2.0, 1.0),
	)
	return Vector2(
		CONTENT_MARGIN + normalized.x * drawable.x,
		CONTENT_MARGIN + (1.0 - normalized.y) * drawable.y,
	)
