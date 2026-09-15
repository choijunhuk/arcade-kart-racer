extends GutTest

## Backlog item 6: `ResourceScanner.scan_tres` re-opened the directory and
## re-loaded every `.tres` on every call — NetContentCatalog.has() alone ran
## it twice per accepted `_selection` RPC. Content is read-only at runtime, so
## a whole-directory scan (empty `listed_files`) is now memoized per
## directory. Proven here by writing a second file to disk after the first
## scan and asserting the memoized result — not the now-larger directory —
## is what a second scan of the same path returns; a real reload would see 2.

const _DIR: String = "user://resource_scanner_cache_test"


func after_each() -> void:
	var directory: DirAccess = DirAccess.open(_DIR)
	if directory != null:
		for file_name: String in directory.get_files():
			directory.remove(file_name)
	DirAccess.remove_absolute(_DIR)


func test_scan_tres_memoizes_a_whole_directory_scan() -> void:
	DirAccess.make_dir_recursive_absolute(_DIR)
	var first: Resource = Resource.new()
	assert_eq(ResourceSaver.save(first, _DIR.path_join("cache_test_a.tres")), OK)
	var scan1: Array[Resource] = ResourceScanner.scan_tres(_DIR)
	assert_eq(scan1.size(), 1, "first scan must see the one file written so far")
	var second: Resource = Resource.new()
	assert_eq(ResourceSaver.save(second, _DIR.path_join("cache_test_b.tres")), OK)
	var raw: DirAccess = DirAccess.open(_DIR)
	assert_eq(raw.get_files().size(), 2, "disk must genuinely have two files now")
	var scan2: Array[Resource] = ResourceScanner.scan_tres(_DIR)
	assert_eq(scan2.size(), 1, "a second whole-directory scan must reuse the memoized listing, not re-scan the directory")


## The exported `.tres.remap` listing path (an explicit `listed_files`) must
## keep working unmemoized: it always reflects exactly the list handed in,
## never a stale directory-wide cache entry for the same directory.
func test_scan_tres_with_explicit_listed_files_bypasses_the_cache() -> void:
	DirAccess.make_dir_recursive_absolute(_DIR)
	var first: Resource = Resource.new()
	assert_eq(ResourceSaver.save(first, _DIR.path_join("cache_test_a.tres")), OK)
	ResourceScanner.scan_tres(_DIR) # Populates the whole-directory cache entry for _DIR.
	var second: Resource = Resource.new()
	assert_eq(ResourceSaver.save(second, _DIR.path_join("cache_test_b.tres")), OK)
	var explicit: Array[Resource] = ResourceScanner.scan_tres(_DIR, PackedStringArray(["cache_test_b.tres"]))
	assert_eq(explicit.size(), 1, "an explicit listed_files scan must always resolve exactly the files it was given")
