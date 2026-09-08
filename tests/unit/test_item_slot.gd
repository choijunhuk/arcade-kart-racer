extends GutTest

const SLOT_PATH: String = "res://kart/item_slot.gd"


func test_slot_script_exists() -> void:
	assert_true(ResourceLoader.exists(SLOT_PATH))


func test_slot_exposes_item_identity_and_category() -> void:
	var slot: Node = _make_slot()
	if slot == null:
		return
	var item: ItemData = preload("res://data/items/rocket_dart.tres")
	slot.call("set_item", item)
	assert_true(bool(slot.call("has_item")))
	assert_eq(StringName(slot.call("get_item_id")), &"rocket_dart")
	assert_eq(int(slot.call("get_category")), ItemData.ItemCategory.PROJECTILE)


func test_clear_item_returns_the_held_resource_and_empties_slot() -> void:
	var slot: Node = _make_slot()
	if slot == null:
		return
	var item: ItemData = preload("res://data/items/nitro_can.tres")
	slot.call("set_item", item)
	assert_same(slot.call("clear_item"), item)
	assert_false(bool(slot.call("has_item")))


func test_item_edge_is_consumed_only_once_for_the_same_input_tick() -> void:
	var slot: Node = _make_slot()
	if slot == null:
		return
	slot.call("set_item", preload("res://data/items/spike_mine.tres"))
	var frame: InputFrame = InputFrame.new()
	frame.item = true
	frame.tick = 42
	slot.call("capture_input", frame)
	slot.call("capture_input", frame)
	assert_true(bool(slot.call("consume_use_request")))
	assert_false(bool(slot.call("consume_use_request")))


func test_roulette_keeps_slot_empty_until_reveal_finishes() -> void:
	var slot: Node = _make_slot()
	if slot == null:
		return
	slot.call("begin_roulette", preload("res://data/items/aegis_bubble.tres"))
	assert_true(bool(slot.get("roulette_active")))
	assert_false(bool(slot.call("has_item")))
	assert_false(bool(slot.call("tick_roulette", 1.0)))
	assert_true(bool(slot.call("tick_roulette", 0.2)))
	assert_true(bool(slot.call("has_item")))


func _make_slot() -> Node:
	if not ResourceLoader.exists(SLOT_PATH):
		fail_test("ItemSlot script is missing")
		return null
	var slot: Node = (load(SLOT_PATH) as GDScript).new() as Node
	add_child_autofree(slot)
	return slot
