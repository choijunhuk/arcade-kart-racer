class_name SimSpeedClass
extends RefCounted

## CLI name <-> RaceConfig.SpeedClass mapping for tools/run_sim.sh's --class flag.

const NAMES: Dictionary[StringName, RaceConfig.SpeedClass] = {
	&"cruise": RaceConfig.SpeedClass.CRUISE,
	&"standard": RaceConfig.SpeedClass.STANDARD,
	&"turbo": RaceConfig.SpeedClass.TURBO,
}


## Resolves a `--class` value, defaulting unknown/missing names to STANDARD.
static func parse(raw_value: String) -> RaceConfig.SpeedClass:
	return NAMES.get(StringName(raw_value), RaceConfig.SpeedClass.STANDARD)


## Returns the lowercase CLI name for a speed class, for summary output.
static func name_for(speed_class: RaceConfig.SpeedClass) -> String:
	for key: StringName in NAMES:
		if NAMES[key] == speed_class:
			return String(key)
	return "standard"
