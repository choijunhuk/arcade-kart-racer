extends GutTest

## 19-D item 2 in the real race scene: a menu-stamped intro holds the
## countdown in COUNTDOWN with the player camera flying over, then 3-2-1-GO
## runs unchanged; the engine time scale is never touched.

const TRACK_PATH: String = "res://track/tracks/test_loop/test_loop.tscn"
const INTRO_SECONDS: float = 0.5

var _ticks: Array[int] = []


func before_each() -> void:
	_ticks.clear()
	EventBus.countdown_tick.connect(_on_tick)


func after_each() -> void:
	EventBus.countdown_tick.disconnect(_on_tick)


func _on_tick(value: int) -> void:
	_ticks.append(value)


func test_intro_flyover_precedes_the_countdown_in_a_real_race() -> void:
	var manager: RaceManager = (load("res://race/race.tscn") as PackedScene).instantiate() as RaceManager
	var track: TrackData = TrackData.new()
	track.id = &"test_loop"
	track.display_name = "Test Loop"
	track.scene = load(TRACK_PATH) as PackedScene
	var config: RaceConfig = RaceConfig.new()
	config.track = track
	config.laps = 1
	config.kart_count = 2
	config.player_kart = load("res://data/karts/medium.tres") as KartData
	config.player_slot = 0
	config.intro_seconds = INTRO_SECONDS
	manager.configure(config, func(kart: KartController, line: RacingLine) -> InputProvider:
		return ScriptedInputProvider.new(kart, line))
	add_child_autofree(manager)
	await get_tree().physics_frame
	var countdown: Countdown = manager.get_node("Countdown") as Countdown
	var camera: RaceCamera = (manager.get_node("SplitScreen") as SplitScreen).get_cameras()[0] as RaceCamera
	assert_eq(manager.get_state(), RaceState.COUNTDOWN)
	assert_true(countdown.is_intro_active())
	assert_eq(camera.get_cinematic_mode(), CameraCinematics.Mode.INTRO)
	assert_eq(_ticks.size(), 0)
	for _tick: int in range(roundi(INTRO_SECONDS * 60.0) + 4):
		await get_tree().physics_frame
	assert_eq(_ticks, [3] as Array[int], "3 fires once the flyover ends")
	assert_eq(camera.get_cinematic_mode(), CameraCinematics.Mode.NONE)
	for _tick: int in range(240):
		if manager.get_state() == RaceState.RACING:
			break
		await get_tree().physics_frame
	assert_eq(manager.get_state(), RaceState.RACING)
	assert_eq(_ticks, [3, 2, 1, 0] as Array[int])
	assert_eq(Engine.time_scale, 1.0)
