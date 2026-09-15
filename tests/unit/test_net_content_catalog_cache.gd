extends GutTest

## Backlog item 6, continued: the per-directory scan memo now lives in
## `NetContentCatalog._scan()`/`clear_cache()`, not `ResourceScanner` — moved
## out of tests/unit/test_resource_scanner_cache.gd (deleted) because the
## scanner-level cache broke tests/unit/test_phase9_ui_logic.gd's own
## resource-scan tests, which write different files under the same directory
## path across the same test run. `ResourceScanner` is a general tool used by
## many non-catalog callers whose directory contents legitimately change
## (tests, tooling) and must stay uncached; only the shipped content catalog
## — read-only at runtime — gets memoized, and only here.
##
## Proven the same way the old test proved the scanner-level memo: write a
## second file to disk after the first lookup and assert the memoized
## result — not the now-larger directory — is what a second lookup of the
## same directory sees; a real reload would see both files.

const _DIR: String = "user://net_content_catalog_cache_test"


func after_each() -> void:
	NetContentCatalog.clear_cache()
	var directory: DirAccess = DirAccess.open(_DIR)
	if directory != null:
		for file_name: String in directory.get_files():
			directory.remove(file_name)
	DirAccess.remove_absolute(_DIR)


func _save_driver(file_name: String, id: String) -> void:
	var driver: DriverData = DriverData.new()
	driver.id = StringName(id)
	assert_eq(ResourceSaver.save(driver, _DIR.path_join(file_name)), OK)


func test_has_memoizes_a_whole_directory_scan() -> void:
	DirAccess.make_dir_recursive_absolute(_DIR)
	_save_driver("cache_test_a.tres", "alpha")
	assert_true(NetContentCatalog.has(_DIR, "alpha"), "first lookup must see the one file written so far")
	_save_driver("cache_test_b.tres", "beta")
	var raw: DirAccess = DirAccess.open(_DIR)
	assert_eq(raw.get_files().size(), 2, "disk must genuinely have two files now")
	assert_false(NetContentCatalog.has(_DIR, "beta"), "a second lookup of the same directory must reuse the memoized scan, not re-read the now-larger directory")


func test_clear_cache_forces_a_fresh_scan() -> void:
	DirAccess.make_dir_recursive_absolute(_DIR)
	_save_driver("cache_test_a.tres", "alpha")
	NetContentCatalog.has(_DIR, "alpha") # Populates the memo for _DIR.
	_save_driver("cache_test_b.tres", "beta")
	assert_false(NetContentCatalog.has(_DIR, "beta"), "sanity: the memo must still be stale before clear_cache()")
	NetContentCatalog.clear_cache()
	assert_true(NetContentCatalog.has(_DIR, "beta"), "clear_cache() must drop the memo so the next lookup sees the new file")


func test_unknown_id_falls_back_to_the_existing_default_unchanged() -> void:
	DirAccess.make_dir_recursive_absolute(_DIR)
	_save_driver("cache_test_a.tres", "alpha")
	NetContentCatalog.has(_DIR, "alpha") # Populates the memo for _DIR.
	assert_false(NetContentCatalog.has(_DIR, "missing_id"), "an id absent from the memoized scan must still resolve to false, not error")
	assert_eq(NetContentCatalog.resolve_track("missing_track"), LocalLobby.DEFAULT_TRACK)
	assert_eq(NetContentCatalog.resolve_difficulty("missing_difficulty"), LocalLobby.DEFAULT_DIFFICULTY)


## The exported `.tres.remap` listing path (an explicit `listed_files`) must
## keep resolving correctly regardless of the catalog's own cache state for
## the same directory: `ResourceScanner` carries no memo of its own any
## more — the memo moved to `NetContentCatalog`, which only ever scans
## whole directories, never an explicit `listed_files` — so this always
## reflects exactly the list handed in.
func test_explicit_listed_files_scan_bypasses_the_catalog_cache() -> void:
	DirAccess.make_dir_recursive_absolute(_DIR)
	_save_driver("cache_test_a.tres", "alpha")
	NetContentCatalog.has(_DIR, "alpha") # Populates the catalog's memo for _DIR.
	_save_driver("cache_test_b.tres", "beta")
	var explicit: Array[Resource] = ResourceScanner.scan_tres(_DIR, PackedStringArray(["cache_test_b.tres.remap"]))
	assert_eq(explicit.size(), 1, "an explicit listed_files scan must always resolve exactly the files it was given")
	assert_eq(String((explicit[0] as DriverData).id), "beta")


## Review finding 7: a scan that hits a `ResourceLoader.load()` failure must
## not be memoized as if it were the complete catalog — otherwise a
## transient failure (e.g. a directory caught mid-write) would stay wrong
## for the rest of the process instead of getting a fresh look next call.
func test_a_load_failure_is_never_cached_as_a_complete_scan() -> void:
	DirAccess.make_dir_recursive_absolute(_DIR)
	var broken: FileAccess = FileAccess.open(_DIR.path_join("broken.tres"), FileAccess.WRITE)
	assert_not_null(broken)
	broken.store_string("not a valid resource")
	broken.close()
	assert_false(NetContentCatalog.has(_DIR, "alpha"), "the broken scan must not see an id that does not exist yet")
	assert_push_warning("broken.tres")
	_save_driver("cache_test_a.tres", "alpha")
	assert_true(NetContentCatalog.has(_DIR, "alpha"), "a failed scan must not have been cached, so this lookup must see the file written afterward")
	assert_push_warning("broken.tres")
	# broken.tres fails to parse via Godot's own text-resource loader on each
	# of the two scans above (it is never cached, by design); that loader
	# reports the malformed content as raw engine errors of its own,
	# alongside this script's push_warning — same pattern as
	# test_phase11_robustness.gd's corrupt-settings-file case.
	assert_engine_error_count(6)
