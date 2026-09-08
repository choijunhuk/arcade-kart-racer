class_name ImpactEffect
extends Node3D

## Short pooled placeholder burst advanced by ItemManager gameplay ticks.

const DURATION_SECONDS: float = 0.25

var _remaining: float = 0.0


## Restarts the burst at a world-space hit point.
func play(world_position: Vector3) -> void:
	global_position = world_position
	_remaining = DURATION_SECONDS
	visible = true
	scale = Vector3.ONE


## Advances presentation lifetime and returns true on completion.
func tick(dt: float) -> bool:
	_remaining = maxf(0.0, _remaining - maxf(dt, 0.0))
	scale = Vector3.ONE * (1.0 + (DURATION_SECONDS - _remaining) * 3.0)
	return _remaining <= 0.0
