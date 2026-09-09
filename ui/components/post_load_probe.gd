class_name PostLoadProbe
extends Node

## Observes real frame intervals after scene replacement; never substitutes GPU QA.
const SAMPLE_FRAMES: int = 120
const FRAME_BUDGET_MS: float = 100.0
const USEC_PER_MS: float = 1000.0
var _last_usec: int = 0
var _frames: int = 0
var _worst_ms: float = 0.0

func _ready() -> void:
	_last_usec = Time.get_ticks_usec()

func _process(_delta: float) -> void:
	var now: int = Time.get_ticks_usec()
	_worst_ms = maxf(_worst_ms, float(now - _last_usec) / USEC_PER_MS)
	_last_usec = now
	_frames += 1
	if _frames >= SAMPLE_FRAMES:
		print("POST_LOAD ", JSON.stringify({"worst_frame_ms": _worst_ms, "budget_ms": FRAME_BUDGET_MS, "pass": _worst_ms <= FRAME_BUDGET_MS, "headless": DisplayServer.get_name() == "headless"}))
		queue_free()
