extends GutTest

const ROULETTE_PATH: String = "res://items/item_roulette.gd"
const EPSILON: float = 0.001


func test_roulette_script_exists() -> void:
	assert_true(ResourceLoader.exists(ROULETTE_PATH))


func test_result_is_fixed_as_soon_as_roulette_starts() -> void:
	var roulette: RefCounted = _make_roulette()
	if roulette == null:
		return
	var item: ItemData = preload("res://data/items/rocket_dart.tres")
	roulette.call("start", item)
	assert_same(roulette.call("get_result"), item)
	assert_true(bool(roulette.call("is_active")))


func test_roulette_finishes_after_exactly_one_point_two_seconds() -> void:
	var roulette: RefCounted = _make_roulette()
	if roulette == null:
		return
	roulette.call("start", preload("res://data/items/nitro_can.tres"))
	assert_false(bool(roulette.call("tick", 1.199)))
	assert_true(bool(roulette.call("tick", 0.001)))
	assert_false(bool(roulette.call("is_active")))


func _make_roulette() -> RefCounted:
	if not ResourceLoader.exists(ROULETTE_PATH):
		fail_test("ItemRoulette script is missing")
		return null
	return (load(ROULETTE_PATH) as GDScript).new() as RefCounted
