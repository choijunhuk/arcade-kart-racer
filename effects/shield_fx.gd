class_name ShieldFx
extends Node

## Presentation-only driver for the Aegis bubble shader: gives each pooled
## bubble its own material, plays a ripple when the shield appears and when
## its owner is bumped or struck. Reads only the parent item's owner_kart.

const RIPPLE_SECONDS: float = 0.45

@export var mesh_path: NodePath = ^"../Mesh"

var _material: ShaderMaterial
var _ripple: float = 0.0
var _was_visible: bool = false


func _ready() -> void:
	var mesh_node: MeshInstance3D = get_node_or_null(mesh_path) as MeshInstance3D
	if mesh_node != null and mesh_node.mesh != null:
		mesh_node.mesh = mesh_node.mesh.duplicate(true)
		_material = mesh_node.mesh.surface_get_material(0) as ShaderMaterial
	EventBus.kart_contacted.connect(_on_owner_event)
	EventBus.kart_hit.connect(_on_owner_hit)


func _exit_tree() -> void:
	if EventBus.kart_contacted.is_connected(_on_owner_event):
		EventBus.kart_contacted.disconnect(_on_owner_event)
	if EventBus.kart_hit.is_connected(_on_owner_hit):
		EventBus.kart_hit.disconnect(_on_owner_hit)


func _process(delta: float) -> void:
	var item: Node3D = get_parent() as Node3D
	var showing: bool = item != null and item.is_visible_in_tree()
	if showing and not _was_visible:
		_start_ripple(Vector3.UP)
	_was_visible = showing
	if _material == null or _ripple <= 0.0:
		return
	_ripple = maxf(0.0, _ripple - delta / RIPPLE_SECONDS)
	_material.set_shader_parameter("ripple", _ripple)


func _on_owner_hit(kart: Node, _hit_type: int) -> void:
	_on_owner_event(kart)


func _on_owner_event(kart: Node) -> void:
	var item: Node = get_parent()
	if item == null or kart == null or kart != item.get("owner_kart"):
		return
	var forward: Vector3 = (kart as Node3D).global_basis.z * -1.0
	_start_ripple(forward)


func _start_ripple(direction: Vector3) -> void:
	_ripple = 1.0
	if _material != null:
		_material.set_shader_parameter("ripple_dir", direction)
		_material.set_shader_parameter("ripple", _ripple)
