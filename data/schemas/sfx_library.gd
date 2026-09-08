class_name SfxLibrary
extends Resource

## Data-only sound catalogue shared by SFX and BGM.

@export var streams: Dictionary[StringName, AudioStream] = {}
@export var volume_db: Dictionary[StringName, float] = {}
@export var pitch_variance: Dictionary[StringName, float] = {}

var _warned_ids: Dictionary[StringName, bool] = {}


## Looks up a sound, warning only once per missing id without interrupting play.
func lookup(id: StringName) -> AudioStream:
	var stream: AudioStream = streams.get(id)
	if stream == null and not _warned_ids.has(id):
		_warned_ids[id] = true
		push_warning("Unknown audio id: %s" % id)
	return stream


## Returns the authored gain in decibels (unity when unspecified).
func get_volume_db(id: StringName) -> float:
	return volume_db.get(id, 0.0)


## Returns the nonnegative random pitch radius around the requested pitch.
func get_pitch_variance(id: StringName) -> float:
	return maxf(0.0, pitch_variance.get(id, 0.0))
