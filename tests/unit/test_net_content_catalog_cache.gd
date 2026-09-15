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


## Backlog item 2: a directory gets at most one scan attempt per process
## (bounded retry = 0) — one unloadable file (corrupt install, missing
## `.import` in an export) must not permanently disable the memo by getting
## rescanned, and re-`push_warning`'d, on every subsequent lookup. That
## re-scan-per-lookup behavior was itself the DoS this memo exists to
## prevent, reinstated, plus attacker-paced log growth on a headless server.
func test_a_broken_file_degrades_the_catalog_once_not_per_lookup() -> void:
	DirAccess.make_dir_recursive_absolute(_DIR)
	var broken: FileAccess = FileAccess.open(_DIR.path_join("broken.tres"), FileAccess.WRITE)
	assert_not_null(broken)
	broken.store_string("not a valid resource")
	broken.close()
	assert_false(NetContentCatalog.has(_DIR, "alpha"), "the one scan attempt must not see an id that does not exist")
	_save_driver("cache_test_a.tres", "alpha")
	assert_false(NetContentCatalog.has(_DIR, "alpha"), "a directory gets at most one scan attempt: once degraded by a broken file, a second lookup must not rescan to pick up a file written afterward")
	# Asserted once, after both `has()` calls above, as an exact total for
	# the whole test: this script's own push_warning fires once per failed
	# load attempt, so exactly 1 here — not 2 — is what proves the second
	# call above did not rescan (the bug this test guards against).
	assert_push_warning("broken.tres")
	assert_push_warning_count(1)
	# Review item 8: the one scan attempt resolved zero usable resources (the
	# only file in the directory failed to parse), so _scan() must also have
	# push_error'd once, loudly, that this directory's catalog is empty —
	# not just the per-file push_warning above.
	assert_push_error("scanned empty")
	assert_push_error_count(1)
	# broken.tres fails to parse via Godot's own text-resource loader on that
	# one attempt; that loader reports the malformed content as its own raw
	# engine errors — same pattern as test_phase11_robustness.gd's
	# corrupt-settings-file case. Unlike the push_warning above, that
	# diagnostic count is Godot's own implementation detail, not this
	# suite's to pin exactly (backlog item 7) — assert at least one instead.
	var engine_errors: Array = []
	for err: GutTrackedError in get_errors():
		if err.is_engine_error():
			err.handled = true
			engine_errors.append(err)
	assert_true(engine_errors.size() >= 1, "broken.tres must raise at least one engine error via Godot's own text-resource loader")


## Backlog item 5: an empty catalog (directory missing, or every file in it
## broken — the memo above caches that empty result too) used to turn
## `default_driver_id()`/`default_kart_id()`'s `_scan(...)[0]` into an
## out-of-bounds script error for the rest of the process's lifetime, on
## every host()/admit. `_DIR` is never created here, so its scan is empty
## without needing a real broken/missing shipped content directory.
func test_default_driver_and_kart_id_fall_back_to_preloaded_defaults_for_an_empty_catalog() -> void:
	assert_eq(NetContentCatalog._first_id_or_default(_DIR, NetContentCatalog.DEFAULT_DRIVER), String(NetContentCatalog.DEFAULT_DRIVER.id))
	assert_eq(NetContentCatalog._first_id_or_default(_DIR, NetContentCatalog.DEFAULT_KART), String(NetContentCatalog.DEFAULT_KART.id))
	# Review item 8: falling back must not also be silent — the first call
	# above's scan (the only one; the second reuses the memo) must have
	# push_error'd once that this directory's catalog is empty.
	assert_push_error("scanned empty")
	assert_push_error_count(1)
