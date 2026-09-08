class_name ImpactEffect
extends Node3D

## One pooled CPU-particle burst shared by item, wall, and landing feedback.

enum Kind {
	ITEM,
	WALL,
	LANDING,
}

const ITEM_COLOR: Color = Color(1.0, 0.28, 0.08, 0.9)
const WALL_COLOR: Color = Color(1.0, 0.82, 0.2, 0.9)
const LANDING_COLOR: Color = Color(0.62, 0.48, 0.32, 0.65)
const IMPACT_GROWTH_RATE: float = 3.0

@export var tuning: FeelTuning = preload("res://data/tuning/feel_default.tres")

@onready var _particles: CPUParticles3D = $Particles
@onready var _burst: MeshInstance3D = $Burst

var _remaining: float = 0.0
var _burst_material: StandardMaterial3D


func _ready() -> void:
	_burst_material = (_burst.get_active_material(0) as StandardMaterial3D).duplicate() as StandardMaterial3D
	_burst.material_override = _burst_material


## Restarts a typed burst at a world-space impact point.
func play(world_position: Vector3, kind: Kind = Kind.ITEM) -> void:
	global_position = world_position
	_remaining = tuning.impact_duration
	visible = true
	scale = Vector3.ONE
	var color: Color = _color_for(kind)
	_particles.color = color
	_particles.emitting = false
	_particles.restart()
	_particles.emitting = true
	_burst_material.albedo_color = color
	_burst_material.emission = color


## Advances presentation lifetime and returns true on completion.
func tick(delta: float) -> bool:
	_remaining = maxf(0.0, _remaining - maxf(delta, 0.0))
	var elapsed: float = tuning.impact_duration - _remaining
	scale = Vector3.ONE * (1.0 + elapsed * IMPACT_GROWTH_RATE)
	if _remaining <= 0.0:
		_particles.emitting = false
	return _remaining <= 0.0


func _color_for(kind: Kind) -> Color:
	match kind:
		Kind.WALL:
			return WALL_COLOR
		Kind.LANDING:
			return LANDING_COLOR
		_:
			return ITEM_COLOR
