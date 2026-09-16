extends GutTest

## Phase 18e-2: mirror mode's record-key suffixing, GP round propagation,
## human steer inversion, and the forced-off online path.


func test_record_track_id_suffixes_only_when_mirrored() -> void:
	var config: RaceConfig = RaceConfig.new()
	config.track = TrackData.new()
	config.track.id = &"track_01"
	assert_eq(config.record_track_id(), &"track_01", "non-mirror keeps the exact pre-18e id")
	config.mirror = true
	assert_eq(config.record_track_id(), &"track_01_mirror")


func test_grand_prix_record_key_appends_mirror_suffix_and_stays_compatible() -> void:
	var track: TrackData = TrackData.new()
	track.id = &"t"
	var config: RaceConfig = _gp_config()

	var standard: GrandPrix = GrandPrix.new()
	standard.setup(config, [track])
	assert_eq(standard.record_key(), &"horizon_cup/normal", "non-mirror STANDARD keeps the pre-18e key")

	config.mirror = true
	var mirrored: GrandPrix = GrandPrix.new()
	mirrored.setup(config, [track])
	assert_eq(mirrored.record_key(), &"horizon_cup_mirror/normal")

	config.speed_class = RaceConfig.SpeedClass.TURBO
	var turbo_mirrored: GrandPrix = GrandPrix.new()
	turbo_mirrored.setup(config, [track])
	assert_eq(turbo_mirrored.record_key(), &"horizon_cup_turbo_mirror/normal")


func test_grand_prix_round_config_carries_mirror_into_every_round() -> void:
	var config: RaceConfig = _gp_config()
	config.mirror = true
	var track_one: TrackData = TrackData.new()
	track_one.id = &"track_a"
	var track_two: TrackData = TrackData.new()
	track_two.id = &"track_b"
	var gp: GrandPrix = GrandPrix.new()
	gp.setup(config, [track_one, track_two])
	assert_true(gp.current_config().mirror, "round 1 config must inherit mirror")
	gp.record_results(0, [_finished_entry(0)])
	assert_true(gp.advance())
	assert_true(gp.current_config().mirror, "round 2 config must also inherit mirror")


func test_player_input_provider_mirrored_negates_steer() -> void:
	var provider: PlayerInputProvider = PlayerInputProvider.new()
	provider.set_strength_override(func(action: StringName, _device: int) -> float:
		return 1.0 if action == InputActions.STEER_RIGHT else 0.0)
	var plain: InputFrame = provider.get_frame()
	assert_gt(plain.steer, 0.0, "unmirrored steer-right must stay positive")

	var mirrored_provider: PlayerInputProvider = PlayerInputProvider.new()
	mirrored_provider.mirrored = true
	mirrored_provider.set_strength_override(func(action: StringName, _device: int) -> float:
		return 1.0 if action == InputActions.STEER_RIGHT else 0.0)
	var mirrored_frame: InputFrame = mirrored_provider.get_frame()
	assert_lt(mirrored_frame.steer, 0.0, "mirrored steer-right must invert to negative")
	assert_almost_eq(mirrored_frame.steer, -plain.steer, 0.0001)


func test_net_race_setup_never_sets_mirror_so_it_stays_false() -> void:
	var roster: Array = [{"driver": "aurora_vale", "kart": "medium", "peer": 1, "ready": true}]
	var config: RaceConfig = NetRaceSetup.build(roster, 2, 3, 42, "track_01")
	assert_false(config.mirror, "online races must never mirror")


func test_settings_default_mirror_is_false() -> void:
	assert_false(bool(SettingsManager.get_setting(&"gameplay", &"mirror", true)))


func _gp_config() -> RaceConfig:
	var config: RaceConfig = RaceConfig.new()
	config.kart_count = 1
	config.player_slot = 0
	config.player_kart = load("res://data/karts/medium.tres") as KartData
	config.ai_difficulty = load("res://data/ai/normal.tres") as AIDifficultyProfile
	return config


func _finished_entry(grid_slot: int) -> RaceResults.Entry:
	var entry: RaceResults.Entry = RaceResults.Entry.new()
	entry.grid_slot = grid_slot
	entry.rank = 1
	entry.total_time_seconds = 60.0
	return entry
