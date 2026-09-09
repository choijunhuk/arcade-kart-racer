class_name BoostPad
extends Area3D

@export var tuning: PhysicsTuning = preload("res://data/tuning/physics_default.tres")


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if body is KartController:
		(body as KartController).request_boost(tuning.boost_pad_boost, &"boost_pad")
		EventBus.item_defense_triggered.emit(body)
