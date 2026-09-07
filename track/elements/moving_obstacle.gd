class_name MovingObstacle
extends AnimatableBody3D

## Track element: patrols `path` (sampling `Curve3D` directly rather than a
## child `PathFollow3D` node, which must live under the `Path3D` it follows
## and would force an awkward parent swap between this body's mesh/collision
## and its route). Stays on layer 1 like static geometry so existing kart
## wall-collision handling treats contact as a wall with no Kart reference
## needed here (spec §15.3).

@export var path: Path3D
@export var speed: float = 6.0
@export var loop: bool = true

var _ratio: float = 0.0
var _direction: float = 1.0


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	sync_to_physics = true


func _physics_process(delta: float) -> void:
	if path == null or path.curve == null:
		return
	var length: float = path.curve.get_baked_length()
	if length <= 0.0:
		return
	_advance(delta, length)
	global_position = path.to_global(path.curve.sample_baked(_ratio * length))


func _advance(delta: float, length: float) -> void:
	var step: float = _direction * speed * delta / length
	if loop:
		_ratio = fposmod(_ratio + step, 1.0)
		return
	_ratio += step
	if _ratio >= 1.0:
		_ratio = 1.0
		_direction = -1.0
	elif _ratio <= 0.0:
		_ratio = 0.0
		_direction = 1.0
