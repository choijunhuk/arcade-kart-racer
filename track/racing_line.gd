class_name RacingLine
extends Path3D

const PLACEHOLDER_POINTS: Array[Vector3] = [
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


func _ready() -> void:
	if curve == null or curve.point_count == 0:
		_build_placeholder_curve()


func _build_placeholder_curve() -> void:
	# PLACEHOLDER: Phase 4 replaces these points with authored racing-line data.
	curve = Curve3D.new()
	for point: Vector3 in PLACEHOLDER_POINTS:
		curve.add_point(point)
