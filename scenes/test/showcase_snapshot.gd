extends Node
## Windowed visual review tool (not headless): runs a real 8-kart race on one
## content track with the player kart driven by ScriptedRaceInputProvider, hides
## the debug overlay, and saves PNGs at fixed race times so every visual change
## is judged against the same frames.
## usage: godot --path . --resolution 1600x900 res://scenes/test/showcase_snapshot.tscn -- <out_dir> [track_index 0-3] [shot_times_csv]
## example: ... -- /tmp/look 2 4,9,15

const RACE_SCENE: String = "res://race/race.tscn"
const TRACKS: Array[String] = [
	"res://data/tracks/track_01.tres",
	"res://data/tracks/track_02.tres",
	"res://data/tracks/track_03.tres",
	"res://data/tracks/track_04.tres",
]
const DEFAULT_SHOT_TIMES: Array[float] = [5.0, 10.0, 16.0]
const PLAYER_SPEED_RATIO: float = 0.92

var _out_dir: String = "/tmp/showcase"
var _shot_ticks: Array[int] = []
var _tick: int = 0
var _shot: int = 0
var _capture_pending: bool = false


func _ready() -> void:
	GameState.automation_mode = true
	var args: PackedStringArray = OS.get_cmdline_user_args()
	_out_dir = args[0] if args.size() > 0 else _out_dir
	var track_index: int = clampi(int(args[1]) if args.size() > 1 else 0, 0, TRACKS.size() - 1)
	var times: Array[float] = DEFAULT_SHOT_TIMES.duplicate()
	if args.size() > 2:
		times.clear()
		for part: String in args[2].split(",", false):
			times.append(float(part))
	for seconds: float in times:
		_shot_ticks.append(int(seconds * Engine.physics_ticks_per_second))
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var overlay: Node = get_node_or_null(^"/root/DebugOverlay")
	if overlay != null:
		overlay.set("visible", false)
	var config: RaceConfig = RaceConfigBuilder.build(
		load("res://data/drivers/aurora_vale.tres") as DriverData,
		load("res://data/karts/medium.tres") as KartData,
		load(TRACKS[track_index]) as TrackData,
		load("res://data/ai/normal.tres") as AIDifficultyProfile,
		3, 8,
	)
	config.seed = 7
	var manager: RaceManager = (load(RACE_SCENE) as PackedScene).instantiate() as RaceManager
	manager.configure(config, func(kart: KartController, line: RacingLine) -> InputProvider:
		return ScriptedRaceInputProvider.new(kart, line, PLAYER_SPEED_RATIO))
	add_child(manager)


func _physics_process(_delta: float) -> void:
	_tick += 1
	if _shot < _shot_ticks.size() and _tick >= _shot_ticks[_shot]:
		_capture_pending = true
	if _shot >= _shot_ticks.size():
		get_tree().quit()


func _process(_delta: float) -> void:
	if not _capture_pending:
		return
	_capture_pending = false
	var path: String = "%s/shot_%02d.png" % [_out_dir, _shot]
	get_viewport().get_texture().get_image().save_png(path)
	print("SNAPSHOT %s t=%.1fs" % [path, _tick / float(Engine.physics_ticks_per_second)])
	_shot += 1
