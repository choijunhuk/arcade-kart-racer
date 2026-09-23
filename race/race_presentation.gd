class_name RacePresentation
extends RefCounted

## Selects observer or player-viewport presentation without gameplay ownership.


## Configures cameras, HUDs, speed lines, and nearest-camera LOD for one race.
static func configure(
	world: World3D, config: RaceConfig, karts: Array[KartController],
	players: Array[KartController], lap_tracker: LapTracker,
	position_tracker: PositionTracker, item_manager: ItemManager,
	track: TrackRoot, observer_camera: RaceCamera, observer_hud: RaceHud,
	observer_speed_lines: SpeedLines, split_screen: SplitScreen,
	particle_budget: ParticleBudgetController,
) -> RaceHud:
	var observed: KartController = players[0] if not players.is_empty() else karts[0]
	if players.is_empty():
		observer_camera.current = true
		observer_hud.visible = true
		observer_speed_lines.visible = true
		observer_camera.set_target(observed)
		observer_speed_lines.set_target(observed)
		observer_hud.bind(null, lap_tracker, position_tracker, karts.size(), config.laps, item_manager, track.get_racing_line(), karts)
		particle_budget.configure(karts, observer_camera)
		return observer_hud
	observer_camera.current = false
	observer_hud.visible = false
	observer_speed_lines.visible = false
	split_screen.configure(world, players, lap_tracker, position_tracker, karts.size(), config.laps, item_manager, track.get_racing_line(), karts, config.mirror)
	seed_saved_best_laps(config, karts, players, split_screen.get_huds(), SaveManager)
	particle_budget.configure_cameras(karts, split_screen.get_cameras())
	return split_screen.get_huds()[0]


## Seeds each player HUD's lap split with that player's saved best for this
## race's record key. The profile index follows RaceResults: order among the
## human grid slots.
static func seed_saved_best_laps(
	config: RaceConfig, karts: Array[KartController], players: Array[KartController],
	huds: Array[RaceHud], save_manager: SaveManagerService,
) -> void:
	if config.track == null:
		return
	for index: int in range(mini(players.size(), huds.size())):
		var feedback: HudFeedback = huds[index].get_node_or_null(^"Feedback") as HudFeedback
		if feedback != null:
			var profile: int = human_profile_index(config, karts, players[index])
			feedback.seed_best_lap(HudFeedback.saved_best_seconds(save_manager, config.record_track_id(), profile))


## 0-based rank of `player` among the human grid slots (karts are in grid order).
static func human_profile_index(config: RaceConfig, karts: Array[KartController], player: KartController) -> int:
	var profile: int = 0
	for slot: int in range(karts.size()):
		if karts[slot] == player:
			return profile
		if config.is_human_grid_slot(slot):
			profile += 1
	return 0


## Binds and resets pause/results overlays before a countdown begins.
static func prepare_overlays(
	manager: RaceManager, config: RaceConfig, player_kart: KartController,
	pause_menu: PauseMenu, results_screen: ResultsScreen,
) -> void:
	pause_menu.bind(
		manager, player_kart != null and not GameState.automation_mode and not GameState.is_networked,
		config.player_device_ids(),
	)
	pause_menu.hide_menu()
	results_screen.hide_results()
