extends Node
## Windowed visual check for any scene: instantiates it, lets the game run,
## saves PNG snapshots at fixed intervals, then quits. Autoloads are live
## because this runs as a normal scene (not a `-s` script).
## usage: godot --path . res://scenes/test/scene_snapshot.tscn -- <scene_path> <out_dir> [seconds] [interval]

const DEFAULT_SCENE: String = "res://race/race.tscn"
const DEFAULT_OUT_DIR: String = "/tmp/scene"
const DEFAULT_SECONDS: float = 20.0
const DEFAULT_INTERVAL: float = 5.0

var _out_dir: String = DEFAULT_OUT_DIR
var _total_ticks: int = 0
var _interval_ticks: int = 0
var _tick: int = 0
var _shot: int = 0
var _capture_pending: bool = false


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var scene_path: String = args[0] if args.size() > 0 else DEFAULT_SCENE
	_out_dir = args[1] if args.size() > 1 else DEFAULT_OUT_DIR
	var seconds: float = float(args[2]) if args.size() > 2 else DEFAULT_SECONDS
	var interval: float = float(args[3]) if args.size() > 3 else DEFAULT_INTERVAL
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_total_ticks = int(seconds * Engine.physics_ticks_per_second)
	_interval_ticks = maxi(1, int(interval * Engine.physics_ticks_per_second))
	add_child((load(scene_path) as PackedScene).instantiate())


func _physics_process(_delta: float) -> void:
	if _tick % _interval_ticks == 0:
		_capture_pending = true
	_tick += 1
	if _tick >= _total_ticks:
		get_tree().quit()


func _process(_delta: float) -> void:
	if not _capture_pending:
		return
	_capture_pending = false
	var path: String = "%s/shot_%02d.png" % [_out_dir, _shot]
	get_viewport().get_texture().get_image().save_png(path)
	print("SNAPSHOT %s t=%.1fs" % [path, _tick / float(Engine.physics_ticks_per_second)])
	_shot += 1
