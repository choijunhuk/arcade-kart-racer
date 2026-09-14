class_name TutorialLauncher
extends RefCounted

## Builds the onboarding tutorial's solo `RaceConfig` on `test_loop` and
## navigates to it. Shared by the main menu's first-run prompt and the
## settings menu's "Replay Tutorial" entry point so both trigger the exact
## same flow.

const TUTORIAL_RACE_PATH: String = "res://ui/tutorial/tutorial_race.tscn"
const TRACK_SCENE: PackedScene = preload("res://track/tracks/test_loop/test_loop.tscn")
const DEFAULT_DRIVER: DriverData = preload("res://data/drivers/aurora_vale.tres")
const DEFAULT_KART: KartData = preload("res://data/karts/medium.tres")
const DEFAULT_DIFFICULTY: AIDifficultyProfile = preload("res://data/ai/normal.tres")


## Navigates `menu` into a fresh solo tutorial race on `test_loop`.
static func start(menu: MenuScreen) -> void:
	var track: TrackData = TrackData.new()
	track.id = &"tutorial_test_loop"
	track.display_name = "Test Loop"
	track.scene = TRACK_SCENE
	track.laps_default = 1
	var config: RaceConfig = RaceConfigBuilder.build(
		DEFAULT_DRIVER, DEFAULT_KART, track, DEFAULT_DIFFICULTY, 1, 1,
	)
	config.items_enabled = true
	GameState.pending_race_config = config
	GameState.tutorial_active = true
	menu.go_to(TUTORIAL_RACE_PATH)
