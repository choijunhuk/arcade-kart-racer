extends GutTest

const GP_PATH: String = "res://race/grand_prix.gd"


func test_gp_points_are_fifteen_twelve_ten_eight_six_four_two_one() -> void:
	assert_true(ResourceLoader.exists(GP_PATH), "Phase 12 must implement the GP value model")
	if not ResourceLoader.exists(GP_PATH):
		return
	var script: Script = load(GP_PATH) as Script
	var expected: Array[int] = [15, 12, 10, 8, 6, 4, 2, 1]
	for index: int in range(expected.size()):
		assert_eq(int(script.call("points_for_position", index + 1)), expected[index])
	assert_eq(int(script.call("points_for_position", 0)), 0)
	assert_eq(int(script.call("points_for_position", 9)), 0)


func test_gp_orders_points_then_best_finish() -> void:
	var gp: GrandPrix = _cup(2)
	assert_true(gp.record_results(0, _entries([0, 1, 2])))
	assert_true(gp.advance())
	assert_true(gp.record_results(1, _entries([2, 1, 0])))
	var standings: Array[GrandPrix.Standing] = gp.standings()
	assert_eq(standings[0].slot, 0, "25 points beats 24; equal best finish uses stable slot")
	assert_eq(standings[1].slot, 2)
	assert_eq(standings[2].points, 24)
	assert_true(gp.is_complete())


func test_equal_points_prefer_the_better_best_finish() -> void:
	var gp: GrandPrix = _cup(3, 4)
	gp.record_results(0, _entries([0, 1, 2, 3]))
	gp.advance()
	gp.record_results(1, _entries([2, 3, 1, 0]))
	gp.advance()
	gp.record_results(2, _entries([2, 3, 1, 0]))
	var standings: Array[GrandPrix.Standing] = gp.standings()
	# Slot 0: 15+8+8=31, slot 1: 12+10+10=32 (the score ordering is primary).
	assert_lt(_rank(standings, 1), _rank(standings, 0))
	var a: GrandPrix.Standing = GrandPrix.Standing.new()
	var b: GrandPrix.Standing = GrandPrix.Standing.new()
	a.points = 24
	a.best_finish = 1
	a.finishes = [1, 5]
	b.points = 24
	b.best_finish = 2
	b.finishes = [2, 2]
	assert_true(GrandPrix._ahead(a, b), "best finish resolves a points tie")


func test_duplicate_and_out_of_order_rounds_do_not_award_points() -> void:
	var gp: GrandPrix = _cup(2)
	assert_false(gp.advance())
	assert_false(gp.record_results(1, _entries([0, 1, 2])))
	assert_true(gp.record_results(0, _entries([0, 1, 2])))
	assert_false(gp.record_results(0, _entries([0, 1, 2])))
	assert_eq(gp.standings()[0].points, 15)


func test_dnf_gets_zero_and_invalid_rosters_do_not_partially_apply() -> void:
	var gp: GrandPrix = _cup(1)
	var entries: Array[RaceResults.Entry] = _entries([0, 1, 2])
	entries[2].total_time_seconds = -1.0
	entries[1].grid_slot = 0
	assert_false(gp.record_results(0, entries))
	assert_eq(gp.standings()[0].points, 0)
	entries[1].grid_slot = 1
	assert_true(gp.record_results(0, entries))
	assert_eq(gp.standings().back().points, 0)


func test_seeded_roster_and_difficulty_remain_identical_across_tracks() -> void:
	var gp: GrandPrix = _cup(2)
	var same_seed: GrandPrix = _cup(2)
	var first: RaceConfig = gp.current_config()
	assert_eq(first.kart_roster, same_seed.current_config().kart_roster)
	assert_eq(first.driver_roster, same_seed.current_config().driver_roster)
	gp.record_results(0, _entries([0, 1, 2]))
	gp.advance()
	var second: RaceConfig = gp.current_config()
	assert_eq(first.kart_roster, second.kart_roster)
	assert_eq(first.driver_roster, second.driver_roster)
	assert_same(first.ai_difficulty, second.ai_difficulty)
	assert_ne(first.track.id, second.track.id)
	assert_eq(second.gp_round, 1)


func test_standings_are_defensive_copies() -> void:
	var gp: GrandPrix = _cup(1)
	gp.record_results(0, _entries([0, 1, 2]))
	var copy: Array[GrandPrix.Standing] = gp.standings()
	copy[0].points = 999
	copy[0].finishes.clear()
	assert_eq(gp.standings()[0].points, 15)
	assert_eq(gp.standings()[0].finishes, [1])


func _cup(rounds: int, count: int = 3) -> GrandPrix:
	var config: RaceConfig = RaceConfig.new()
	config.kart_count = count
	config.seed = 1204
	config.player_kart = load("res://data/karts/medium.tres") as KartData
	config.ai_difficulty = load("res://data/ai/hard.tres") as AIDifficultyProfile
	var sequence: Array[TrackData] = []
	for index: int in range(rounds):
		var track: TrackData = TrackData.new()
		track.id = StringName("test_%d" % index)
		sequence.append(track)
	var gp: GrandPrix = GrandPrix.new()
	gp.setup(config, sequence)
	return gp


func _entries(order: Array[int]) -> Array[RaceResults.Entry]:
	var entries: Array[RaceResults.Entry] = []
	for index: int in range(order.size()):
		var entry: RaceResults.Entry = RaceResults.Entry.new()
		entry.grid_slot = order[index]
		entry.rank = index + 1
		entry.total_time_seconds = 70.0 + float(index)
		entries.append(entry)
	return entries


func _rank(standings: Array[GrandPrix.Standing], slot: int) -> int:
	for index: int in range(standings.size()):
		if standings[index].slot == slot:
			return index
	return -1
