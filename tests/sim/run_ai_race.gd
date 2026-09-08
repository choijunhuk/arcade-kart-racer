extends Node

## Headless AI-only race simulation (spec §13.8). Every kart is
## AIController-driven (`RaceConfig.player_slot = -1`); validates finish
## rate, per-kart respawn/wall-hit budgets, and difficulty pacing without a
## human. `tools/run_sim.sh` runs this once per `--difficulty`; comparing the
## three summaries is how the Phase 6 DoD checks Easy > Normal > Hard.

const RACE_SCENE: PackedScene = preload("res://race/race.tscn")
const MEDIUM_KART: KartData = preload("res://data/karts/medium.tres")
const DIFFICULTY_PROFILES: Dictionary[StringName, AIDifficultyProfile] = {
	&"easy": preload("res://data/ai/easy.tres"),
	&"normal": preload("res://data/ai/normal.tres"),
	&"hard": preload("res://data/ai/hard.tres"),
}
const TRACK_SCENES: Dictionary[StringName, PackedScene] = {
	&"track_01": preload("res://track/tracks/track_01_ridgeline_circuit/track_01_ridgeline_circuit.tscn"),
	&"test_hairpin": preload("res://track/tracks/test_hairpin/test_hairpin.tscn"),
	&"test_loop": preload("res://track/tracks/test_loop/test_loop.tscn"),
	&"test_loop_hills": preload("res://track/tracks/test_loop_hills/test_loop_hills.tscn"),
}
const DEFAULT_LAPS: int = 3
const DEFAULT_KARTS: int = 8
const DEFAULT_RACES: int = 1
const DEFAULT_DIFFICULTY: StringName = &"normal"
const DEFAULT_TRACK: StringName = &"track_01"
const MAX_KARTS: int = 8
const MIN_VALUE: int = 1
const SIM_TIME_SCALE: float = 8.0
const MAX_SECONDS_PER_LAP: float = 150.0
const FLOW_MARGIN_SECONDS: float = 30.0
const PHYSICS_TICKS_PER_SECOND: int = 60
## Spec §13.8 DoD: respawns/kart and wall head-ons/lap budgets.
const MAX_RESPAWNS_PER_KART: int = 2
const MAX_HEAD_ON_PER_LAP: float = 3.0

var _kart_names_by_id: Dictionary[int, String] = {}
var _respawns: Dictionary[String, int] = {}
var _wall_head_on_counts: Dictionary[String, int] = {}
var _wall_head_on_count: int = 0
var _drift_started_count: int = 0
var _tier3_release_count: int = 0
var _shortcut_take_count: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	Engine.time_scale = SIM_TIME_SCALE
	EventBus.kart_respawned.connect(_on_kart_respawned)
	EventBus.kart_hit.connect(_on_kart_hit)
	EventBus.drift_started.connect(_on_drift_started)
	EventBus.drift_ended.connect(_on_drift_ended)
	var options: Dictionary = parse_options(OS.get_cmdline_user_args())
	var difficulty: AIDifficultyProfile = DIFFICULTY_PROFILES[options["difficulty"]]
	var track_scene: PackedScene = TRACK_SCENES[options["track"]]
	var race_outputs: Array[Dictionary] = []
	var failed: bool = false
	for race_index: int in range(int(options["races"])):
		var race_output: Dictionary = await _run_one_race(
			int(options["laps"]), int(options["karts"]), race_index + 1, difficulty, track_scene,
		)
		race_outputs.append(race_output)
		failed = failed or _race_failed(race_output, int(options["laps"]))
	Engine.time_scale = 1.0
	var payload: Dictionary = {
		"success": not failed,
		"difficulty": String(options["difficulty"]),
		"track": String(options["track"]),
		"laps": int(options["laps"]),
		"karts": int(options["karts"]),
		"races": race_outputs,
		"summary": _summarize(race_outputs, int(options["laps"])),
	}
	print(JSON.stringify(payload))
	get_tree().quit(1 if failed else 0)


## Parses `--laps N --karts N --races N --difficulty easy|normal|hard
## --track NAME`, clamping numeric values to safe bounds and falling back to
## the default for an unrecognized difficulty/track name.
static func parse_options(args: PackedStringArray) -> Dictionary:
	var options: Dictionary = {
		"laps": DEFAULT_LAPS,
		"karts": DEFAULT_KARTS,
		"races": DEFAULT_RACES,
		"difficulty": DEFAULT_DIFFICULTY,
		"track": DEFAULT_TRACK,
	}
	var index: int = 0
	while index < args.size():
		var key: String = args[index]
		if index + 1 >= args.size():
			break
		var raw_value: String = args[index + 1]
		match key:
			"--laps":
				options["laps"] = maxi(MIN_VALUE, raw_value.to_int())
			"--karts":
				options["karts"] = mini(maxi(MIN_VALUE, raw_value.to_int()), MAX_KARTS)
			"--races":
				options["races"] = maxi(MIN_VALUE, raw_value.to_int())
			"--difficulty":
				var difficulty_name: StringName = StringName(raw_value)
				options["difficulty"] = difficulty_name if DIFFICULTY_PROFILES.has(difficulty_name) else DEFAULT_DIFFICULTY
			"--track":
				var track_name: StringName = StringName(raw_value)
				options["track"] = track_name if TRACK_SCENES.has(track_name) else DEFAULT_TRACK
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


## Spec §13.8 DoD: every kart must finish, no kart may respawn more than
## twice, and no kart's wall head-ons may exceed the per-lap budget.
static func _race_failed(race_output: Dictionary, laps: int) -> bool:
	if has_unfinished(race_output["times"] as Dictionary):
		return true
	for count: Variant in (race_output["respawns"] as Dictionary).values():
		if int(count) > MAX_RESPAWNS_PER_KART:
			return true
	for count: Variant in (race_output["wall_head_on_counts"] as Dictionary).values():
		if float(count) > MAX_HEAD_ON_PER_LAP * float(laps):
			return true
	return false


## Mean per-lap finish time across every finisher in every race (spec §13.8:
## this is what separates Easy/Normal/Hard when `tools/run_sim.sh` is run
## once per difficulty and the three summaries are compared).
static func _summarize(race_outputs: Array[Dictionary], laps: int) -> Dictionary:
	var lap_time_samples: Array[float] = []
	for race_output: Dictionary in race_outputs:
		for value: Variant in (race_output["times"] as Dictionary).values():
			if float(value) >= 0.0:
				lap_time_samples.append(float(value) / float(laps))
	var mean_lap_time: float = 0.0
	if not lap_time_samples.is_empty():
		var total: float = 0.0
		for sample: float in lap_time_samples:
			total += sample
		mean_lap_time = total / float(lap_time_samples.size())
	return {"mean_lap_time_seconds": mean_lap_time, "finisher_samples": lap_time_samples.size()}


func _run_one_race(laps: int, kart_count: int, race_number: int, difficulty: AIDifficultyProfile, track_scene: PackedScene) -> Dictionary:
	_reset_metrics()
	var track_data: TrackData = TrackData.new()
	track_data.id = &"sim_track"
	track_data.scene = track_scene
	var config: RaceConfig = RaceConfig.new()
	config.track = track_data
	config.laps = laps
	config.kart_count = kart_count
	config.player_kart = MEDIUM_KART
	config.player_slot = -1
	config.ai_difficulty = difficulty
	config.seed = race_number # vary each race's AI rolls instead of repeating race 1
	var manager: RaceManager = RACE_SCENE.instantiate() as RaceManager
	manager.configure(config)
	get_tree().root.add_child(manager)
	_register_shortcut_tracking(manager)
	for kart: KartController in manager.get_karts():
		var kart_name: String = String(kart.name)
		_kart_names_by_id[kart.get_instance_id()] = kart_name
		_respawns[kart_name] = 0
		_wall_head_on_counts[kart_name] = 0

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
		"wall_head_on_counts": _wall_head_on_counts.duplicate(),
		"wall_head_on_count": _wall_head_on_count,
		"drifts_started": _drift_started_count,
		"tier3_releases": _tier3_release_count,
		"shortcut_takes": _shortcut_take_count,
	}
	manager.free()
	return output


## Connects every TrackShortcut's `kart_entered` once the race's track scene
## exists, so "shortcut takes" can be counted without RaceManager/PositionTracker
## exposing a dedicated signal for it.
func _register_shortcut_tracking(manager: RaceManager) -> void:
	var track: Node = manager.get_node_or_null("Track")
	var shortcuts: Node = track.get_node_or_null("Shortcuts") if track != null else null
	if shortcuts == null:
		return
	for child: Node in shortcuts.get_children():
		if child is TrackShortcut:
			(child as TrackShortcut).kart_entered.connect(_on_shortcut_entered)


func _reset_metrics() -> void:
	_kart_names_by_id.clear()
	_respawns.clear()
	_wall_head_on_counts.clear()
	_wall_head_on_count = 0
	_drift_started_count = 0
	_tier3_release_count = 0
	_shortcut_take_count = 0


func _on_kart_respawned(kart: Node) -> void:
	var kart_name: String = String(_kart_names_by_id.get(kart.get_instance_id(), ""))
	if not kart_name.is_empty():
		_respawns[kart_name] = int(_respawns.get(kart_name, 0)) + 1


func _on_kart_hit(kart: Node, hit_type: int) -> void:
	if hit_type != HitReactor.HitType.BUMP:
		return
	var kart_name: String = String(_kart_names_by_id.get(kart.get_instance_id(), ""))
	if kart_name.is_empty():
		return
	_wall_head_on_counts[kart_name] = int(_wall_head_on_counts.get(kart_name, 0)) + 1
	_wall_head_on_count += 1


func _on_drift_started(_kart: Node, _direction: int) -> void:
	_drift_started_count += 1


func _on_drift_ended(_kart: Node, released_tier: int) -> void:
	if released_tier >= 3:
		_tier3_release_count += 1


func _on_shortcut_entered(_body: Node3D) -> void:
	_shortcut_take_count += 1
