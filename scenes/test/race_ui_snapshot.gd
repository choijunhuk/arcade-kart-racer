extends Node
## Windowed visual review tool for the in-race UI (not headless): runs a real
## race with 1-4 local players (each driven by ScriptedRaceInputProvider, so
## split screen is exercised exactly as in local multiplayer), saves PNGs at
## fixed race times, then optionally shows the pause overlay and a results
## screen over the live frame and captures those too.
## With demo=1 every player starts an item roulette (rocket dart) and gets a
## threat warning right after the first shot, so later shots show the
## roulette, the landed item and the warning banner.
## usage: godot --path . --resolution 1600x900 res://scenes/test/race_ui_snapshot.tscn -- <out_dir> [players 1-4] [track_index 0-3] [shot_times_csv] [overlays 0/1] [demo 0/1]
## example: ... -- /tmp/split2 2 0 1,6 0

const RACE_SCENE: String = "res://race/race.tscn"
const TRACKS: Array[String] = [
	"res://data/tracks/track_01.tres",
	"res://data/tracks/track_02.tres",
	"res://data/tracks/track_03.tres",
	"res://data/tracks/track_04.tres",
]
const DRIVERS: Array[StringName] = [&"aurora_vale", &"cinder_rook", &"nyx_calder", &"orin_gale"]
const KARTS: Array[StringName] = [&"medium", &"light", &"heavy", &"medium"]
const SAMPLE_NAMES: Array[String] = ["Nyx Calder", "Aurora Vale", "Cinder Rook", "Orin Gale", "Luma Circuit", "Bramble Knox", "Echo Meridian", "Flint Harbor"]
const SAMPLE_KARTS: Array[String] = ["Zephyr Needle", "Medium", "Basalt Crown", "Light", "Copper Arc", "Heavy", "Medium", "Light"]
const PLAYER_SPEED_RATIO: float = 0.92
const OVERLAY_SETTLE_SECONDS: float = 1.4

var _out_dir: String = "/tmp/race_ui"
var _manager: RaceManager
var _shot_ticks: Array[int] = []
var _overlays: bool = false
var _demo: bool = false
var _tick: int = 0
var _shot: int = 0
var _capture_pending: bool = false
var _finishing: bool = false


func _ready() -> void:
	GameState.automation_mode = true
	var args: PackedStringArray = OS.get_cmdline_user_args()
	_out_dir = args[0] if args.size() > 0 else _out_dir
	var players: int = clampi(int(args[1]) if args.size() > 1 else 1, 1, 4)
	var track_index: int = clampi(int(args[2]) if args.size() > 2 else 0, 0, TRACKS.size() - 1)
	var times: PackedStringArray = (args[3] if args.size() > 3 else "4,9").split(",", false)
	_overlays = args.size() > 4 and args[4] == "1"
	_demo = args.size() > 5 and args[5] == "1"
	for part: String in times:
		_shot_ticks.append(int(float(part) * Engine.physics_ticks_per_second))
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var overlay: Node = get_node_or_null(^"/root/DebugOverlay")
	if overlay != null:
		overlay.set("visible", false)
	_manager = (load(RACE_SCENE) as PackedScene).instantiate() as RaceManager
	_manager.configure(_config(players, load(TRACKS[track_index]) as TrackData), func(kart: KartController, line: RacingLine) -> InputProvider:
		return ScriptedRaceInputProvider.new(kart, line, PLAYER_SPEED_RATIO))
	add_child(_manager)


func _config(players: int, track: TrackData) -> RaceConfig:
	var slots: Array[PlayerSlot] = []
	for index: int in range(players):
		var slot: PlayerSlot = PlayerSlot.new()
		slot.device_id = index
		slot.driver_id = DRIVERS[index]
		slot.kart_id = KARTS[index]
		slot.grid_slot = index
		slots.append(slot)
	var config: RaceConfig = RaceConfigBuilder.build_local(slots, track, load("res://data/ai/normal.tres") as AIDifficultyProfile)
	if players == 1:
		config.race_mode = RaceConfig.RaceMode.SINGLE_RACE
		config.player_driver = load("res://data/drivers/%s.tres" % DRIVERS[0]) as DriverData
		config.player_kart = load("res://data/karts/%s.tres" % KARTS[0]) as KartData
	config.laps = 3
	config.seed = 7
	return config


func _physics_process(_delta: float) -> void:
	_tick += 1
	if _shot < _shot_ticks.size() and _tick >= _shot_ticks[_shot]:
		_capture_pending = true
	if _shot >= _shot_ticks.size() and not _finishing:
		_finishing = true
		_finish.call_deferred()


func _process(_delta: float) -> void:
	if not _capture_pending:
		return
	_capture_pending = false
	_save("shot_%02d" % _shot)
	if _demo and _shot == 0:
		_start_demo()
	_shot += 1


func _start_demo() -> void:
	var item: ItemData = load("res://data/items/rocket_dart.tres") as ItemData
	for kart: KartController in _manager.get_human_karts():
		kart.item_slot.begin_roulette(item)
		EventBus.threat_warning.emit(kart, &"hunter_drone", 4.0)


func _finish() -> void:
	if _overlays:
		var pause_menu: PauseMenu = _manager.get_node(^"PauseMenu") as PauseMenu
		pause_menu.show_menu(_manager)
		await get_tree().create_timer(OVERLAY_SETTLE_SECONDS).timeout
		_save("pause")
		pause_menu.hide_menu()
		var results: ResultsScreen = _manager.get_node(^"ResultsScreen") as ResultsScreen
		EventBus.race_state_changed.emit(RaceState.FINISHING, RaceState.RESULTS)
		results.show_results(_sample_entries(), null)
		await get_tree().create_timer(OVERLAY_SETTLE_SECONDS * 2.0).timeout
		_save("results")
	get_tree().quit()


func _save(shot_name: String) -> void:
	var path: String = "%s/%s.png" % [_out_dir, shot_name]
	get_viewport().get_texture().get_image().save_png(path)
	print("SNAPSHOT %s t=%.1fs" % [path, _tick / float(Engine.physics_ticks_per_second)])


## Plausible finished-race rows built from the real roster names.
func _sample_entries() -> Array[RaceResults.Entry]:
	var entries: Array[RaceResults.Entry] = []
	var karts: Array[KartController] = _manager.get_karts()
	for index: int in range(karts.size()):
		var entry: RaceResults.Entry = RaceResults.Entry.new()
		entry.rank = index + 1
		entry.grid_slot = index
		entry.driver_name = SAMPLE_NAMES[index % SAMPLE_NAMES.size()]
		entry.kart_display_name = SAMPLE_KARTS[index % SAMPLE_KARTS.size()]
		entry.total_time_seconds = 128.412 + index * 1.873
		entry.best_lap_seconds = 41.207 + index * 0.412
		entry.is_human = index == 1
		entry.is_new_record = index == 1
		entries.append(entry)
	return entries
