class_name SkidMark
extends MeshInstance3D

## Continuous ring-buffered tyre strip detached from the moving kart transform.

@export var tuning: FeelTuning = preload("res://data/tuning/feel_default.tres")

const SKID_COLOR: Color = Color(0.04, 0.04, 0.04, 1.0)
const FADE_SECONDS: float = 3.0
var _idle_seconds: float = 0.0

const TANGENT_EPSILON: float = 0.0001

var _kart: KartController
var _buffer: SkidStripBuffer = SkidStripBuffer.new()
var _array_mesh: ArrayMesh = ArrayMesh.new()


func _ready() -> void:
	_kart = get_parent().get_parent() as KartController
	_buffer.configure(tuning.skid_mark_max_segments)
	set_as_top_level(true)
	global_transform = Transform3D.IDENTITY
	mesh = _array_mesh
	material_override = _make_material()


func _process(delta: float) -> void:
	if _kart == null or _kart.get_drift_state() != DriftController.DriftState.HOLD:
		_idle_seconds += delta
		transparency = clampf(_idle_seconds / FADE_SECONDS, 0.0, 1.0)
		return
	if _idle_seconds > 0.0:
		_buffer.configure(tuning.skid_mark_max_segments)
		_array_mesh.clear_surfaces()
	_idle_seconds = 0.0
	transparency = 0.0
	var local_point: Vector3 = to_local(_kart.global_position - Vector3.UP * tuning.skid_mark_ground_offset)
	var points: Array[Vector3] = _buffer.get_points()
	if not points.is_empty() and points.back().distance_to(local_point) < tuning.skid_mark_min_spacing:
		return
	_buffer.add_point(local_point)
	_rebuild_mesh()


## Builds indexed triangle geometry where adjacent quads share one edge pair.
static func build_strip_geometry(
	points: Array[Vector3], half_width: float, maximum_alpha: float,
) -> Dictionary:
	var vertices: PackedVector3Array = PackedVector3Array()
	var colors: PackedColorArray = PackedColorArray()
	var indices: PackedInt32Array = PackedInt32Array()
	if points.size() < 2:
		return {"vertices": vertices, "colors": colors, "indices": indices}
	for index: int in range(points.size()):
		var previous: Vector3 = points[maxi(index - 1, 0)]
		var next: Vector3 = points[mini(index + 1, points.size() - 1)]
		var tangent: Vector3 = next - previous
		tangent.y = 0.0
		var side: Vector3 = tangent.normalized().cross(Vector3.UP) if tangent.length_squared() > TANGENT_EPSILON else Vector3.RIGHT
		vertices.append(points[index] - side * half_width)
		vertices.append(points[index] + side * half_width)
		var age_alpha: float = maximum_alpha * float(index) / float(points.size() - 1)
		var color: Color = Color(SKID_COLOR.r, SKID_COLOR.g, SKID_COLOR.b, age_alpha)
		colors.append(color)
		colors.append(color)
	for segment: int in range(points.size() - 1):
		var left_a: int = segment * 2
		var right_a: int = left_a + 1
		var left_b: int = left_a + 2
		var right_b: int = left_a + 3
		indices.append_array(PackedInt32Array([left_a, right_a, left_b, left_b, right_a, right_b]))
	return {"vertices": vertices, "colors": colors, "indices": indices}


func _rebuild_mesh() -> void:
	_array_mesh.clear_surfaces()
	var geometry: Dictionary = build_strip_geometry(
		_buffer.get_points(), tuning.skid_mark_half_width, tuning.skid_mark_alpha,
	)
	var vertices: PackedVector3Array = geometry["vertices"] as PackedVector3Array
	if vertices.is_empty():
		return
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = geometry["colors"] as PackedColorArray
	arrays[Mesh.ARRAY_INDEX] = geometry["indices"] as PackedInt32Array
	_array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


func _make_material() -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material
