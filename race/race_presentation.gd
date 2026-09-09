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
	split_screen.configure(world, players, lap_tracker, position_tracker, karts.size(), config.laps, item_manager, track.get_racing_line(), karts)
	particle_budget.configure_cameras(karts, split_screen.get_cameras())
	return split_screen.get_huds()[0]
