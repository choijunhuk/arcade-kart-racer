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
func reconcile(kart: KartController, state: Dictionary, acknowledged: int, predicted_positions: Dictionary = {}) -> void:
	if acknowledged < _last_ack:
		return
	_last_ack = acknowledged
	var before: Vector3 = kart.global_position + visual_offset
	kart.apply_state(state)
	if requires_server_pose(int(state["components"]["."]["state"])):
		frames.clear()
		visual_offset = Vector3.ZERO
		_remaining = 0.0
		return
	while not frames.is_empty() and frames[0].tick <= acknowledged:
		frames.pop_front()
	for frame: InputFrame in frames:
		kart.step_input(frame, NetTuning.STEP, true)
		# Future acknowledgements must compare against this replayed trajectory.
		predicted_positions[frame.tick] = kart.global_position
	var correction: Vector3 = before - kart.global_position
	visual_offset = correction if correction.length() <= NetTuning.SNAP_METERS else Vector3.ZERO
	_remaining = NetTuning.CORRECTION_SECONDS

## Removes correction linearly in 100 ms without touching the collision body.
func advance_visual(delta: float) -> Vector3:
	var next: float = maxf(0.0, _remaining - delta)
	visual_offset *= next / _remaining if _remaining > 0.0 else 0.0
	_remaining = next
	return visual_offset

## Server-owned teleports, freezes and post-finish driving are not locally replayed.
static func requires_server_pose(kart_state: int) -> bool:
	return kart_state in [KartState.RESPAWNING, KartState.FROZEN, KartState.FINISHED]
