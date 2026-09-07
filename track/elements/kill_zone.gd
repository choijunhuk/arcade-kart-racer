class_name KillZone
extends Area3D

## Converts layer-2 body entry into a typed kart signal for RespawnSystem.

signal kart_entered(kart: KartController)


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if body is KartController:
		kart_entered.emit(body as KartController)
