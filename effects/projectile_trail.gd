class_name ProjectileTrail
extends MeshInstance3D

## Presentation-only glowing ribbon behind a moving (pooled) item. Samples the
## parent's world position, faces the active camera, fades toward the tail and
## resets itself whenever the item is hidden or teleported (pool reuse).

@export var trail_color: Color = Color(1.0, 0.45, 0.1, 0.9)
@export var head_width: float = 0.34
@export var max_points: int = 18
@export var min_spacing: float = 0.35

const TELEPORT_DISTANCE: float = 6.0

var _points: Array[Vector3] = []
var _array_mesh: ArrayMesh = ArrayMesh.new()
var _target: Node3D
## Reused per frame (resized/overwritten in place) so the ribbon rebuild does
## not allocate fresh Packed arrays every _process.
var _vertices: PackedVector3Array = PackedVector3Array()
var _colors: PackedColorArray = PackedColorArray()
var _indices: PackedInt32Array = PackedInt32Array()
var _arrays: Array = []


func _ready() -> void:
	_target = get_parent() as Node3D
	set_as_top_level(true)
	global_transform = Transform3D.IDENTITY
	mesh = _array_mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.vertex_color_use_as_albedo = true
	material_override = material


func _process(_delta: float) -> void:
	if _target == null or not _target.is_visible_in_tree():
		_reset()
		return
	var head: Vector3 = _target.global_position
	if not _points.is_empty() and _points[0].distance_to(head) > TELEPORT_DISTANCE:
		_points.clear()
	# _points[0] is the live head; a new committed point is added each time
	# the head gets min_spacing away from the previous committed one.
	if _points.is_empty():
		_points.append(head)
	_points[0] = head
	if _points.size() < 2 or _points[1].distance_to(head) >= min_spacing:
		_points.push_front(head)
		if _points.size() > max_points:
			_points.pop_back()
	visible = true
	_rebuild()


func _reset() -> void:
	if _points.is_empty():
		return
	_points.clear()
	_array_mesh.clear_surfaces()
	visible = false


func _rebuild() -> void:
	_array_mesh.clear_surfaces()
	var camera: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if _points.size() < 2 or camera == null:
		return
	var last: int = _points.size() - 1
	_vertices.resize(_points.size() * 2)
	_colors.resize(_points.size() * 2)
	_indices.resize(last * 6)
	for index: int in range(_points.size()):
		var along: Vector3 = _points[maxi(index - 1, 0)] - _points[mini(index + 1, last)]
		var to_camera: Vector3 = camera.global_position - _points[index]
		var side: Vector3 = along.cross(to_camera).normalized()
		var fade: float = 1.0 - float(index) / float(last)
		var half: float = head_width * 0.5 * lerpf(0.25, 1.0, fade)
		var color: Color = Color(trail_color, trail_color.a * fade * fade)
		_vertices[index * 2] = _points[index] - side * half
		_vertices[index * 2 + 1] = _points[index] + side * half
		_colors[index * 2] = color
		_colors[index * 2 + 1] = color
	for segment: int in range(last):
		var a: int = segment * 2
		var i: int = segment * 6
		_indices[i] = a
		_indices[i + 1] = a + 1
		_indices[i + 2] = a + 2
		_indices[i + 3] = a + 2
		_indices[i + 4] = a + 1
		_indices[i + 5] = a + 3
	if _arrays.size() != Mesh.ARRAY_MAX:
		_arrays.resize(Mesh.ARRAY_MAX)
	_arrays[Mesh.ARRAY_VERTEX] = _vertices
	_arrays[Mesh.ARRAY_COLOR] = _colors
	_arrays[Mesh.ARRAY_INDEX] = _indices
	_array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _arrays)
	# Drop the extra references so the next in-place write does not trigger
	# a copy-on-write of the member arrays.
	_arrays[Mesh.ARRAY_VERTEX] = null
	_arrays[Mesh.ARRAY_COLOR] = null
	_arrays[Mesh.ARRAY_INDEX] = null
