class_name JumpPad
extends Area3D

@export var launch_velocity: Vector3 = Vector3(0.0, 9.0, -18.0)


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if body is KartController:
		(body as KartController).launch(launch_velocity)
