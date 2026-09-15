extends GutTest

const DIRECTORY: String = "user://phase19-ghost-track-reset"
const OTHER_TRACK_ID: StringName = &"track_01_ridgeline_circuit"


func before_each() -> void:
	_clear_directory()


func after_each() -> void:
	_clear_directory()


func test_remove_ghost_deletes_only_the_target_track_file() -> void:
	_write(GhostTrackReset.TRACK_02_ID, "track_02 fixture")
	_write(OTHER_TRACK_ID, "track_01 fixture")

	GhostTrackReset.remove_track_02_ghost(DIRECTORY)

	assert_false(FileAccess.file_exists(_path(GhostTrackReset.TRACK_02_ID)))
	assert_true(FileAccess.file_exists(_path(OTHER_TRACK_ID)))


func test_remove_ghost_also_clears_a_stray_tmp_write() -> void:
	_write(GhostTrackReset.TRACK_02_ID, "track_02 fixture")
	var tmp_path: String = _path(GhostTrackReset.TRACK_02_ID) + ".tmp"
	_write_path(tmp_path, "in-progress write")

	GhostTrackReset.remove_track_02_ghost(DIRECTORY)

	assert_false(FileAccess.file_exists(_path(GhostTrackReset.TRACK_02_ID)))
	assert_false(FileAccess.file_exists(tmp_path))


func test_remove_ghost_tolerates_a_missing_directory() -> void:
	var missing_directory: String = "user://phase19-ghost-track-reset-does-not-exist"
	assert_false(DirAccess.dir_exists_absolute(missing_directory))

	GhostTrackReset.remove_track_02_ghost(missing_directory)

	assert_false(DirAccess.dir_exists_absolute(missing_directory))


func test_remove_ghost_runs_safely_when_called_more_than_once() -> void:
	_write(GhostTrackReset.TRACK_02_ID, "track_02 fixture")

	GhostTrackReset.remove_track_02_ghost(DIRECTORY)
	assert_false(FileAccess.file_exists(_path(GhostTrackReset.TRACK_02_ID)))

	# A second run (e.g. an already-migrated save reloading) must stay a no-op.
	GhostTrackReset.remove_track_02_ghost(DIRECTORY)
	assert_false(FileAccess.file_exists(_path(GhostTrackReset.TRACK_02_ID)))


## Security review finding: an arbitrary track_id must never resolve outside
## the ghosts directory (e.g. "../save" reaching user://save.json).
func test_remove_ghost_rejects_a_path_traversal_track_id() -> void:
	var result: Error = GhostTrackReset.remove_ghost(&"../save", DIRECTORY)

	assert_eq(result, ERR_INVALID_PARAMETER)


func _path(track_id: StringName) -> String:
	return DIRECTORY.path_join("%s.json" % track_id)


func _write(track_id: StringName, contents: String) -> void:
	_write_path(_path(track_id), contents)


func _write_path(path: String, contents: String) -> void:
	DirAccess.make_dir_recursive_absolute(DIRECTORY)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(file)
	file.store_string(contents)
	file.close()


func _clear_directory() -> void:
	if not DirAccess.dir_exists_absolute(DIRECTORY):
		return
	var dir: DirAccess = DirAccess.open(DIRECTORY)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if not dir.current_is_dir():
			DirAccess.remove_absolute(DIRECTORY.path_join(entry))
		entry = dir.get_next()
	dir.list_dir_end()
