class_name ItemRoulette
extends RefCounted

## Tick-driven reveal timer whose result is fixed at pickup time.

const DURATION_SECONDS: float = 1.2

var _result: ItemData
var _remaining: float = 0.0
var _active: bool = false


## Starts a reveal for an already-selected result.
func start(result: ItemData) -> void:
	_result = result
	_remaining = DURATION_SECONDS
	_active = result != null


## Advances the timer and returns true only on the finishing tick.
func tick(dt: float) -> bool:
	if not _active:
		return false
	_remaining = maxf(0.0, _remaining - maxf(dt, 0.0))
	if _remaining > 0.0:
		return false
	_active = false
	return true


## Returns whether the reveal animation is still active.
func is_active() -> bool:
	return _active


## Returns the result fixed when `start` was called.
func get_result() -> ItemData:
	return _result


## Returns reveal progress from zero to one for temporary HUD animation.
func get_progress() -> float:
	if not _active:
		return 1.0 if _result != null else 0.0
	return clampf(1.0 - _remaining / DURATION_SECONDS, 0.0, 1.0)
