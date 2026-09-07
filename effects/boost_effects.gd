class_name BoostEffects
extends Node3D

@onready var _kart: KartController = get_parent() as KartController
@onready var _exhaust: Array[GPUParticles3D] = [$ExhaustLeft, $ExhaustRight]


func _ready() -> void:
	var controller: BoostController = _kart.get_node("BoostController") as BoostController
	controller.boost_started.connect(_on_boost_started)
	controller.boost_ended.connect(_on_boost_ended)


func _on_boost_started(_spec: BoostSpecData) -> void:
	for particles: GPUParticles3D in _exhaust:
		particles.emitting = true


func _on_boost_ended() -> void:
	for particles: GPUParticles3D in _exhaust:
		particles.emitting = false
