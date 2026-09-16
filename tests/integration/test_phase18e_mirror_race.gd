extends GutTest

## Phase 18e-2: a mirror-config race flips the player's SubViewportContainer
## and re-flips the HUD/minimap so text stays legible while the minimap
## still reads mirrored with the world; a non-mirror race stays identity.

const RACE_SCENE: PackedScene = preload("res://race/race.tscn")
const TEST_TRACK_SCENE: PackedScene = preload("res://track/tracks/test_loop/test_loop.tscn")
const KART: KartData = preload("res://data/karts/medium.tres")
const DIFFICULTY: AIDifficultyProfile = preload("res://data/ai/normal.tres")


func test_mirror_config_flips_container_hud_and_minimap() -> void:
	await _assert_view_state(true)


func test_non_mirror_config_leaves_everything_at_identity_scale() -> void:
	await _assert_view_state(false)


func _assert_view_state(mirror: bool) -> void:
	var race: RaceManager = RACE_SCENE.instantiate() as RaceManager
	race.configure(_config(mirror), _provider)
	add_child_autofree(race)
	await wait_physics_frames(1)
	var split: SplitScreen = race.get_node("SplitScreen") as SplitScreen
	assert_eq(split.get_viewport_count(), 1)
	var expected: float = -1.0 if mirror else 1.0
	for container: Node in split.get_children():
		var view: SubViewportContainer = container as SubViewportContainer
		if view == null:
			continue
		assert_almost_eq(view.scale.x, expected, 0.001, "container.scale.x")
		assert_almost_eq(view.scale.y, 1.0, 0.001, "container.scale.y")
	var huds: Array[RaceHud] = split.get_huds()
	assert_eq(huds.size(), 1)
	var hud: RaceHud = huds[0]
	assert_almost_eq(hud.scale.x, expected, 0.001, "hud.scale.x counter-flips the container")
	assert_almost_eq(hud.scale.y, 1.0, 0.001, "hud.scale.y")
	var minimap: Control = hud.get_node("Minimap") as Control
	assert_almost_eq(minimap.scale.x, expected, 0.001, "minimap re-flips to read mirrored with the world")


func _config(mirror: bool) -> RaceConfig:
	var track: TrackData = TrackData.new()
	track.id = &"test_loop"
	track.display_name = "Test Loop"
	track.scene = TEST_TRACK_SCENE
	track.laps_default = 3
	var config: RaceConfig = RaceConfig.new()
	config.track = track
	config.laps = 3
	config.kart_count = 2
	config.ai_difficulty = DIFFICULTY
	config.player_kart = KART
	config.player_slot = 0
	config.items_enabled = false
	config.mirror = mirror
	return config


func _provider(kart: KartController, line: RacingLine) -> InputProvider:
	var provider: ScriptedInputProvider = ScriptedInputProvider.new(kart, line)
	provider.set_drift_on_corners(true)
	return provider
