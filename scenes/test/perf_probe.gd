class_name PerformanceProbe
extends Node

## Windowed 12-kart race probe. Measures real frame intervals after warm-up.

const RACE_SCENE: PackedScene = preload("res://race/race.tscn")
const TRACK_DATA: TrackData = preload("res://data/tracks/track_01.tres")
const KART_DATA: KartData = preload("res://data/karts/medium.tres")
const AI_DIFFICULTY: AIDifficultyProfile = preload("res://data/ai/normal.tres")
const DEFAULT_KART_COUNT: int = 12
const DEFAULT_DURATION_SECONDS: float = 30.0
const WARMUP_SECONDS: float = 2.0
const MICROSECONDS_PER_SECOND: float = 1_000_000.0
const PROBE_LAPS: int = 3
const PROBE_SEED: int = 8_008
const FRAME_BUDGET_SECONDS: float = 0.033
const MILLISECONDS_PER_SECOND: float = 1000.0

var _race: RaceManager
var _kart_count: int = DEFAULT_KART_COUNT
var _duration_seconds: float = DEFAULT_DURATION_SECONDS
var _elapsed_real: float = 0.0
var _measured_real: float = 0.0
var _measured_frames: int = 0
var _worst_frame_seconds: float = 0.0
var _last_frame_usec: int = 0
var _over_budget_frames: int = 0
var _worst_frame_monitors: Dictionary = {}


func _ready() -> void:
	_parse_arguments(OS.get_cmdline_user_args())
	_race = RACE_SCENE.instantiate() as RaceManager
	_race.configure(build_config(_kart_count))
	add_child(_race)
	_last_frame_usec = Time.get_ticks_usec()
	print("PERF_PROBE start karts=%d duration=%.1fs warmup=%.1fs" % [_kart_count, _duration_seconds, WARMUP_SECONDS])


func _process(_delta: float) -> void:
	var now_usec: int = Time.get_ticks_usec()
	var frame_seconds: float = float(now_usec - _last_frame_usec) / MICROSECONDS_PER_SECOND
	_last_frame_usec = now_usec
	var after_warmup: bool = _elapsed_real >= WARMUP_SECONDS
	_elapsed_real += frame_seconds
	if after_warmup:
		_measured_real += frame_seconds
		_measured_frames += 1
		if frame_seconds > FRAME_BUDGET_SECONDS:
			_over_budget_frames += 1
		if frame_seconds > _worst_frame_seconds:
			_worst_frame_seconds = frame_seconds
			_worst_frame_monitors = {
				"at_seconds": _elapsed_real,
				"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * MILLISECONDS_PER_SECOND,
				"physics_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * MILLISECONDS_PER_SECOND,
				"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
				"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			}
	if _measured_real >= _duration_seconds:
		_finish()


## Builds the same all-AI RaceManager configuration used by the windowed probe.
func build_config(kart_count: int) -> RaceConfig:
	var config: RaceConfig = RaceConfig.new()
	config.track = TRACK_DATA
	config.laps = PROBE_LAPS
	config.kart_count = clampi(kart_count, 1, RaceManager.MAX_KART_COUNT)
	config.player_slot = -1
	config.player_kart = KART_DATA
	config.ai_difficulty = AI_DIFFICULTY
	config.items_enabled = true
	config.seed = PROBE_SEED
	return config


func _parse_arguments(arguments: PackedStringArray) -> void:
	if arguments.size() >= 1 and arguments[0].is_valid_int():
		_kart_count = clampi(arguments[0].to_int(), 1, RaceManager.MAX_KART_COUNT)
	if arguments.size() >= 2 and arguments[1].is_valid_float():
		_duration_seconds = maxf(arguments[1].to_float(), 1.0)


func _finish() -> void:
	var mean_fps: float = float(_measured_frames) / maxf(_measured_real, 0.001)
	var result: Dictionary = {
		"karts": _kart_count,
		"warmup_seconds": WARMUP_SECONDS,
		"frames_over_33ms": _over_budget_frames,
		"worst_frame_monitors": _worst_frame_monitors,
		"duration_seconds": snappedf(_measured_real, 0.001),
		"mean_fps": snappedf(mean_fps, 0.01),
		"worst_frame_ms": snappedf(_worst_frame_seconds * MILLISECONDS_PER_SECOND, 0.01),
		"gpu_particles": ParticleBudget.count_gpu_particles(_race),
		"renderer": RenderingServer.get_video_adapter_name(),
	}
	print("PERF_PROBE ", JSON.stringify(result))
	get_tree().quit(0)
