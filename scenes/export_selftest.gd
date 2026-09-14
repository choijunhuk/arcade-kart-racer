class_name ExportSelftest
extends Node

## Runs inside a real exported build (`<binary> -- --selftest`) where command-line scene
## overrides are disabled. Verifies the paths that only break after export: data scanning
## through `.tres.remap` files (items, karts, drivers, tracks) and instancing a race track.
## Prints one `EXPORT_SELFTEST {...}` line and exits 0 on success, 1 on failure.

const DATA_DIRECTORIES: Dictionary = {
	"items": "res://data/items",
	"karts": "res://data/karts",
	"drivers": "res://data/drivers",
	"tracks": "res://data/tracks",
}
const MIN_COUNTS: Dictionary = {"items": 7, "karts": 3, "drivers": 1, "tracks": 1}
const TRACK_SCENE: String = "res://track/tracks/track_01_ridgeline_circuit/track_01_ridgeline_circuit.tscn"
const SETTLE_FRAMES: int = 30

var _report: Dictionary = {"exported": OS.has_feature("template"), "counts": {}, "errors": []}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	for key: String in DATA_DIRECTORIES:
		var found: Array = ResourceScanner.scan_tres(DATA_DIRECTORIES[key])
		(_report["counts"] as Dictionary)[key] = found.size()
		if found.size() < int(MIN_COUNTS[key]):
			(_report["errors"] as Array).append("%s: found %d, expected at least %d" % [key, found.size(), MIN_COUNTS[key]])
	var packed: PackedScene = load(TRACK_SCENE) as PackedScene
	if packed == null:
		(_report["errors"] as Array).append("track scene failed to load: %s" % TRACK_SCENE)
	else:
		var track: Node = packed.instantiate()
		add_child(track)
		for _frame: int in range(SETTLE_FRAMES):
			await get_tree().process_frame
		_report["track_children"] = track.get_child_count()
		if track.get_child_count() == 0:
			(_report["errors"] as Array).append("track instanced with no children")
	_report["passed"] = (_report["errors"] as Array).is_empty()
	print("EXPORT_SELFTEST " + JSON.stringify(_report))
	get_tree().quit(0 if bool(_report["passed"]) else 1)
