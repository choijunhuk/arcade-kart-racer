class_name ExportSelftest
extends Node

## Runs inside a real exported build (`<binary> -- --selftest`) where command-line scene
## overrides are disabled. Verifies the paths that only break after export: data scanning
## through `.tres.remap` files (items, karts, drivers, tracks) and instancing every
## playable track through its TrackData's remapped scene reference.
## Prints one `EXPORT_SELFTEST {...}` line and exits 0 on success, 1 on failure.

const DATA_DIRECTORIES: Dictionary = {
	"items": "res://data/items",
	"karts": "res://data/karts",
	"drivers": "res://data/drivers",
	"tracks": "res://data/tracks",
}
const MIN_COUNTS: Dictionary = {"items": 7, "karts": 3, "drivers": 1, "tracks": 4}
const SETTLE_FRAMES: int = 30

var _report: Dictionary = {"exported": OS.has_feature("template"), "counts": {}, "track_children": {}, "errors": []}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	for key: String in DATA_DIRECTORIES:
		var found: Array = ResourceScanner.scan_tres(DATA_DIRECTORIES[key])
		(_report["counts"] as Dictionary)[key] = found.size()
		if found.size() < int(MIN_COUNTS[key]):
			(_report["errors"] as Array).append("%s: found %d, expected at least %d" % [key, found.size(), MIN_COUNTS[key]])
	for resource: Resource in ResourceScanner.scan_tres(DATA_DIRECTORIES["tracks"]):
		var data: TrackData = resource as TrackData
		if data == null:
			(_report["errors"] as Array).append("non-TrackData resource in %s: %s" % [DATA_DIRECTORIES["tracks"], resource.resource_path])
			continue
		await _instance_track(data)
	_report["passed"] = (_report["errors"] as Array).is_empty()
	print("EXPORT_SELFTEST " + JSON.stringify(_report))
	get_tree().quit(0 if bool(_report["passed"]) else 1)


## Instances one track through its TrackData `scene` reference, which is the
## `.tscn.remap` path an exported build resolves, and records its child count.
func _instance_track(data: TrackData) -> void:
	var id: String = String(data.id)
	if data.scene == null:
		(_report["errors"] as Array).append("track %s has no scene" % id)
		return
	var track: Node = data.scene.instantiate()
	add_child(track)
	for _frame: int in range(SETTLE_FRAMES):
		await get_tree().process_frame
	(_report["track_children"] as Dictionary)[id] = track.get_child_count()
	if track.get_child_count() == 0:
		(_report["errors"] as Array).append("track %s instanced with no children" % id)
	remove_child(track)
	track.free()
