extends GutTest

## Phase 18e-1: speed class multipliers, composition order, and the forced-
## STANDARD paths (time trial, grand prix keys, online) stay covered here.

const FLOAT_EPSILON: float = 0.001


func test_speed_class_multipliers_match_spec() -> void:
	assert_almost_eq(SpeedClassStats.max_speed_multiplier(RaceConfig.SpeedClass.CRUISE), 0.85, FLOAT_EPSILON)
	assert_almost_eq(SpeedClassStats.acceleration_multiplier(RaceConfig.SpeedClass.CRUISE), 0.9, FLOAT_EPSILON)
	assert_almost_eq(SpeedClassStats.max_speed_multiplier(RaceConfig.SpeedClass.STANDARD), 1.0, FLOAT_EPSILON)
	assert_almost_eq(SpeedClassStats.acceleration_multiplier(RaceConfig.SpeedClass.STANDARD), 1.0, FLOAT_EPSILON)
	assert_almost_eq(SpeedClassStats.max_speed_multiplier(RaceConfig.SpeedClass.TURBO), 1.15, FLOAT_EPSILON)
	assert_almost_eq(SpeedClassStats.acceleration_multiplier(RaceConfig.SpeedClass.TURBO), 1.1, FLOAT_EPSILON)


func test_speed_class_apply_only_scales_speed_and_acceleration_leaving_kart_unmutated() -> void:
	var kart: KartData = KartData.new()
	kart.max_speed = 30.0
	kart.acceleration = 12.0
	kart.handling = 1.2
	kart.drift_factor = 0.9
	kart.drift_charge_mult = 1.1
	kart.boost_power = 1.3
	var scaled: KartData = SpeedClassStats.apply(kart, RaceConfig.SpeedClass.TURBO)
	assert_not_same(scaled, kart)
	assert_almost_eq(scaled.max_speed, 34.5, FLOAT_EPSILON)
	assert_almost_eq(scaled.acceleration, 13.2, FLOAT_EPSILON)
	assert_almost_eq(scaled.handling, 1.2, FLOAT_EPSILON, "handling must stay unchanged across classes")
	assert_almost_eq(scaled.drift_factor, 0.9, FLOAT_EPSILON, "drift charge must stay unchanged across classes")
	assert_almost_eq(scaled.boost_power, 1.3, FLOAT_EPSILON, "boost power must stay unchanged across classes")
	assert_almost_eq(kart.max_speed, 30.0, FLOAT_EPSILON, "original KartData must stay unmutated")


## Chains exactly what RaceManager._spawn_karts() does: RaceRoster.kart_for_slot()
## (the single place SpeedClassStats applies the class multiplier) feeding
## RaceConfigBuilder.apply_driver_mods() with 2 args. Guards against the class
## multiplier ever being reapplied inside apply_driver_mods() and double-counted.
func test_race_manager_chain_applies_class_multiplier_exactly_once_turbo() -> void:
	var roster: RaceRoster = RaceRoster.new()
	var config: RaceConfig = RaceConfig.new()
	config.speed_class = RaceConfig.SpeedClass.TURBO
	var base_kart: KartData = KartData.new()
	base_kart.max_speed = 20.0
	config.kart_roster = [base_kart]
	config.player_kart = base_kart
	var driver: DriverData = DriverData.new()
	driver.stat_mods = {&"max_speed": 0.05}
	var kart_for_slot: KartData = roster.kart_for_slot(config, 0, null)
	var modified: KartData = RaceConfigBuilder.apply_driver_mods(kart_for_slot, driver)
	assert_almost_eq(modified.max_speed, 20.0 * 1.15 * 1.05, FLOAT_EPSILON)


func test_race_manager_chain_applies_class_multiplier_exactly_once_cruise() -> void:
	var roster: RaceRoster = RaceRoster.new()
	var config: RaceConfig = RaceConfig.new()
	config.speed_class = RaceConfig.SpeedClass.CRUISE
	var base_kart: KartData = KartData.new()
	base_kart.max_speed = 20.0
	config.kart_roster = [base_kart]
	config.player_kart = base_kart
	var driver: DriverData = DriverData.new()
	driver.stat_mods = {&"max_speed": 0.05}
	var kart_for_slot: KartData = roster.kart_for_slot(config, 0, null)
	var modified: KartData = RaceConfigBuilder.apply_driver_mods(kart_for_slot, driver)
	assert_almost_eq(modified.max_speed, 20.0 * 0.85 * 1.05, FLOAT_EPSILON)


func test_race_manager_chain_leaves_max_speed_unscaled_by_class_standard() -> void:
	var roster: RaceRoster = RaceRoster.new()
	var config: RaceConfig = RaceConfig.new()
	config.speed_class = RaceConfig.SpeedClass.STANDARD
	var base_kart: KartData = KartData.new()
	base_kart.max_speed = 20.0
	config.kart_roster = [base_kart]
	config.player_kart = base_kart
	var driver: DriverData = DriverData.new()
	driver.stat_mods = {&"max_speed": 0.05}
	var kart_for_slot: KartData = roster.kart_for_slot(config, 0, null)
	var modified: KartData = RaceConfigBuilder.apply_driver_mods(kart_for_slot, driver)
	assert_almost_eq(modified.max_speed, 20.0 * 1.05, FLOAT_EPSILON)


func test_apply_driver_mods_defaults_to_standard_matching_prior_behavior() -> void:
	var kart: KartData = KartData.new()
	kart.max_speed = 28.0
	var driver: DriverData = DriverData.new()
	driver.stat_mods = {&"max_speed": 0.05}
	var modified: KartData = RaceConfigBuilder.apply_driver_mods(kart, driver)
	assert_almost_eq(modified.max_speed, 29.4, FLOAT_EPSILON)


func test_kart_for_slot_scales_the_roster_without_mutating_shared_resources() -> void:
	var roster: RaceRoster = RaceRoster.new()
	var config: RaceConfig = RaceConfig.new()
	config.speed_class = RaceConfig.SpeedClass.TURBO
	var shared_kart: KartData = load("res://data/karts/medium.tres") as KartData
	var original_speed: float = shared_kart.max_speed
	config.kart_roster = [shared_kart]
	config.player_kart = shared_kart
	var resolved: KartData = roster.kart_for_slot(config, 0, null)
	assert_almost_eq(resolved.max_speed, original_speed * 1.15, FLOAT_EPSILON)
	assert_almost_eq(shared_kart.max_speed, original_speed, FLOAT_EPSILON, "shared .tres resource must stay unmutated")


func test_normalize_forces_standard_speed_class_for_time_trial() -> void:
	var config: RaceConfig = RaceConfig.new()
	config.race_mode = RaceConfig.RaceMode.TIME_TRIAL
	config.speed_class = RaceConfig.SpeedClass.TURBO
	config.track = TrackData.new()
	config.track.scene = load("res://track/tracks/test_loop/test_loop.tscn") as PackedScene
	RaceConfigBuilder.normalize(config)
	assert_eq(config.speed_class, RaceConfig.SpeedClass.STANDARD)


func test_grand_prix_record_key_keeps_standard_and_suffixes_other_classes() -> void:
	var config: RaceConfig = _gp_config()
	var track: TrackData = TrackData.new()
	track.id = &"t"
	var standard: GrandPrix = GrandPrix.new()
	standard.setup(config, [track])
	assert_eq(standard.record_key(), &"horizon_cup/normal", "STANDARD keeps the pre-18e key so old bests stay valid")

	config.speed_class = RaceConfig.SpeedClass.CRUISE
	var cruise: GrandPrix = GrandPrix.new()
	cruise.setup(config, [track])
	assert_eq(cruise.record_key(), &"horizon_cup_cruise/normal")

	config.speed_class = RaceConfig.SpeedClass.TURBO
	var turbo: GrandPrix = GrandPrix.new()
	turbo.setup(config, [track])
	assert_eq(turbo.record_key(), &"horizon_cup_turbo/normal")


func test_net_race_setup_never_sets_speed_class_so_it_stays_standard() -> void:
	var roster: Array = [{"driver": "aurora_vale", "kart": "medium", "peer": 1, "ready": true}]
	var config: RaceConfig = NetRaceSetup.build(roster, 2, 3, 42, "track_01")
	assert_eq(config.speed_class, RaceConfig.SpeedClass.STANDARD)


func _gp_config() -> RaceConfig:
	var config: RaceConfig = RaceConfig.new()
	config.kart_count = 1
	config.player_slot = 0
	config.player_kart = load("res://data/karts/medium.tres") as KartData
	config.ai_difficulty = load("res://data/ai/normal.tres") as AIDifficultyProfile
	return config
