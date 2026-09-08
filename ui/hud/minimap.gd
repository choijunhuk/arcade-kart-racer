class_name RaceMinimap
extends Control

const UPDATE_INTERVAL_SECONDS: float = 0.1
const CONTENT_MARGIN: float = 10.0
const RIVAL_DOT_COLOR: Color = Color(0.82, 0.9, 1.0, 1.0)
const PLAYER_DOT_COLOR: Color = Color(1.0, 0.82, 0.12, 1.0)
const RIVAL_DOT_SCALE: Vector2 = Vector2.ONE
const PLAYER_DOT_SCALE: Vector2 = Vector2.ONE * 1.6
const DOT_HALF_SIZE: float = 3.5

@onready var _track_line: Line2D = $TrackLine
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


func _rebuild_track_line() -> void:
	var canvas_points: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in MinimapProjection.normalize_points(_world_points):
		canvas_points.append(_to_canvas(point))
	_track_line.points = canvas_points


func _rebuild_dots() -> void:
	for child: Node in _dots_root.get_children():
		child.free()
	_dots.clear()
	var polygon: PackedVector2Array = PackedVector2Array([
		Vector2(-DOT_HALF_SIZE, -DOT_HALF_SIZE),
		Vector2(DOT_HALF_SIZE, -DOT_HALF_SIZE),
		Vector2(DOT_HALF_SIZE, DOT_HALF_SIZE),
		Vector2(-DOT_HALF_SIZE, DOT_HALF_SIZE),
	])
	for kart: KartController in _karts:
		var dot: Polygon2D = Polygon2D.new()
		dot.name = "Player" if kart == _player_kart else "Rival"
		dot.polygon = polygon
		dot.color = PLAYER_DOT_COLOR if kart == _player_kart else RIVAL_DOT_COLOR
		dot.scale = PLAYER_DOT_SCALE if kart == _player_kart else RIVAL_DOT_SCALE
		_dots_root.add_child(dot)
		_dots[kart.get_instance_id()] = dot


func _to_canvas(normalized: Vector2) -> Vector2:
	var drawable: Vector2 = Vector2(
		maxf(size.x - CONTENT_MARGIN * 2.0, 1.0),
		maxf(size.y - CONTENT_MARGIN * 2.0, 1.0),
	)
	return Vector2(
		CONTENT_MARGIN + normalized.x * drawable.x,
		CONTENT_MARGIN + (1.0 - normalized.y) * drawable.y,
	)
