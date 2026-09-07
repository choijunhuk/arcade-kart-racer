class_name SkidMark
extends MeshInstance3D

@export var tuning: FeelTuning = preload("res://data/tuning/feel_default.tres")

var _kart: KartController
var _points: Array[Vector3] = []
var _immediate: ImmediateMesh = ImmediateMesh.new()


func _ready() -> void:
	_kart = get_parent().get_parent() as KartController
	mesh = _immediate


func _process(_delta: float) -> void:
	if _kart == null or _kart.get_drift_state() != DriftController.DriftState.HOLD:
		return
	var local_point: Vector3 = to_local(_kart.global_position) + Vector3.DOWN * 0.28
	if not _points.is_empty() and _points.back().distance_to(local_point) < tuning.skid_mark_min_spacing:
		return
	_points.append(local_point)
	if _points.size() > tuning.skid_mark_max_segments:
		_points.pop_front()
	_rebuild_mesh()


func _rebuild_mesh() -> void:
	_immediate.clear_surfaces()
	if _points.size() < 2:
		return
	_immediate.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for point: Vector3 in _points:
		_immediate.surface_set_color(Color(0.04, 0.04, 0.04, 0.75))
		_immediate.surface_add_vertex(point + Vector3.LEFT * tuning.skid_mark_half_width)
		_immediate.surface_add_vertex(point + Vector3.RIGHT * tuning.skid_mark_half_width)
	_immediate.surface_end()
