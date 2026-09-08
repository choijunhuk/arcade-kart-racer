class_name AIDriftPlanner
extends RefCounted

## Curvature-gated drift entry/hold/release (spec §13.4), split out of
## `ai_driver.gd` to keep both files under the spec §29 400-line budget.
## `drift_skill` controls entry hesitation and premature-release "mistakes";
## direction-lock/steer-floor mirror the proven Phase 5
## `ScriptedRaceInputProvider` pattern.

## Mirrors `PhysicsTuning.drift_min_steer` (0.35): DriftController silently
## refuses a hop below that, so the locked steer must clear it with margin.
const MIN_STEER_TO_START_DRIFT: float = 0.4
const COUNTERSTEER_CANCEL_MARGIN: float = 0.9
const DRIFT_RELEASE_CURVATURE_RATIO: float = 0.5
const DRIFT_CANCEL_PROB_PER_SECOND: float = 0.15
## drift_skill=0 still attempts half the eligible corners; skill only closes
## the gap to "never misses one" (spec: skill affects judgment, not physics).
const MIN_ATTEMPT_CHANCE: float = 0.5

var _rng: RandomNumberGenerator
var _locked_direction: int = 0


func _init(rng: RandomNumberGenerator) -> void:
	_rng = rng


## Mutates `frame.steer`/`frame.drift`/`frame.drift_pressed` in place.
func update(frame: InputFrame, kart: KartController, profile: AIDifficultyProfile, nav: AINavigator.NavResult, dt: float) -> void:
	match kart.get_drift_state():
		DriftController.DriftState.HOP:
			frame.steer = float(_locked_direction) * maxf(absf(frame.steer), MIN_STEER_TO_START_DRIFT)
			frame.drift = true
		DriftController.DriftState.HOLD:
			_update_hold(frame, kart, profile, nav.signed_curvature_ahead, dt)
		_:
			_try_enter(frame, kart, profile, nav.signed_curvature_ahead)


func _try_enter(frame: InputFrame, kart: KartController, profile: AIDifficultyProfile, curvature: float) -> void:
	if absf(curvature) < profile.drift_curvature_threshold or kart.get_speed() < 1.0:
		return
	if _rng.randf() > lerpf(MIN_ATTEMPT_CHANCE, 1.0, profile.drift_skill):
		return
	_locked_direction = 1 if curvature > 0.0 else -1
	frame.steer = float(_locked_direction) * maxf(absf(frame.steer), MIN_STEER_TO_START_DRIFT)
	frame.drift = true
	frame.drift_pressed = true


func _update_hold(frame: InputFrame, kart: KartController, profile: AIDifficultyProfile, curvature: float, dt: float) -> void:
	# KartPhysics already locks drift direction. Preserve countersteer so the
	# navigator can widen the turn instead of forcing the kart into the inner wall.
	# Strong opposition cancels DriftController HOLD, so keep a strict margin.
	if frame.steer * float(_locked_direction) < 0.0:
		var limit: float = kart.tuning.drift_min_steer * COUNTERSTEER_CANCEL_MARGIN
		frame.steer = clampf(frame.steer, -limit, limit)
	var release_threshold: float = profile.drift_curvature_threshold * DRIFT_RELEASE_CURVATURE_RATIO
	var tier_reached: bool = kart.get_drift_tier() >= profile.target_tier
	var cancel_prob: float = (1.0 - profile.drift_skill) * DRIFT_CANCEL_PROB_PER_SECOND * dt
	var mistake: bool = _rng.randf() < cancel_prob
	frame.drift = absf(curvature) >= release_threshold and not tier_reached and not mistake
