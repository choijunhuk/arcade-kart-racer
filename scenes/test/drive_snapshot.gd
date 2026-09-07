extends Node
## Windowed visual check (not headless): instantiates the kart sandbox,
## swaps the player input for ScriptedInputProvider (racing-line follower),
## drives for N seconds and saves PNG snapshots at fixed intervals.
## usage: godot --path . res://scenes/test/drive_snapshot.tscn -- <out_dir> [seconds] [interval] [drift|nodrift] [track_index]

const SANDBOX_SCENE: String = "res://scenes/test/kart_sandbox.tscn"
const DEFAULT_OUT_DIR: String = "/tmp/drive"
const DEFAULT_SECONDS: float = 20.0
const DEFAULT_INTERVAL: float = 5.0

var _kart: KartController
var _out_dir: String = DEFAULT_OUT_DIR
var _total_ticks: int = 0
var _interval_ticks: int = 0
var _tick: int = 0
var _shot: int = 0
var _capture_pending: bool = false


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	_out_dir = args[0] if args.size() > 0 else DEFAULT_OUT_DIR
	var seconds: float = float(args[1]) if args.size() > 1 else DEFAULT_SECONDS
	var interval: float = float(args[2]) if args.size() > 2 else DEFAULT_INTERVAL
	var drift_on_corners: bool = args.size() > 3 and args[3] == "drift"
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_total_ticks = int(seconds * Engine.physics_ticks_per_second)
	_interval_ticks = maxi(1, int(interval * Engine.physics_ticks_per_second))

	var track_index: int = int(args[4]) if args.size() > 4 else 0
	var sandbox: Node = (load(SANDBOX_SCENE) as PackedScene).instantiate()
	add_child(sandbox)
	if track_index > 0:
		sandbox.call("_select_track", track_index)
	_kart = sandbox.get_node("Kart") as KartController
	var racing_line: Path3D = sandbox.get_child(0).get_node("RacingLine") as Path3D
	var provider: ScriptedInputProvider = ScriptedInputProvider.new(_kart, racing_line)
	provider.set_drift_on_corners(drift_on_corners)
	_kart.set_input_provider(provider)


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
	var img: Image = get_viewport().get_texture().get_image()
	var path: String = "%s/drive_%02d.png" % [_out_dir, _shot]
	img.save_png(path)
	print("SNAPSHOT %s t=%.1fs speed=%.1f state=%d grounded=%s pos=%s" % [
		path, _tick / float(Engine.physics_ticks_per_second), _kart.get_speed(), _kart.get_state(),
		str(_kart.is_grounded()), str(_kart.global_position.snapped(Vector3.ONE * 0.1))])
	_shot += 1
