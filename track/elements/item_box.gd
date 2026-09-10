class_name ItemBox
extends Area3D

## Track element: collectible box. Only hide/respawn + a generic pickup
## signal live here; ItemManager owns effects. Track must
## not reference Kart (spec §6.5), so this never casts the entering body.

signal collected(body: Node3D)
signal availability_changed(available: bool)

@export var respawn_time: float = 3.0
@export var spin_speed_degrees: float = 90.0

@onready var _mesh: MeshInstance3D = $Mesh
@onready var _collision: CollisionShape3D = $CollisionShape3D

var network_replica: bool = false

var _respawn_remaining: float = 0.0
var _hidden: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	var paint: StandardMaterial3D = PrimitiveArt.material(Color(0.15, 0.8, 1.0, 0.3), true)
	paint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mesh.material_override = paint
	var icon: Label3D = Label3D.new()
	icon.text = "?"
	icon.font_size = 96
	icon.pixel_size = 0.008
	icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_mesh.add_child(icon)


func _physics_process(delta: float) -> void:
	if _hidden:
		if network_replica:
			return
		_respawn_remaining = maxf(0.0, _respawn_remaining - delta)
		if is_zero_approx(_respawn_remaining):
			_respawn()
		return
	_mesh.rotate_y(deg_to_rad(spin_speed_degrees) * delta)


func _on_body_entered(body: Node3D) -> void:
	if network_replica or _hidden:
		return
	_hidden = true
	_mesh.visible = false
	# Deferred: toggling a shape's `disabled` state from inside `body_entered`
	# mutates the physics space while it is still flushing this very query,
	# which the engine rejects (`flushing_queries` assert).
	_collision.set_deferred(&"disabled", true)
	_respawn_remaining = respawn_time
	collected.emit(body)
	availability_changed.emit(false)


func _respawn() -> void:
	_hidden = false
	_mesh.visible = true
	_collision.set_deferred(&"disabled", false)
	availability_changed.emit(true)

## Applies a server availability event without collecting or starting a local timer.
func apply_network_available(available: bool) -> void:
	_hidden = not available
	_mesh.visible = available
	_collision.set_deferred(&"disabled", not available)
