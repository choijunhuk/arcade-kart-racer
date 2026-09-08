class_name ResourceScanner
extends RefCounted

## Loads valid `.tres` resources from one directory in deterministic path order.
static func scan_tres(directory_path: String) -> Array[Resource]:
	var resources: Array[Resource] = []
	var directory: DirAccess = DirAccess.open(directory_path)
	if directory == null:
		push_warning("Resource directory could not be opened: %s" % directory_path)
		return resources
	var file_names: PackedStringArray = directory.get_files()
	file_names.sort()
	for file_name: String in file_names:
		if not file_name.ends_with(".tres"):
			continue
		var resource_path: String = directory_path.path_join(file_name)
		var resource: Resource = ResourceLoader.load(resource_path)
		if resource == null:
			push_warning("Resource could not be loaded: %s" % resource_path)
			continue
		resources.append(resource)
	return resources
