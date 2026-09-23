class_name ItemFx
extends Node3D

## Presentation-only idle motion for item models: spins the optional
## "Spinner" child, bobs this node, and pulses the optional "Blink" child's
## emission so hazards read at a glance. Never touches gameplay state.

## Turns this node so its -Z follows the parent item's travel direction.
@export var face_travel: bool = false
@export var spin_speed: float = 0.0
@export var bob_height: float = 0.0
@export var bob_speed: float = 3.0
@export var blink_speed: float = 0.0
@export var blink_energy: float = 4.0

var _time: float = 0.0
var _base_y: float = 0.0
var _spinner: Node3D
var _blink_material: StandardMaterial3D


func _ready() -> void:
	_base_y = position.y
	_time = randf() * TAU
	_spinner = get_node_or_null(^"Spinner") as Node3D
	var blink: MeshInstance3D = get_node_or_null(^"Blink") as MeshInstance3D
	if blink != null and blink.material_override is StandardMaterial3D:
		_blink_material = (blink.material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
		blink.material_override = _blink_material


func _process(delta: float) -> void:
	_time += delta
	if face_travel:
		_face_travel()
	if _spinner != null and spin_speed != 0.0:
		_spinner.rotate_y(spin_speed * delta)
	if bob_height > 0.0:
		position.y = _base_y + sin(_time * bob_speed) * bob_height
	if _blink_material != null and blink_speed > 0.0:
		var pulse: float = 0.5 + 0.5 * sin(_time * blink_speed)
		_blink_material.emission_energy_multiplier = blink_energy * pulse * pulse


func _face_travel() -> void:
	var item: Node = get_parent()
	if item == null or not item.has_method("get_travel_direction"):
		return
	var direction: Vector3 = item.call("get_travel_direction") as Vector3
	if direction.length_squared() > 0.0001 and absf(direction.normalized().dot(Vector3.UP)) < 0.99:
		global_basis = Basis.looking_at(direction, Vector3.UP)
