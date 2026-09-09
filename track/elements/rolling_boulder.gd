class_name RollingBoulder
extends Hazard

## A rolling hazard follows an authored route on deterministic physics time.

@export var path: Path3D
@export var speed: float = 5.0
@export var radius: float = 1.4
var distance: float = 0.0


func _physics_process(delta: float) -> void:
	if path == null or path.curve == null:
		return # An unassigned authoring path leaves the obstacle stationary.
	var length: float = path.curve.get_baked_length()
	if length <= 0.0:
		return
	distance = fposmod(distance + speed * delta, length * 2.0)
	var offset: float = distance if distance <= length else length * 2.0 - distance
	global_position = path.to_global(path.curve.sample_baked(offset))
	($Mesh as MeshInstance3D).rotate_x(speed * delta / radius)
