class_name BoostEffects
extends Node3D

## Heat-shimmer fade speed in intensity units per second, applied on both the
## rise (boost start) and fall (boost end) edges.
const SHIMMER_FADE_SPEED: float = 4.0

@onready var _kart: KartController = get_parent() as KartController
@onready var _exhaust: GPUParticles3D = $Exhaust
@onready var _flame_core: MeshInstance3D = $FlameCore
@onready var _heat_shimmer: MeshInstance3D = $HeatShimmer
@onready var _shimmer_material: ShaderMaterial = _heat_shimmer.mesh.material as ShaderMaterial

var _boost_active: bool = false
var _lod_enabled: bool = true
var _shimmer_intensity: float = 0.0


func _ready() -> void:
	_exhaust.material_override = ParticleArt.material(true)
	var controller: BoostController = _kart.get_node("BoostController") as BoostController
	controller.boost_started.connect(_on_boost_started)
	controller.boost_ended.connect(_on_boost_ended)


func _process(delta: float) -> void:
	_exhaust.emitting = _boost_active and _lod_enabled
	_flame_core.visible = _boost_active and _lod_enabled
	var target: float = 1.0 if (_boost_active and _lod_enabled) else 0.0
	_shimmer_intensity = move_toward(_shimmer_intensity, target, SHIMMER_FADE_SPEED * delta)
	_heat_shimmer.visible = _shimmer_intensity > 0.0
	_shimmer_material.set_shader_parameter("intensity", _shimmer_intensity)


func _on_boost_started(_spec: BoostSpecData) -> void:
	_boost_active = true
	_exhaust.emitting = _lod_enabled


func _on_boost_ended() -> void:
	_boost_active = false
	_exhaust.emitting = false


## Enables or disables exhaust for camera-distance LOD without losing boost state.
func set_lod_enabled(enabled: bool) -> void:
	_lod_enabled = enabled
	_exhaust.emitting = _boost_active and _lod_enabled


## Applies the user-selected visual density without restarting the exhaust.
func set_quality_ratio(ratio: float) -> void:
	_exhaust.amount_ratio = clampf(ratio, 0.0, 1.0)
