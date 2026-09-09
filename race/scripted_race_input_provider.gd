class_name ScriptedRaceInputProvider
extends InputProvider

## Temporary deterministic racing-line follower for Phase 5 race flow/sims.
## Phase 5 deterministic follower retained for post-finish player cruise/tests;
## active AI racers use AIController/AINavigator/AIDriver composition.

const LOOKAHEAD_DISTANCE: float = 8.0
const STEER_GAIN: float = 3.0
const MIN_CORNER_THROTTLE: float = 0.15
const CURVATURE_SAMPLE_DISTANCE: float = 8.0
const DRIFT_CURVATURE_ENTER_THRESHOLD: float = 0.045
const DRIFT_CURVATURE_EXIT_THRESHOLD: float = 0.001
const MIN_STEER_TO_START_DRIFT: float = 0.35
const CORNERING_GRIP_ESTIMATE: float = 5.0
const CORNER_BRAKE: float = 0.6
const SPEED_LIMIT_BRAKE: float = 0.35

var _kart: KartController
var _racing_line: RacingLine
var _target_speed_ratio: float = 0.8
var _drift_on_corners: bool = true
var _was_drifting: bool = false
var _locked_direction: float = 1.0
## Previous tick's resolved offset, used only to pick which wrap of a fresh
## full-scan `RacingLine.offset_at()` result is continuous with where this
## follower actually was (spec item B). The scan itself stays unhinted/full
## every tick — hinting the search window instead would leave it unable to
## reacquire the kart after a large discontinuous jump (a stuck-recovery
## respawn teleport), searching only near the stale pre-teleport location.
## The seam itself is a genuine tie (the closing baked point duplicates the
## first one), so an unhinted scan can report either side; without this,
## picking the "wrong" side snaps the offset back near 0 a little early,
## making `sample(offset + LOOKAHEAD_DISTANCE)` land behind the kart and
## drive spurious corner braking/oscillation right before the finish line.
var _cached_offset: float = -1.0


func _init(kart: KartController, racing_line: RacingLine, target_speed_ratio: float = 0.8) -> void:
	_kart = kart
	_racing_line = racing_line
	_target_speed_ratio = clampf(target_speed_ratio, 0.1, 1.0)


## Produces deterministic pursuit steering with conservative corner braking.
func get_frame() -> InputFrame:
	var frame: InputFrame = InputFrame.new()
	var offset: float = _current_offset()
	var steer: float = _compute_steer_toward_line(offset)
	frame.steer = steer
	frame.throttle = _target_speed_ratio * lerpf(
		1.0, MIN_CORNER_THROTTLE, clampf(absf(steer), 0.0, 1.0),
	)
	var signed_curvature: float = _upcoming_curvature(offset)
	var curvature: float = absf(signed_curvature)
	var drift_state: int = _kart.get_drift_state()
	if _drift_on_corners:
		_apply_drift_input(frame, steer, signed_curvature, curvature, drift_state)
	if drift_state != DriftController.DriftState.HOLD:
		_apply_corner_braking(frame, curvature)
	if _kart.get_speed_ratio() > _target_speed_ratio:
		frame.throttle = 0.0
		frame.brake = maxf(frame.brake, SPEED_LIMIT_BRAKE)
	return frame


## Enables fixed curvature-gated drifting without tactical AI decisions.
func set_drift_on_corners(enabled: bool) -> void:
	_drift_on_corners = enabled
	_was_drifting = false


## Changes the simple speed cap used for normal versus finished driving.
func set_target_speed_ratio(ratio: float) -> void:
	_target_speed_ratio = clampf(ratio, 0.1, 1.0)


func _apply_drift_input(
	frame: InputFrame, steer: float, signed_curvature: float,
	curvature: float, drift_state: int,
) -> void:
	if drift_state == DriftController.DriftState.HOP:
		frame.steer = _locked_direction * maxf(absf(steer), MIN_STEER_TO_START_DRIFT)
		frame.drift = true
	elif drift_state == DriftController.DriftState.HOLD:
		frame.steer = maxf(steer * _locked_direction, 0.0) * _locked_direction
		frame.drift = curvature >= DRIFT_CURVATURE_EXIT_THRESHOLD
	else:
		if curvature >= DRIFT_CURVATURE_ENTER_THRESHOLD:
			_locked_direction = signf(steer) if absf(steer) > 0.001 else signf(signed_curvature)
			frame.steer = _locked_direction * maxf(absf(steer), MIN_STEER_TO_START_DRIFT)
		frame.drift = curvature >= DRIFT_CURVATURE_ENTER_THRESHOLD and absf(frame.steer) >= MIN_STEER_TO_START_DRIFT
	frame.drift_pressed = frame.drift and not _was_drifting
	_was_drifting = frame.drift


func _apply_corner_braking(frame: InputFrame, curvature: float) -> void:
	if curvature <= 0.001:
		return
	var safe_speed: float = sqrt(CORNERING_GRIP_ESTIMATE / curvature)
	if _kart.get_speed() > safe_speed:
		frame.throttle = 0.0
		frame.brake = CORNER_BRAKE


## Resolves this tick's racing-line offset via an unhinted full scan (always
## finds the true global nearest point, so a large discontinuous jump like a
## respawn teleport is reacquired immediately), then keeps whichever wrap of
## that raw result is closest to the previous tick's offset — the only fix
## needed for the ambiguous tie exactly at the start/finish seam (spec item B).
func _current_offset() -> float:
	if _racing_line == null:
		return 0.0
	var raw: float = _racing_line.offset_at(_kart.global_position)
	if _cached_offset < 0.0:
		_cached_offset = raw
		return raw
	var length: float = _racing_line.length()
	var best: float = raw
	var best_delta: float = absf(raw - _cached_offset)
	for candidate: float in [raw + length, raw - length]:
		var delta: float = absf(candidate - _cached_offset)
		if delta < best_delta:
			best_delta = delta
			best = candidate
	_cached_offset = fposmod(best, maxf(length, 0.001))
	return _cached_offset


func _upcoming_curvature(offset: float) -> float:
	if _racing_line == null:
		return 0.0
	var first: Vector3 = _racing_line.sample(offset + CURVATURE_SAMPLE_DISTANCE)
	var second: Vector3 = _racing_line.sample(offset + CURVATURE_SAMPLE_DISTANCE * 2.0)
	var third: Vector3 = _racing_line.sample(offset + CURVATURE_SAMPLE_DISTANCE * 3.0)
	var incoming: Vector3 = (second - first).normalized()
	var outgoing: Vector3 = (third - second).normalized()
	if incoming.length() < 0.001 or outgoing.length() < 0.001:
		return 0.0
	return incoming.signed_angle_to(outgoing, Vector3.UP) / CURVATURE_SAMPLE_DISTANCE


func _compute_steer_toward_line(offset: float) -> float:
	if _racing_line == null:
		return 0.0
	var target_global: Vector3 = _racing_line.sample(offset + LOOKAHEAD_DISTANCE)
	var to_target: Vector3 = target_global - _kart.global_position
	to_target.y = 0.0
	if to_target.length() < 0.001:
		return 0.0
	var forward: Vector3 = _kart.get_forward()
	forward.y = 0.0
	if forward.length() < 0.001:
		return 0.0
	forward = forward.normalized()
	to_target = to_target.normalized()
	var angle: float = atan2(forward.cross(to_target).y, forward.dot(to_target))
	return clampf(angle * STEER_GAIN, -1.0, 1.0)
