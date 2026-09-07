class_name ScriptedInputProvider
extends InputProvider

## Test double that drives full throttle and steers toward a point on a
## `RacingLine` a fixed distance ahead, using `Curve3D.get_closest_offset()`
## and `Curve3D.sample_baked()`. Used by kart integration tests so they do
## not depend on `PlayerInputProvider`/the `Input` singleton.

const LOOKAHEAD_DISTANCE: float = 8.0
const STEER_GAIN: float = 3.0
const MIN_CORNER_THROTTLE: float = 0.15
const CURVATURE_SAMPLE_DISTANCE: float = 8.0
## A true circular turn of radius R has curvature ~= 1/R, so this must stay
## at or below 1 / HAIRPIN_RADIUS (spec §24 Phase 3: ~18 m hairpins, curvature
## ~0.056) for the drift-on-corners mode to detect them as worth drifting.
const DRIFT_CURVATURE_ENTER_THRESHOLD: float = 0.045
## Hysteresis below `DRIFT_CURVATURE_ENTER_THRESHOLD` so a brief mid-corner
## dip in the sampled curvature (spline easing near a turn's tangent points)
## does not release the drift before the kart has actually exited the turn.
const DRIFT_CURVATURE_EXIT_THRESHOLD: float = 0.001
## Mirrors `PhysicsTuning.drift_min_steer`: `DriftController` silently
## refuses to start a hop below this, and the press edge only fires once, so
## the scripted driver must not request drift before its own steering has
## actually turned into the corner far enough to be accepted.
const MIN_STEER_TO_START_DRIFT: float = 0.35
## Representative cornering grip (m/s^2) used only to pick a safe scripted
## cornering speed from upcoming curvature (`safe_speed = sqrt(grip * radius)`,
## radius = 1/curvature) so the driver brakes for a tight turn the way any
## real driver would, instead of sliding through it at full cruising speed.
## Deliberately below `PhysicsTuning.grip` as a safety margin; not itself a
## gameplay value.
const CORNERING_GRIP_ESTIMATE: float = 5.0
const CORNER_BRAKE: float = 0.6

var throttle: float = 1.0
var _kart: Node3D
var _racing_line: Path3D
var _drift_on_corners: bool = false
var _was_drifting: bool = false
var _locked_direction: float = 1.0


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
	var signed_curvature: float = _upcoming_curvature()
	var curvature: float = absf(signed_curvature)
	var drift_state: int = _get_drift_state()
	if _drift_on_corners:
		if drift_state == DriftController.DriftState.HOP:
			# A pursuit-style line-follower only ever needs gentle correction
			# steer, which never reaches `drift_min_steer` on its own. A real
			# driver deliberately flicks the wheel harder than the racing
			# line strictly requires to kick off and hold a drift, so keep
			# boosting the steer magnitude on the locked direction through
			# the whole hop — dropping back to the gentle line-following
			# value even one tick early fails `DriftController`'s per-tick
			# minimum-steer hop check.
			steer = _locked_direction * maxf(absf(steer), MIN_STEER_TO_START_DRIFT)
			frame.steer = steer
			frame.drift = true
		elif drift_state == DriftController.DriftState.HOLD:
			# Clamp (never boost) natural pursuit-steer to the locked
			# direction's side: any opposite-direction excursion becomes
			# neutral instead of trips the opposite-steer cancel, but the
			# magnitude otherwise still tracks what the line actually needs
			# (an artificial floor overturns once the exit starts straightening).
			steer = maxf(steer * _locked_direction, 0.0) * _locked_direction
			frame.steer = steer
			frame.drift = curvature >= DRIFT_CURVATURE_EXIT_THRESHOLD
		else:
			if curvature >= DRIFT_CURVATURE_ENTER_THRESHOLD:
				_locked_direction = signf(steer) if absf(steer) > 0.001 else signf(signed_curvature)
				steer = _locked_direction * maxf(absf(steer), MIN_STEER_TO_START_DRIFT)
				frame.steer = steer
			frame.drift = curvature >= DRIFT_CURVATURE_ENTER_THRESHOLD and absf(steer) >= MIN_STEER_TO_START_DRIFT
		frame.drift_pressed = frame.drift and not _was_drifting
		_was_drifting = frame.drift
	# Once actually holding a drift, `DriftController`'s own speed retention
	# manages cornering speed; braking on top of that starves charge time and
	# cancels the drift outright (low-speed cancel). Keep braking through the
	# NONE/HOP approach (not just while `frame.drift` is false) so the kart
	# enters the hold at a controllable speed instead of carrying full
	# cruising speed into the turn during the brief hop transition.
	if drift_state != DriftController.DriftState.HOLD:
		_apply_corner_braking(frame, curvature)
	return frame


func _get_drift_state() -> int:
	if not _kart.has_method("get_drift_state"):
		return DriftController.DriftState.NONE
	return int(_kart.call("get_drift_state"))


## Overrides throttle with a brake when the upcoming turn is tighter than the
## kart can safely hold at its current speed, independent of drift mode: a
## real driver slows for a sharp corner whether or not they intend to drift
## through it.
func _apply_corner_braking(frame: InputFrame, curvature: float) -> void:
	if curvature <= 0.001 or not _kart.has_method("get_speed"):
		return
	var radius: float = 1.0 / curvature
	var safe_speed: float = sqrt(CORNERING_GRIP_ESTIMATE * radius)
	if _kart.call("get_speed") > safe_speed:
		frame.throttle = 0.0
		frame.brake = CORNER_BRAKE


## Enables optional curvature-gated drift input while preserving legacy default behavior.
func set_drift_on_corners(enabled: bool) -> void:
	_drift_on_corners = enabled
	_was_drifting = false


func _upcoming_curvature() -> float:
	if _racing_line == null or _racing_line.curve == null:
		return 0.0
	var curve: Curve3D = _racing_line.curve
	var length: float = curve.get_baked_length()
	if length <= 0.0:
		return 0.0
	var local_position: Vector3 = _racing_line.to_local(_kart.global_position)
	var offset: float = curve.get_closest_offset(local_position)
	var first: Vector3 = curve.sample_baked(fposmod(offset + CURVATURE_SAMPLE_DISTANCE, length))
	var second: Vector3 = curve.sample_baked(fposmod(offset + CURVATURE_SAMPLE_DISTANCE * 2.0, length))
	var third: Vector3 = curve.sample_baked(fposmod(offset + CURVATURE_SAMPLE_DISTANCE * 3.0, length))
	var incoming: Vector3 = (second - first).normalized()
	var outgoing: Vector3 = (third - second).normalized()
	if incoming.length() < 0.001 or outgoing.length() < 0.001:
		return 0.0
	return incoming.signed_angle_to(outgoing, Vector3.UP) / CURVATURE_SAMPLE_DISTANCE


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
