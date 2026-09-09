class_name TimedHazard
extends Hazard

## Sandstorm alternates active/clear phases; entering and staying are both covered.

@export var active_seconds: float = 2.0
@export var clear_seconds: float = 6.0
@export var phase_seconds: float = 0.0
var active: bool = false
var _hit_this_phase: Dictionary[int, bool] = {}


func _physics_process(delta: float) -> void:
	phase_seconds = fposmod(phase_seconds + delta, active_seconds + clear_seconds)
	active = phase_seconds < active_seconds
	$Mesh.visible = active
	if not active:
		_hit_this_phase.clear()
	if active:
		for body: Node3D in get_overlapping_bodies():
			_hit_once(body)


func _on_body_entered(body: Node3D) -> void:
	if active:
		_hit_once(body)


func _hit_once(body: Node3D) -> void:
	var id: int = body.get_instance_id()
	if _hit_this_phase.has(id):
		return
	_hit_this_phase[id] = true
	body_hazard_hit.emit(body, hit_type)
