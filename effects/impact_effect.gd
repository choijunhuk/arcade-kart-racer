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
## Item explosions linger longer than wall/landing puffs and add a ground shockwave.
const ITEM_DURATION_SCALE: float = 1.8
const RING_START_SCALE: float = 0.6
const RING_END_SCALE: float = 7.0

@export var tuning: FeelTuning = preload("res://data/tuning/feel_default.tres")

@onready var _particles: CPUParticles3D = $Particles
@onready var _burst: MeshInstance3D = $Burst
@onready var _ring: MeshInstance3D = $Ring

var _remaining: float = 0.0
var _duration: float = 0.25
var _burst_color: Color = ITEM_COLOR
var _burst_material: StandardMaterial3D
var _ring_material: StandardMaterial3D


func _ready() -> void:
	_particles.material_override = ParticleArt.material(true)
	_burst_material = (_burst.get_active_material(0) as StandardMaterial3D).duplicate() as StandardMaterial3D
	_burst.material_override = _burst_material
	_ring_material = _make_ring_material()
	_ring.material_override = _ring_material


## Restarts a typed burst at a world-space impact point.
func play(world_position: Vector3, kind: Kind = Kind.ITEM) -> void:
	global_position = world_position
	_duration = tuning.impact_duration * (ITEM_DURATION_SCALE if kind == Kind.ITEM else 1.0)
	_remaining = _duration
	visible = true
	scale = Vector3.ONE
	var color: Color = _color_for(kind)
	_burst_color = color
	_ring.visible = kind != Kind.LANDING
	_ring_material.albedo_color = color.lightened(0.3)
	_particles.color = color
	_particles.emitting = false
	_particles.restart()
	_particles.emitting = true
	_burst_material.albedo_color = color
	_burst_material.emission = color


## Advances presentation lifetime and returns true on completion.
func tick(delta: float) -> bool:
	_remaining = maxf(0.0, _remaining - maxf(delta, 0.0))
	var elapsed: float = _duration - _remaining
	var progress: float = clampf(elapsed / maxf(_duration, 0.001), 0.0, 1.0)
	_burst.scale = Vector3.ONE * (1.0 + elapsed * IMPACT_GROWTH_RATE)
	_burst_material.albedo_color = Color(_burst_color.lerp(Color(0.25, 0.08, 0.04), progress), _burst_color.a * (1.0 - progress))
	_burst_material.emission_energy_multiplier = 3.0 * (1.0 - progress)
	var ring_scale: float = lerpf(RING_START_SCALE, RING_END_SCALE, 1.0 - pow(1.0 - progress, 3.0))
	_ring.scale = Vector3(ring_scale, 1.0, ring_scale)
	_ring_material.albedo_color.a = 1.0 - progress
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


static func _make_ring_material() -> StandardMaterial3D:
	var gradient: Gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.62, 0.8, 1.0])
	gradient.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.15), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 64
	texture.height = 64
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_texture = texture
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material
