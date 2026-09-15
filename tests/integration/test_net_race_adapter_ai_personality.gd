extends GutTest

## Split out of test_net_race_adapter.gd (400-line rule, backlog item 8).
##
## Backlog item 4: `NetRace._build_automated_source`'s NetHumanAIController
## must drive with its own kart's DriverData.ai_personality, exactly like
## RaceManager._spawn_ai_kart() does locally, instead of a neutral default
## (aurora_vale's ai_personality is non-default on every axis, so a wrong
## fallback to null would fail this). Server-authoritative AI needs no
## protocol change for this — only the local simulation this peer's own
## input derives from is affected.
##
## Backlog item 8: this test used to live in test_net_race_adapter.gd and
## share that file's `before_each()`-built session/manager, which meant
## giving the fixture's own local kart a personality-bearing driver id
## ("aurora_vale") to make the assertion meaningful. Every other test in
## that file also runs with `session.automated = true`, so the shared
## fixture's local kart would have driven with a non-neutral personality in
## every one of them instead of just this one. Building its own isolated
## single-kart session/manager here keeps that file's fixture on the
## driverless "nova" id it always used, and needs no `CaptureSession`
## (packet capture is irrelevant to this assertion).
func test_automated_source_uses_the_local_karts_driver_personality() -> void:
	var session: NetSession = NetSession.new()
	session.automated = true
	session.players = [{"peer": 1}]
	add_child_autofree(session)
	session.set_physics_process(false)
	GameState.net_session = session
	GameState.is_networked = true
	GameState.automation_mode = true
	var config: RaceConfig = RaceConfig.new()
	config.track = preload("res://data/tracks/track_01.tres")
	config.player_kart = preload("res://data/karts/medium.tres")
	config.kart_count = 1
	config.laps = 1
	var player: PlayerSlot = PlayerSlot.new()
	player.grid_slot = 0
	player.device_id = -1
	player.driver_id = &"aurora_vale"
	player.kart_id = &"medium"
	config.players.append(player)
	var manager: RaceManager = (load("res://race/race.tscn") as PackedScene).instantiate() as RaceManager
	manager.configure(config)
	add_child_autofree(manager)
	var kart: KartController = manager.get_karts()[session.local_slot()]
	var controller: AIController = kart.get_node("NetHumanAIController") as AIController
	assert_not_null(controller, "the automated human must be driven by a real AIController")
	var expected: AIPersonality = kart.get_driver_data().ai_personality
	assert_not_null(expected, "sanity: the test driver must actually carry a personality")
	assert_eq(controller.get("_personality"), expected, "the automated human's AIController must receive its own kart's driver personality, not the neutral default")

func after_each() -> void:
	GameState.net_session = null
	GameState.is_networked = false
	GameState.automation_mode = false
