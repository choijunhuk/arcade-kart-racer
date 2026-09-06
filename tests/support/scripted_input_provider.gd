class_name ScriptedInputProvider
extends InputProvider

## Test double that drives full throttle and steers toward a point on a
## `RacingLine` a fixed distance ahead, using `Curve3D.get_closest_offset()`
## and `Curve3D.sample_baked()`. Used by kart integration tests so they do
## not depend on `PlayerInputProvider`/the `Input` singleton.

const LOOKAHEAD_DISTANCE: float = 8.0
const STEER_GAIN: float = 3.0
const MIN_CORNER_THROTTLE: float = 0.35

var throttle: float = 1.0
var _kart: Node3D
var _racing_line: Path3D


func _init(kart: Node3D, racing_line: Path3D) -> void:
	_kart = kart
	_racing_line = racing_line


func get_frame() -> InputFrame:
	var frame: InputFrame = InputFrame.new()
	var steer: float = _compute_steer_toward_line()
	frame.steer = steer
	# Ease off the throttle in proportion to the steering command so the
	# scripted driver slows for corners instead of running wide into walls,
	# the way any real driver (human or AI) would.
	frame.throttle = throttle * lerpf(1.0, MIN_CORNER_THROTTLE, clampf(absf(steer), 0.0, 1.0))
	return frame


func _compute_steer_toward_line() -> float:
	if _racing_line == null or _racing_line.curve == null:
		return 0.0
	var curve: Curve3D = _racing_line.curve
	var local_position: Vector3 = _racing_line.to_local(_kart.global_position)
	var offset: float = curve.get_closest_offset(local_position)
	var target_offset: float = fposmod(offset + LOOKAHEAD_DISTANCE, curve.get_baked_length())
	var target_local: Vector3 = curve.sample_baked(target_offset)
	var target_global: Vector3 = _racing_line.to_global(target_local)

	var to_target: Vector3 = target_global - _kart.global_position
	to_target.y = 0.0
	if to_target.length() < 0.001:
		return 0.0
	to_target = to_target.normalized()

	var forward: Vector3 = -_kart.global_transform.basis.z
	forward.y = 0.0
	if forward.length() < 0.001:
		return 0.0
	forward = forward.normalized()

	var angle: float = atan2(forward.cross(to_target).y, forward.dot(to_target))
	return clampf(angle * STEER_GAIN, -1.0, 1.0)
