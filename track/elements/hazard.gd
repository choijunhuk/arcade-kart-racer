class_name Hazard
extends Area3D

## Track element: contact damage/effect zone. Emits a generic body signal;
## `HazardRelay` (race/) is the one that knows about KartController/HitReactor
## (spec §6.5: Track must not reference Kart).

signal body_hazard_hit(body: Node3D, hit_type: int)

@export var hit_type: int = HitReactor.HitType.SPIN_OUT


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	body_hazard_hit.emit(body, hit_type)
