class_name AIDifficulty
extends RefCounted

## Validates `AIDifficultyProfile` resources and derives the small set of
## values every AI module needs from one, so nobody re-derives them ad hoc.

## Spec §13.6 last bullet: difficulty is judgment quality, never a speed cheat.
const MAX_SPEED_CONFIDENCE: float = 1.0


## Returns whether `profile` is safe to drive with, pushing one error per
## violation instead of silently clamping bad authored content.
static func validate(profile: AIDifficultyProfile) -> bool:
	if profile == null:
		push_error("AIDifficulty.validate: profile is null")
		return false
	var valid: bool = true
	if profile.speed_confidence > MAX_SPEED_CONFIDENCE:
		push_error("AIDifficultyProfile %s speed_confidence exceeds 1.0 (spec §13.6)" % profile.id)
		valid = false
	if profile.ai_tick_hz <= 0.0:
		push_error("AIDifficultyProfile %s ai_tick_hz must be positive" % profile.id)
		valid = false
	if profile.lane_offset_min > profile.lane_offset_max:
		push_error("AIDifficultyProfile %s lane_offset_min exceeds lane_offset_max" % profile.id)
		valid = false
	return valid


## Returns the per-tick interval in seconds for `profile.ai_tick_hz`.
static func tick_interval(profile: AIDifficultyProfile) -> float:
	return 1.0 / maxf(profile.ai_tick_hz, 1.0)


## Returns a deterministic per-kart base lane offset (spec §13.3).
static func sample_base_lane_offset(profile: AIDifficultyProfile, rng: RandomNumberGenerator) -> float:
	return rng.randf_range(profile.lane_offset_min, profile.lane_offset_max)
