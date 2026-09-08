class_name AIDriver
extends RefCounted

## Steering/throttle/brake/drift/trick/stuck decisions (spec §13.4). Owns one
## kart's mutable timers/RNG-derived state across ticks; drift entry/hold is
## delegated to `AIDriftPlanner` to keep this file under the spec §29
## 400-line budget.

const SPEED_MARGIN: float = 1.0
const BRAKE_AMOUNT: float = 1.0
const LATE_BRAKE_DELAY_SECONDS: float = 0.3
## Deliberately short: the forward-center cast sees an ordinary curving wall
## within range constantly while cornering (a straight ray vs. a curved
## corridor), so this must stay a genuine near-collision check, not routine
## corner geometry, or it would override the corner-speed governor forever.
const HEAD_ON_BRAKE_DISTANCE: float = 3.0
const AVOID_STRENGTH: float = 1.0
const OVERTAKE_SPEED_DELTA: float = 1.5
## Above this |curvature| the AI is mid-corner; it neither starts nor holds
## an overtake attempt there (spec §13.4: "코너 정점 근처에서는 추월 시도 안 함").
const CORNER_APEX_CURVATURE: float = 0.03
const REVERSE_TRIGGER_SECONDS: float = 2.0
const RESPAWN_TRIGGER_SECONDS: float = 5.0
const REVERSE_DURATION_SECONDS: float = 1.0
const STUCK_SPEED_THRESHOLD: float = 1.0
const STUCK_SPEED_SMOOTHING_RATE: float = 1.0
const FINISHED_SPEED_RATIO: float = 0.5
const MAX_RUBBER_BAND: float = 0.05
const TRICK_MIN_AIR_TIME: float = 0.35
## Rate-limits the PD derivative term (radians/tick). Without this, a target
## point close to the kart (short look-ahead at low corner speed) can swing
## its angle wildly tick to tick, and `kd` amplifies that "derivative kick"
## into steer flipping hard-left/hard-right every tick instead of settling.
const MAX_STEER_ERROR_DELTA: float = 0.4

enum StuckAction { NONE, REVERSE, RESPAWN }

var _rng: RandomNumberGenerator
var _drift_planner: AIDriftPlanner
var _prev_steer_error: float = 0.0
var _stuck_elapsed: float = 0.0
var _speed_ema: float = 999.0
var _reverse_remaining: float = 0.0
var _was_overspeed: bool = false
var _late_brake_delay_remaining: float = 0.0
var _trick_rolled_this_flight: bool = false
var _rubber_band_mult: float = 1.0
var _last_target_speed: float = 0.0
var _start_pressed: bool = false
var _planned_start_phase: float = -1.0


func _init(rng: RandomNumberGenerator) -> void:
	_rng = rng
	_drift_planner = AIDriftPlanner.new(rng)


## Returns the current rubber-band multiplier for the debug overlay (spec §13.7).
func get_rubber_band_mult() -> float:
	return _rubber_band_mult


## Returns the most recently computed target speed for debug overlays.
func get_last_target_speed() -> float:
	return _last_target_speed


## Pure PD steering law with clamp and one injected noise sample (spec §13.4).
static func compute_steer(error: float, prev_error: float, dt: float, kp: float, kd: float, noise_amplitude: float, noise_sample: float) -> float:
	var delta: float = clampf(error - prev_error, -MAX_STEER_ERROR_DELTA, MAX_STEER_ERROR_DELTA)
	var derivative: float = delta / maxf(dt, 0.0001)
	return clampf(kp * error + kd * derivative + noise_amplitude * noise_sample, -1.0, 1.0)


## Pure corner-speed formula: sqrt(lateral accel / curvature), scaled by confidence.
static func compute_corner_speed(max_lateral_accel: float, curvature: float, max_speed: float, speed_confidence: float) -> float:
	if curvature <= 0.0001:
		return max_speed * speed_confidence
	var corner_speed: float = sqrt(max_lateral_accel / curvature)
	return minf(max_speed, corner_speed) * speed_confidence


## Pure catch-up multiplier clamped to +-max_band (spec §13.7).
static func compute_rubber_band_mult(gap: float, strength: float, max_band: float) -> float:
	return clampf(1.0 + strength * gap, 1.0 - max_band, 1.0 + max_band)


## Returns 1 (right), -1 (left), or 0 (no clear lane) to overtake through.
static func choose_overtake_side(left_clear: bool, right_clear: bool) -> int:
	if right_clear:
		return 1
	if left_clear:
		return -1
	return 0


## Pure avoidance bias: positive nudges right, negative nudges left (spec §13.4).
static func compute_avoid_bias(report: AISensors.SensorReport, avoid_strength: float) -> float:
	var bias: float = 0.0
	if report.obstacle_hit.get(AISensors.Side.LEFT, false):
		bias += avoid_strength
	if report.obstacle_hit.get(AISensors.Side.RIGHT, false):
		bias -= avoid_strength
	return bias


## Pure overtake bias toward whichever forward lane is clear (spec §13.4).
static func compute_overtake_bias(report: AISensors.SensorReport, profile: AIDifficultyProfile, curvature_ahead: float) -> float:
	if report.kart_ahead_distance > profile.overtake_range or report.kart_ahead_relative_speed < OVERTAKE_SPEED_DELTA:
		return 0.0
	if absf(curvature_ahead) > CORNER_APEX_CURVATURE:
		return 0.0
	var left_clear: bool = report.side_clear(AISensors.Side.LEFT) and report.kart_ahead_side != AISensors.Side.LEFT
	var right_clear: bool = report.side_clear(AISensors.Side.RIGHT) and report.kart_ahead_side != AISensors.Side.RIGHT
	return float(choose_overtake_side(left_clear, right_clear)) * profile.lane_offset_max


## Pure stuck-timer state machine (spec §13.4): reverse after 2s, respawn after 5s.
static func evaluate_stuck(stuck_elapsed: float) -> StuckAction:
	if stuck_elapsed >= RESPAWN_TRIGGER_SECONDS:
		return StuckAction.RESPAWN
	if stuck_elapsed >= REVERSE_TRIGGER_SECONDS:
		return StuckAction.REVERSE
	return StuckAction.NONE


## Builds one InputFrame from sensor/navigation state (spec §13.4).
func compute_frame(
	kart: KartController, profile: AIDifficultyProfile, nav: AINavigator.NavResult,
	sensors: AISensors.SensorReport, context: AIRaceContext, dt: float,
) -> InputFrame:
	var frame: InputFrame = InputFrame.zero()
	match kart.get_state():
		KartState.RESPAWNING:
			_stuck_elapsed = 0.0
			_reverse_remaining = 0.0
			_speed_ema = 999.0
			return frame
		KartState.FROZEN:
			return _compute_start_frame(context)
		KartState.FINISHED:
			return _compute_finished_frame(kart, nav)
		_:
			pass
	_update_stuck(kart, context, dt)
	if _reverse_remaining > 0.0:
		frame.steer = -clampf(_angle_to_target(kart, nav.target_point), -1.0, 1.0)
		frame.brake = 1.0
		return frame
	var steer_error: float = _angle_to_target(kart, nav.target_point)
	frame.steer = compute_steer(steer_error, _prev_steer_error, dt, profile.steer_kp, profile.steer_kd, profile.steer_noise, _rng.randfn(0.0, 1.0))
	_prev_steer_error = steer_error
	var target_speed: float = _compute_target_speed(kart, profile, nav, context)
	if kart.get_drift_state() == DriftController.DriftState.HOLD:
		# Mid-drift, `DriftController`'s own grip/speed-retention rules (spec
		# §10.2) already keep cornering safe; braking on top of that starves
		# mini-turbo charge and fights the very reason to drift a corner.
		frame.throttle = 1.0
	else:
		_drive_throttle_brake(frame, kart, target_speed, dt, profile)
	_drift_planner.update(frame, kart, profile, nav, dt)
	_apply_head_on_brake(frame, kart, sensors)
	_apply_trick(frame, kart, profile)
	return frame


func _angle_to_target(kart: KartController, target_point: Vector3) -> float:
	var to_target: Vector3 = target_point - kart.global_position
	to_target.y = 0.0
	var forward: Vector3 = kart.get_forward()
	forward.y = 0.0
	if to_target.length() < 0.001 or forward.length() < 0.001:
		return 0.0
	return atan2(forward.normalized().cross(to_target.normalized()).y, forward.normalized().dot(to_target.normalized()))


func _compute_target_speed(kart: KartController, profile: AIDifficultyProfile, nav: AINavigator.NavResult, context: AIRaceContext) -> float:
	var max_speed: float = kart.get_kart_data().max_speed
	var corner_speed: float = compute_corner_speed(profile.max_lateral_accel, nav.curvature_ahead, max_speed, profile.speed_confidence)
	var gap: float = _rubber_band_gap(kart, context)
	_rubber_band_mult = compute_rubber_band_mult(gap, profile.rubber_band_strength, MAX_RUBBER_BAND)
	_last_target_speed = corner_speed * _rubber_band_mult
	return _last_target_speed


func _rubber_band_gap(kart: KartController, context: AIRaceContext) -> float:
	if context == null or context.player_kart == null or context.position_tracker == null or context.racing_line == null:
		return 0.0
	var lap_length: float = context.racing_line.length()
	if lap_length <= 0.0:
		return 0.0
	var player_progress: float = context.position_tracker.get_progress(context.player_kart)
	var ai_progress: float = context.position_tracker.get_progress(kart)
	return clampf((player_progress - ai_progress) / lap_length, -1.0, 1.0)


func _drive_throttle_brake(frame: InputFrame, kart: KartController, target_speed: float, dt: float, profile: AIDifficultyProfile) -> void:
	var overspeed: bool = kart.get_speed() > target_speed + SPEED_MARGIN
	if overspeed and not _was_overspeed:
		_late_brake_delay_remaining = LATE_BRAKE_DELAY_SECONDS if _rng.randf() < profile.late_brake_prob else 0.0
	_was_overspeed = overspeed
	if not overspeed:
		frame.throttle = 1.0
		return
	if _late_brake_delay_remaining > 0.0:
		_late_brake_delay_remaining -= dt
		frame.throttle = 1.0
		return
	frame.throttle = 0.0
	frame.brake = BRAKE_AMOUNT


## Only overrides throttle/brake for a genuine near-collision, and only while
## still carrying real speed — once slow, the stuck/reverse handling above
## takes over instead of this pinning the kart into reverse forever.
func _apply_head_on_brake(frame: InputFrame, kart: KartController, sensors: AISensors.SensorReport) -> void:
	if kart.get_speed() > STUCK_SPEED_THRESHOLD and sensors.obstacle_distance.get(AISensors.Side.CENTER, INF) <= HEAD_ON_BRAKE_DISTANCE:
		frame.throttle = 0.0
		frame.brake = 1.0


func _apply_trick(frame: InputFrame, kart: KartController, profile: AIDifficultyProfile) -> void:
	if kart.is_grounded():
		_trick_rolled_this_flight = false
		return
	if _trick_rolled_this_flight or kart.get_air_time() < TRICK_MIN_AIR_TIME:
		return
	_trick_rolled_this_flight = true
	if _rng.randf() < profile.trick_prob:
		frame.drift_pressed = true


## Uses a smoothed speed (not the instantaneous value) so a kart wedged
## against a wall and bouncing between ~0 and ~2 m/s every tick still reads
## as stuck instead of endlessly resetting the timer on each brief spike.
func _update_stuck(kart: KartController, context: AIRaceContext, dt: float) -> void:
	var alpha: float = clampf(STUCK_SPEED_SMOOTHING_RATE * dt, 0.0, 1.0)
	_speed_ema = lerpf(_speed_ema, absf(kart.get_speed()), alpha)
	if _speed_ema < STUCK_SPEED_THRESHOLD:
		_stuck_elapsed += dt
	else:
		_stuck_elapsed = 0.0
		_reverse_remaining = 0.0
	match evaluate_stuck(_stuck_elapsed):
		StuckAction.RESPAWN:
			if context != null and context.request_respawn.is_valid():
				context.request_respawn.call(kart)
			_stuck_elapsed = 0.0
		StuckAction.REVERSE:
			if _reverse_remaining <= 0.0:
				_reverse_remaining = REVERSE_DURATION_SECONDS
		StuckAction.NONE:
			pass
	if _reverse_remaining > 0.0:
		_reverse_remaining -= dt


## While FROZEN, only `plan_start_boost()`'s pre-rolled timing decides the
## throttle press; a kart that never had a plan rolled (e.g. a bare unit test)
## conservatively never presses, so it never risks a wheelspin penalty either.
func _compute_start_frame(context: AIRaceContext) -> InputFrame:
	var frame: InputFrame = InputFrame.zero()
	if context == null or not context.get_countdown_phase_seconds.is_valid() or _planned_start_phase < 0.0:
		return frame
	var phase: float = context.get_countdown_phase_seconds.call()
	if phase <= 0.0:
		return frame # countdown has not actually started yet (or GO already passed)
	if not _start_pressed and phase <= _planned_start_phase:
		_start_pressed = true
	frame.throttle = 1.0 if _start_pressed else 0.0
	return frame


func _compute_finished_frame(kart: KartController, nav: AINavigator.NavResult) -> InputFrame:
	var frame: InputFrame = InputFrame.zero()
	frame.steer = clampf(_angle_to_target(kart, nav.target_point) * 2.0, -1.0, 1.0)
	frame.throttle = 1.0 if kart.get_speed_ratio() < FINISHED_SPEED_RATIO else 0.0
	return frame


## Rolls this kart's one-shot start-boost timing plan from `start_boost_skill`
## (spec §13.4). Must run before COUNTDOWN's first tick; AIController calls
## this once from `setup()`.
func plan_start_boost(kart: KartController, profile: AIDifficultyProfile) -> void:
	var window: float = kart.tuning.start_boost_window
	if _rng.randf() < profile.start_boost_skill:
		_planned_start_phase = _rng.randf_range(0.0, window * 0.5)
	else:
		_planned_start_phase = window + _rng.randf_range(0.1, 1.0)
