class_name NetPrediction
extends RefCounted

## Client-owned raw input history and visual-only correction, never server authority.
var frames: Array[InputFrame] = []
var visual_offset: Vector3 = Vector3.ZERO
var _remaining: float = 0.0
var _last_ack: int = -1

## Keeps bounded independent frames after their actual prediction tick.
func record(frame: InputFrame) -> void:
	frames.append(frame.clone())
	if frames.size() > NetTuning.HISTORY_TICKS:
		frames.pop_front()

## Rewinds full physics state and replays every unacknowledged local input.
func reconcile(kart: KartController, state: Dictionary, acknowledged: int) -> void:
	if acknowledged < _last_ack:
		return
	_last_ack = acknowledged
	var before: Vector3 = kart.global_position + visual_offset
	kart.apply_state(state)
	while not frames.is_empty() and frames[0].tick <= acknowledged:
		frames.pop_front()
	for frame: InputFrame in frames:
		kart.step_input(frame, NetTuning.STEP, true)
	var correction: Vector3 = before - kart.global_position
	visual_offset = correction if correction.length() <= NetTuning.SNAP_METERS else Vector3.ZERO
	_remaining = NetTuning.CORRECTION_SECONDS

## Removes correction linearly in 100 ms without touching the collision body.
func advance_visual(delta: float) -> Vector3:
	var next: float = maxf(0.0, _remaining - delta)
	visual_offset *= next / _remaining if _remaining > 0.0 else 0.0
	_remaining = next
	return visual_offset
