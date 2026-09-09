extends GutTest

const ITEM_TABLE_PATH: String = "res://items/item_table.gd"
const DEFAULT_TABLE: ItemTableData = preload("res://data/item_tables/default_8_karts.tres")
const EPSILON: float = 0.001


func test_item_table_script_exists() -> void:
	assert_true(ResourceLoader.exists(ITEM_TABLE_PATH))


func test_rank_normalization_maps_first_and_last_for_four_karts() -> void:
	var script: GDScript = _require_script()
	if script == null:
		return
	assert_almost_eq(float(script.call("normalize_rank", 1, 4)), 0.0, EPSILON)
	assert_almost_eq(float(script.call("normalize_rank", 4, 4)), 1.0, EPSILON)


func test_rank_normalization_maps_middle_for_six_karts() -> void:
	var script: GDScript = _require_script()
	if script == null:
		return
	assert_almost_eq(float(script.call("normalize_rank", 4, 6)), 0.6, EPSILON)


func test_rank_normalization_maps_middle_for_twelve_karts() -> void:
	var script: GDScript = _require_script()
	if script == null:
		return
	assert_almost_eq(float(script.call("normalize_rank", 7, 12)), 6.0 / 11.0, EPSILON)


func test_interpolated_weights_match_first_row_at_leading_rank() -> void:
	var weights: PackedFloat32Array = _weights(0.0, &"")
	if weights.is_empty():
		return
	assert_almost_eq(weights[0], 10.0, EPSILON)
	assert_almost_eq(weights[2], 25.0, EPSILON)
	assert_almost_eq(weights[4], 45.0, EPSILON)


func test_interpolated_weights_lerp_between_neighbor_rows() -> void:
	var weights: PackedFloat32Array = _weights(0.5 / 7.0, &"")
	if weights.is_empty():
		return
	assert_almost_eq(weights[0], 15.0, EPSILON)
	assert_almost_eq(weights[1], 2.5, EPSILON)
	assert_almost_eq(weights[4], 37.5, EPSILON)


func test_previous_item_weight_is_halved_after_interpolation() -> void:
	var weights: PackedFloat32Array = _weights(0.0, &"aegis_bubble")
	if weights.is_empty():
		return
	assert_almost_eq(weights[4], 22.5, EPSILON)
	assert_almost_eq(weights[2], 25.0, EPSILON)


func test_pick_is_repeatable_for_the_same_seed() -> void:
	var script: GDScript = _require_script()
	if script == null:
		return
	var first_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var second_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	first_rng.seed = 713
	second_rng.seed = 713
	var first: StringName = StringName(script.call("pick", DEFAULT_TABLE, 0.75, &"", first_rng))
	var second: StringName = StringName(script.call("pick", DEFAULT_TABLE, 0.75, &"", second_rng))
	assert_eq(first, second)
	assert_true(DEFAULT_TABLE.item_ids.has(first))


func _weights(rank_normalized: float, previous_id: StringName) -> PackedFloat32Array:
	var script: GDScript = _require_script()
	if script == null:
		return PackedFloat32Array()
	return script.call("interpolated_weights", DEFAULT_TABLE, rank_normalized, previous_id) as PackedFloat32Array


func _require_script() -> GDScript:
	if ResourceLoader.exists(ITEM_TABLE_PATH):
		return load(ITEM_TABLE_PATH) as GDScript
	fail_test("ItemTable script is missing")
	return null
