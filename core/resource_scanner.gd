class_name ResourceScanner
extends RefCounted

const REMAP_SUFFIX: String = ".remap"


## Loads `.tres`/`.res` resources, including exported `.tres.remap` listings,
## from one directory in deterministic logical-path order.
static func scan_tres(
	directory_path: String,
	listed_files: PackedStringArray = PackedStringArray(),
) -> Array[Resource]:
	var resources: Array[Resource] = []
	resources.assign((_scan(directory_path, listed_files)["resources"] as Array))
	return resources


## Same scan as `scan_tres`, plus whether every matched file actually loaded
## (review finding 7): the only caller that memoizes a whole-directory scan —
## `NetContentCatalog._scan()` — must never cache a result that skipped a
## `ResourceLoader.load()` failure (or an unopenable directory) as if it were
## the complete picture.
static func scan_tres_complete(
	directory_path: String,
	listed_files: PackedStringArray = PackedStringArray(),
) -> Dictionary:
	return _scan(directory_path, listed_files)


static func _scan(directory_path: String, listed_files: PackedStringArray) -> Dictionary:
	var resources: Array[Resource] = []
	var file_names: PackedStringArray = listed_files.duplicate()
	if file_names.is_empty():
		var directory: DirAccess = DirAccess.open(directory_path)
		if directory == null:
			push_warning("Resource directory could not be opened: %s" % directory_path)
			return {"resources": resources, "complete": false}
		file_names = directory.get_files()
	file_names.sort()
	var complete: bool = true
	for file_name: String in file_names:
		if not _is_resource_file(file_name):
			continue
		var logical_file_name: String = file_name
		if logical_file_name.ends_with(REMAP_SUFFIX):
			logical_file_name = logical_file_name.substr(
				0, logical_file_name.length() - REMAP_SUFFIX.length(),
			)
		var resource_path: String = directory_path.path_join(logical_file_name)
		var resource: Resource = ResourceLoader.load(resource_path)
		if resource == null:
			push_warning("Resource could not be loaded: %s" % resource_path)
			complete = false
			continue
		resources.append(resource)
	return {"resources": resources, "complete": complete}


static func _is_resource_file(file_name: String) -> bool:
	return (
		file_name.ends_with(".tres")
		or file_name.ends_with(".tres.remap")
		or file_name.ends_with(".res")
	)
