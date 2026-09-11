class_name CameraPreset
extends Resource

## Named subset of camera feel values swapped by the `camera_preset` gameplay
## setting. Arcade favors a quick, punchy follow; Cinematic favors a softer,
## lower, more distant-feeling chase. Any tuning field not listed here is left
## untouched on the active `FeelTuning` resource.

const ARCADE_ID: String = "arcade"
const CINEMATIC_ID: String = "cinematic"
const VALID_IDS: PackedStringArray = [ARCADE_ID, CINEMATIC_ID]
const ARCADE_PATH: String = "res://data/tuning/camera_preset_arcade.tres"
const CINEMATIC_PATH: String = "res://data/tuning/camera_preset_cinematic.tres"

@export var follow_stiffness: float = 10.0
@export var camera_height: float = 2.2
@export var speed_fov_add: float = 14.0
@export var boost_fov_add: float = 8.0
@export var drift_side_offset: float = 0.7


## Returns `id` when it names a known preset, otherwise the Arcade default.
static func resolve_id(id: String) -> String:
	return id if VALID_IDS.has(id) else ARCADE_ID


## Maps a (possibly unknown) preset id to its Resource path, defaulting unknown ids to Arcade.
static func path_for_id(id: String) -> String:
	return CINEMATIC_PATH if resolve_id(id) == CINEMATIC_ID else ARCADE_PATH


## Loads the preset Resource for `id`, resolving unknown ids to Arcade.
static func load_for_id(id: String) -> CameraPreset:
	return load(path_for_id(id)) as CameraPreset
