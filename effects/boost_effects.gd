class_name BoostEffects
extends Node3D

@onready var _kart: KartController = get_parent() as KartController
@onready var _exhaust: GPUParticles3D = $Exhaust

var _boost_active: bool = false
var _lod_enabled: bool = true


func _ready() -> void:
	var controller: BoostController = _kart.get_node("BoostController") as BoostController
	controller.boost_started.connect(_on_boost_started)
	controller.boost_ended.connect(_on_boost_ended)


func _process(_delta: float) -> void:
	_exhaust.emitting = _boost_active and _lod_enabled


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
