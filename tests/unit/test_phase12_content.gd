extends GutTest

const EXPECTED_KARTS: int = 6
const EXPECTED_DRIVERS: int = 8
const EXPECTED_TRACKS: int = 4
const EXPECTED_ITEMS: int = 9
const MAX_DRIVER_MOD: float = 0.05


func test_two_distinct_karts_per_weight_class() -> void:
	var counts: Array[int] = [0, 0, 0]
	var ids: Array[StringName] = []
	var colors: Array[Color] = []
	var resources: Array[Resource] = ResourceScanner.scan_tres("res://data/karts")
	assert_eq(resources.size(), EXPECTED_KARTS)
	for resource: Resource in resources:
		var kart: KartData = resource as KartData
		assert_not_null(kart)
		if kart == null:
			continue
		counts[kart.weight_class] += 1
		assert_false(ids.has(kart.id))
		assert_false(colors.has(kart.body_color))
		ids.append(kart.id)
		colors.append(kart.body_color)
	assert_eq(counts, [2, 2, 2])


func test_eight_small_driver_modifiers_and_voice_hooks() -> void:
	var resources: Array[Resource] = ResourceScanner.scan_tres("res://data/drivers")
	assert_eq(resources.size(), EXPECTED_DRIVERS)
	var voices: Array[StringName] = []
	for resource: Resource in resources:
		var driver: DriverData = resource as DriverData
		assert_false(driver.voice_set.is_empty())
		assert_false(voices.has(driver.voice_set))
		voices.append(driver.voice_set)
		for value: float in driver.stat_mods.values():
			assert_lte(absf(value), MAX_DRIVER_MOD)


func test_four_selectable_three_lap_tracks() -> void:
	var resources: Array[Resource] = ResourceScanner.scan_tres("res://data/tracks")
	assert_eq(resources.size(), EXPECTED_TRACKS)
	for resource: Resource in resources:
		var track: TrackData = resource as TrackData
		assert_eq(track.laps_default, 3)
		assert_not_null(track.scene)


func test_nine_items_and_all_probability_rows_sum_to_one_hundred() -> void:
	var table: ItemTableData = load("res://data/item_tables/default_8_karts.tres") as ItemTableData
	assert_eq(table.item_ids.size(), EXPECTED_ITEMS)
	assert_true(table.item_ids.has(&"triple_dart"))
	assert_true(table.item_ids.has(&"phantom_decoy"))
	for row: PackedFloat32Array in table.rows:
		assert_eq(row.size(), EXPECTED_ITEMS)
		var total: float = 0.0
		for weight: float in row:
			assert_gte(weight, 0.0)
			total += weight
		assert_almost_eq(total, 100.0, 0.001)
	for id: StringName in table.item_ids:
		var data: ItemData = load("res://data/items/%s.tres" % id) as ItemData
		assert_not_null(data.scene)
