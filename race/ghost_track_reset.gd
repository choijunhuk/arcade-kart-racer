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
## Rejects a non-filename id (mirrors GhostRecording's own guard) instead of
## resolving it against the directory. Returns the first deletion error hit
## (also logged), or OK when every existing file was removed successfully.
static func remove_ghost(track_id: StringName, directory: String = GhostRecording.DEFAULT_DIRECTORY) -> Error:
	if not String(track_id).is_valid_filename():
		return ERR_INVALID_PARAMETER
	var result: Error = OK
	for suffix: String in ["", ".tmp"]:
		var path: String = directory.path_join("%s.json%s" % [track_id, suffix])
		if FileAccess.file_exists(path):
			var error: Error = DirAccess.remove_absolute(path)
			if error != OK:
				push_warning("Failed to delete ghost file %s: %s" % [path, error_string(error)])
				if result == OK:
					result = error
	return result


## Convenience entry point for the track_02 (Lumen Underpass) reset.
static func remove_track_02_ghost(directory: String = GhostRecording.DEFAULT_DIRECTORY) -> Error:
	return remove_ghost(TRACK_02_ID, directory)
