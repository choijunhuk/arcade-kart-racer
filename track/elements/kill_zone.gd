class_name KillZone
extends Area3D

## Track element: re-emits layer-2 body entry as a generic node signal.
## Track must not reference Kart (spec §6.5); RespawnSystem does the cast.

signal body_fell(body: Node3D)


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	body_fell.emit(body)
