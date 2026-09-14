class_name SpeedClassStats
extends RefCounted

## Pure per-class stat multipliers (Phase 18e-1 spec §18e). Handling, drift
## charge, and boost power stay identical across classes by design.

const MAX_SPEED_MULTIPLIERS: Dictionary[RaceConfig.SpeedClass, float] = {
	RaceConfig.SpeedClass.CRUISE: 0.85,
	RaceConfig.SpeedClass.STANDARD: 1.0,
	RaceConfig.SpeedClass.TURBO: 1.15,
}
const ACCELERATION_MULTIPLIERS: Dictionary[RaceConfig.SpeedClass, float] = {
	RaceConfig.SpeedClass.CRUISE: 0.9,
	RaceConfig.SpeedClass.STANDARD: 1.0,
	RaceConfig.SpeedClass.TURBO: 1.1,
}
const DISPLAY_NAMES: Dictionary[RaceConfig.SpeedClass, String] = {
	RaceConfig.SpeedClass.CRUISE: "CRUISE",
	RaceConfig.SpeedClass.STANDARD: "STANDARD",
	RaceConfig.SpeedClass.TURBO: "TURBO",
}


## Returns the max_speed multiplier for `speed_class`; unknown values are STANDARD.
static func max_speed_multiplier(speed_class: RaceConfig.SpeedClass) -> float:
	return MAX_SPEED_MULTIPLIERS.get(speed_class, 1.0)


## Returns the acceleration multiplier for `speed_class`; unknown values are STANDARD.
static func acceleration_multiplier(speed_class: RaceConfig.SpeedClass) -> float:
	return ACCELERATION_MULTIPLIERS.get(speed_class, 1.0)


## Returns a duplicate of `kart` with class multipliers applied; `kart` is never mutated.
static func apply(kart: KartData, speed_class: RaceConfig.SpeedClass) -> KartData:
	var scaled: KartData = kart.duplicate(true) as KartData
	scaled.max_speed = kart.max_speed * max_speed_multiplier(speed_class)
	scaled.acceleration = kart.acceleration * acceleration_multiplier(speed_class)
	return scaled


## Returns the uppercase display label for `speed_class`.
static func display_name(speed_class: RaceConfig.SpeedClass) -> String:
	return DISPLAY_NAMES.get(speed_class, "STANDARD")
