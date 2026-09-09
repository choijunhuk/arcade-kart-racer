class_name RaceModes
extends Node

## Race composition adapter for persistent GP state and race-local time trials.

var time_trial: TimeTrialGhost
var _config: RaceConfig


## Rebuilds the optional mode owner without changing the normal race lifecycle.
func setup(config: RaceConfig, player: KartController, track: TrackRoot, hud: RaceHud) -> void:
	_config = config
	if time_trial != null:
		time_trial.free()
		time_trial = null
	if config.race_mode == RaceConfig.RaceMode.TIME_TRIAL:
		time_trial = TimeTrialGhost.new()
		add_child(time_trial)
		time_trial.setup(player, track, config.track.id, config.laps)
		track.get_node("ItemBoxes").hide()
	hud.bind_time_trial(time_trial)


## Ends recording before post-finish driving replaces the player's input provider.
func player_finished() -> void:
	if time_trial != null:
		time_trial.stop()


## Awards this GP round once, and persists only a completed player's cup best.
func finalize(entries: Array[RaceResults.Entry]) -> void:
	var gp: GrandPrix = GameState.grand_prix_state
	if _config.race_mode != RaceConfig.RaceMode.GRAND_PRIX or gp == null:
		return
	if not gp.record_results(_config.gp_round, entries) or not gp.is_complete():
		return
	var standings: Array[GrandPrix.Standing] = gp.standings()
	for index: int in range(standings.size()):
		if standings[index].slot == gp.player_slot():
			var error: Error = SaveManager.record_grand_prix(gp.record_key(), index + 1, standings[index].points)
			if error != OK:
				push_warning("GP best could not be saved: %s" % error_string(error))


## Installs the next round in GameState; the results button replaces the scene.
static func next_grand_prix_race() -> bool:
	var gp: GrandPrix = GameState.grand_prix_state
	if gp == null or not gp.advance():
		return false
	GameState.pending_race_config = gp.current_config()
	GameState.selected_track_id = GameState.pending_race_config.track.id
	return true
