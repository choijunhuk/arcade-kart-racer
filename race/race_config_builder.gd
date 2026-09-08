class_name RaceConfigBuilder
extends RefCounted

const DEFAULT_KART_COUNT: int = 8
const MIN_LAPS: int = 1
const MAX_DRIVER_MODIFIER: float = 0.05
const MODIFIABLE_STATS: Array[StringName] = [
	&"max_speed",
	&"acceleration",
	&"handling",
	&"drift_factor",
	&"weight",
]


## Builds the complete immutable-style payload consumed by `RaceManager`.
static func build(
	driver: DriverData,
	kart: KartData,
	track: TrackData,
	difficulty: AIDifficultyProfile,
	laps: int = -1,
	kart_count: int = DEFAULT_KART_COUNT,
) -> RaceConfig:
	var config: RaceConfig = RaceConfig.new()
	config.player_driver = driver
	config.player_kart = kart
	config.track = track
	config.ai_difficulty = difficulty
	config.laps = maxi(MIN_LAPS, track.laps_default if laps < MIN_LAPS else laps)
	config.kart_count = maxi(1, kart_count)
	config.player_slot = 0
	config.items_enabled = true
	return config


## Returns a deep duplicate with allowlisted driver percentage modifiers applied.
static func apply_driver_mods(kart: KartData, driver: DriverData) -> KartData:
	var modified: KartData = kart.duplicate(true) as KartData
	if driver == null:
		return modified
	for stat_name: StringName in driver.stat_mods:
		if not MODIFIABLE_STATS.has(stat_name):
			push_warning("Driver modifier ignores unsupported kart stat: %s" % String(stat_name))
			continue
		var base_value: float = float(modified.get(stat_name))
		var modifier: float = clampf(
			driver.stat_mods[stat_name], -MAX_DRIVER_MODIFIER, MAX_DRIVER_MODIFIER,
		)
		modified.set(stat_name, base_value * (1.0 + modifier))
	return modified
