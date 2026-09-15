class_name GhostTrackReset
extends RefCounted

## One-time ghost cleanup paired with SaveManagerService's version 3 migration.
## PR #30 replaced track_02's geometry outright (new centerline, checkpoints and
## length), so any ghost recorded on the old layout would replay across ground
## that no longer exists. Deleting the file is idempotent by design: a missing
## ghosts directory or missing file is the normal steady state once this has run.

const TRACK_02_ID: StringName = &"track_02_lumen_underpass"


## Removes the saved ghost (and any stray in-progress write) for one track id.
## Safe to call repeatedly: an absent directory or file is not an error.
static func remove_ghost(track_id: StringName, directory: String = GhostRecording.DEFAULT_DIRECTORY) -> void:
	for suffix: String in ["", ".tmp"]:
		var path: String = directory.path_join("%s.json%s" % [track_id, suffix])
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


## Convenience entry point for the track_02 (Lumen Underpass) reset.
static func remove_track_02_ghost(directory: String = GhostRecording.DEFAULT_DIRECTORY) -> void:
	remove_ghost(TRACK_02_ID, directory)
