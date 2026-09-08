class_name ItemBox
extends Area3D

## Track element: collectible box. Only hide/respawn + a generic pickup
## signal live here; ItemManager owns effects. Track must
## not reference Kart (spec §6.5), so this never casts the entering body.

signal collected(body: Node3D)

@export var respawn_time: float = 3.0
@export var spin_speed_degrees: float = 90.0

@onready var _mesh: MeshInstance3D = $Mesh
@onready var _collision: CollisionShape3D = $CollisionShape3D

var _respawn_remaining: float = 0.0
var _hidden: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	if _hidden:
		_respawn_remaining = maxf(0.0, _respawn_remaining - delta)
		if is_zero_approx(_respawn_remaining):
			_respawn()
		return
	_mesh.rotate_y(deg_to_rad(spin_speed_degrees) * delta)


func _on_body_entered(body: Node3D) -> void:
	if _hidden:
		return
	_hidden = true
	_mesh.visible = false
	# Deferred: toggling a shape's `disabled` state from inside `body_entered`
	# mutates the physics space while it is still flushing this very query,
	# which the engine rejects (`flushing_queries` assert).
	_collision.set_deferred(&"disabled", true)
	_respawn_remaining = respawn_time
	collected.emit(body)


func _respawn() -> void:
	_hidden = false
	_mesh.visible = true
	_collision.set_deferred(&"disabled", false)
