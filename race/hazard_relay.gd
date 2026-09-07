class_name HazardRelay
extends Node

## Bridges generic `Hazard` Area3D signals to `KartController.apply_hit()`,
## the same role `RespawnSystem` plays for `KillZone` (spec §6.5).


func register_hazard(hazard: Hazard) -> void:
	if not hazard.body_hazard_hit.is_connected(_on_body_hazard_hit):
		hazard.body_hazard_hit.connect(_on_body_hazard_hit)


func _on_body_hazard_hit(body: Node3D, hit_type: int) -> void:
	var kart: KartController = body as KartController
	if kart != null:
		kart.apply_hit(hit_type as HitReactor.HitType, null)
