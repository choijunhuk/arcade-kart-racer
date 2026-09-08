extends Node

## Runs real Phase 5 scripted-follower races. Proper AI replaces the temporary
## providers in Phase 6; this script validates race flow and finish reliability.

const RACE_SCENE: PackedScene = preload("res://race/race.tscn")
const TRACK_DATA: TrackData = preload("res://data/tracks/track_01.tres")
const KART_DATA: KartData = preload("res://data/karts/medium.tres")
const DEFAULT_LAPS: int = 3
const DEFAULT_KARTS: int = 8
const DEFAULT_RACES: int = 1
const MAX_KARTS: int = 8
const MIN_VALUE: int = 1
const SIM_TIME_SCALE: float = 4.0
const MAX_SECONDS_PER_LAP: float = 150.0
const FLOW_MARGIN_SECONDS: float = 30.0
const PHYSICS_TICKS_PER_SECOND: int = 60

var _kart_names_by_id: Dictionary[int, String] = {}
var _respawns: Dictionary[String, int] = {}
var _wall_head_on_count: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	Engine.time_scale = SIM_TIME_SCALE
	EventBus.kart_respawned.connect(_on_kart_respawned)
	EventBus.kart_hit.connect(_on_kart_hit)
	var options: Dictionary = parse_options(OS.get_cmdline_user_args())
	var race_outputs: Array[Dictionary] = []
	var failed: bool = false
	for race_index: int in range(int(options["races"])):
		var race_output: Dictionary = await _run_one_race(
			int(options["laps"]), int(options["karts"]), race_index + 1,
		)
		race_outputs.append(race_output)
		failed = failed or has_unfinished(race_output["times"] as Dictionary)
	Engine.time_scale = 1.0
	var payload: Dictionary = {
		"success": not failed,
		"track": String(TRACK_DATA.id),
		"laps": int(options["laps"]),
		"karts": int(options["karts"]),
		"races": race_outputs,
	}
	print(JSON.stringify(payload))
	get_tree().quit(1 if failed else 0)


## Parses `--laps N --karts N --races N`, clamping every value to safe bounds.
static func parse_options(args: PackedStringArray) -> Dictionary:
	var options: Dictionary = {
		"laps": DEFAULT_LAPS,
		"karts": DEFAULT_KARTS,
		"races": DEFAULT_RACES,
	}
	var index: int = 0
	while index < args.size():
		var key: String = args[index]
		if index + 1 >= args.size():
			break
		var value: int = maxi(MIN_VALUE, args[index + 1].to_int())
		match key:
			"--laps":
				options["laps"] = value
			"--karts":
				options["karts"] = mini(value, MAX_KARTS)
			"--races":
				options["races"] = value
		index += 2
	return options


## Returns true when any kart is missing a non-negative finish time.
static func has_unfinished(times: Dictionary) -> bool:
	if times.is_empty():
		return true
	for value: Variant in times.values():
		if float(value) < 0.0:
			return true
	return false


func _run_one_race(laps: int, kart_count: int, race_number: int) -> Dictionary:
	_reset_metrics()
	var config: RaceConfig = RaceConfig.new()
	config.track = TRACK_DATA
	config.laps = laps
	config.kart_count = kart_count
	config.player_kart = KART_DATA
	config.player_slot = 0
	var manager: RaceManager = RACE_SCENE.instantiate() as RaceManager
	manager.configure(config, _make_scripted_player)
	get_tree().root.add_child(manager)
	for kart: KartController in manager.get_karts():
		var kart_name: String = String(kart.name)
		_kart_names_by_id[kart.get_instance_id()] = kart_name
		_respawns[kart_name] = 0

	var max_ticks: int = roundi(
		(float(laps) * MAX_SECONDS_PER_LAP + FLOW_MARGIN_SECONDS)
		* float(PHYSICS_TICKS_PER_SECOND) / SIM_TIME_SCALE
	)
	for _tick: int in range(max_ticks):
		if manager.get_state() == RaceState.RESULTS:
			break
		await get_tree().physics_frame

	var finish_order: Array[String] = []
	var times: Dictionary[String, float] = {}
	for kart: KartController in manager.get_karts():
		times[String(kart.name)] = -1.0
	for entry: RaceResults.Entry in manager.get_results():
		finish_order.append(entry.kart_name)
		times[entry.kart_name] = entry.total_time_seconds
	var output: Dictionary = {
		"race": race_number,
		"finish_order": finish_order,
		"times": times,
		"respawns": _respawns.duplicate(),
		"wall_head_on_count": _wall_head_on_count,
	}
	manager.free()
	return output


func _make_scripted_player(kart: KartController, line: RacingLine) -> InputProvider:
	var provider: ScriptedRaceInputProvider = ScriptedRaceInputProvider.new(kart, line, 1.0)
	provider.set_drift_on_corners(true)
	return provider


func _reset_metrics() -> void:
	_kart_names_by_id.clear()
	_respawns.clear()
	_wall_head_on_count = 0


func _on_kart_respawned(kart: Node) -> void:
	var kart_name: String = String(_kart_names_by_id.get(kart.get_instance_id(), ""))
	if not kart_name.is_empty():
		_respawns[kart_name] = int(_respawns.get(kart_name, 0)) + 1


func _on_kart_hit(kart: Node, hit_type: int) -> void:
	if _kart_names_by_id.has(kart.get_instance_id()) and hit_type == HitReactor.HitType.BUMP:
		_wall_head_on_count += 1
