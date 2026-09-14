extends GutTest

## Pure aggregator tests for RaceTelemetryLog (Phase 18d-3): per-lap dict
## shape, drift release tier buckets, hit/recovery pairing across lap
## boundaries, the in-progress lap, and race totals.


func test_per_lap_dict_records_every_event_type() -> void:
	var log: RaceTelemetryLog = RaceTelemetryLog.new()

	log.drift_started()
	log.drift_ended(2)
	log.boost_started(&"mini_turbo_2")
	log.item_used()
	log.hit(1.0)
	log.recovered(2.5)
	log.wall_impact()
	log.respawn()
	log.lap_completed(1, 42.5)

	var laps: Array = log.to_dict()["laps"]
	assert_eq(laps.size(), 1)
	var lap: Dictionary = laps[0]
	assert_eq(int(lap["lap"]), 1)
	assert_eq(int(lap["drifts_started"]), 1)
	assert_eq(lap["drift_release_tiers"], {"2": 1})
	assert_eq(lap["boosts_by_source"], {"mini_turbo_2": 1})
	assert_eq(int(lap["items_used"]), 1)
	assert_eq(int(lap["hits"]), 1)
	assert_eq(lap["hit_recovery_seconds"], [1.5])
	assert_eq(int(lap["wall_impacts"]), 1)
	assert_eq(int(lap["respawns"]), 1)
	assert_almost_eq(float(lap["lap_time"]), 42.5, 0.001)


func test_drift_release_tier_distribution_buckets_0_to_3() -> void:
	var log: RaceTelemetryLog = RaceTelemetryLog.new()

	for tier: int in [0, 1, 2, 3, 1, 1]:
		log.drift_ended(tier)
	log.lap_completed(1, 10.0)

	var tiers: Dictionary = (log.to_dict()["laps"][0] as Dictionary)["drift_release_tiers"]
	assert_eq(tiers, {"0": 1, "1": 3, "2": 1, "3": 1})


func test_drift_ended_clamps_out_of_range_tiers_into_0_to_3() -> void:
	var log: RaceTelemetryLog = RaceTelemetryLog.new()

	log.drift_ended(-1)
	log.drift_ended(99)
	log.lap_completed(1, 10.0)

	var tiers: Dictionary = (log.to_dict()["laps"][0] as Dictionary)["drift_release_tiers"]
	assert_eq(tiers, {"0": 1, "3": 1})


func test_hit_recovery_seconds_computed_from_hit_and_recovered_times() -> void:
	var log: RaceTelemetryLog = RaceTelemetryLog.new()

	log.hit(1.0)
	log.recovered(3.5)
	log.hit(5.0)
	log.recovered(5.25)
	log.lap_completed(1, 10.0)

	var lap: Dictionary = log.to_dict()["laps"][0]
	assert_eq(int(lap["hits"]), 2)
	assert_eq(lap["hit_recovery_seconds"], [2.5, 0.25])


func test_recovered_without_a_pending_hit_is_ignored() -> void:
	var log: RaceTelemetryLog = RaceTelemetryLog.new()

	log.recovered(5.0)
	log.lap_completed(1, 10.0)

	var lap: Dictionary = log.to_dict()["laps"][0]
	assert_eq(int(lap["hits"]), 0)
	assert_eq((lap["hit_recovery_seconds"] as Array).size(), 0)


func test_lap_boundaries_attribute_hit_recovery_to_the_lap_the_hit_started_in() -> void:
	var log: RaceTelemetryLog = RaceTelemetryLog.new()

	log.hit(29.0)
	log.lap_completed(1, 30.0)
	log.recovered(30.4)
	log.lap_completed(2, 60.0)

	var laps: Array = log.to_dict()["laps"]
	assert_eq(laps.size(), 2)
	var lap1_recovery: Array = (laps[0] as Dictionary)["hit_recovery_seconds"]
	assert_eq(lap1_recovery.size(), 1, "recovery must land in the lap the hit started in")
	if lap1_recovery.size() == 1:
		assert_almost_eq(float(lap1_recovery[0]), 1.4, 0.0001)
	assert_eq((laps[1] as Dictionary)["hit_recovery_seconds"], [])
	assert_eq(int((laps[1] as Dictionary)["hits"]), 0)


func test_unfinished_current_lap_is_included_only_when_it_has_activity() -> void:
	var empty_log: RaceTelemetryLog = RaceTelemetryLog.new()
	assert_eq((empty_log.to_dict()["laps"] as Array).size(), 0, "an untouched in-progress lap must not appear")

	var active_log: RaceTelemetryLog = RaceTelemetryLog.new()
	active_log.drift_started()
	var laps: Array = active_log.to_dict()["laps"]
	assert_eq(laps.size(), 1)
	assert_null((laps[0] as Dictionary)["lap_time"], "an unfinished lap has no recorded lap_time yet")


func test_totals_sum_drifts_boosts_hits_and_lap_time_across_laps() -> void:
	var log: RaceTelemetryLog = RaceTelemetryLog.new()

	log.drift_started()
	log.drift_ended(1)
	log.boost_started(&"mini_turbo_1")
	log.wall_impact()
	log.lap_completed(1, 30.0)

	log.drift_started()
	log.drift_ended(1)
	log.boost_started(&"mini_turbo_1")
	log.hit(0.0)
	log.recovered(1.0)
	log.respawn()
	log.lap_completed(2, 28.0)

	var totals: Dictionary = log.to_dict()["totals"]
	assert_eq(int(totals["laps_completed"]), 2)
	assert_eq(int(totals["drifts_started"]), 2)
	assert_eq(totals["drift_release_tiers"], {"1": 2})
	assert_eq(totals["boosts_by_source"], {"mini_turbo_1": 2})
	assert_eq(int(totals["hits"]), 1)
	assert_eq(totals["hit_recovery_seconds"], [1.0])
	assert_eq(int(totals["wall_impacts"]), 1)
	assert_eq(int(totals["respawns"]), 1)
	assert_almost_eq(float(totals["race_time"]), 58.0, 0.001)


func test_boost_started_with_empty_source_is_grouped_as_unknown() -> void:
	var log: RaceTelemetryLog = RaceTelemetryLog.new()

	log.boost_started(&"")
	log.lap_completed(1, 10.0)

	var sources: Dictionary = (log.to_dict()["laps"][0] as Dictionary)["boosts_by_source"]
	assert_eq(sources, {"unknown": 1})
