extends GutTest

const MANAGER_PATH: String = "res://items/item_manager.gd"
const KART_SCENE: PackedScene = preload("res://kart/kart.tscn")
const ITEM_PATHS: Array[String] = [
	"res://data/items/rocket_dart.tres",
	"res://data/items/hunter_drone.tres",
	"res://data/items/spike_mine.tres",
	"res://data/items/nitro_can.tres",
	"res://data/items/aegis_bubble.tres",
	"res://data/items/pulse_blast.tres",
	"res://data/items/storm_beacon.tres",
]


func test_manager_script_exists() -> void:
	assert_true(ResourceLoader.exists(MANAGER_PATH))


func test_every_shipped_item_has_an_icon_and_concrete_item_scene() -> void:
	for path: String in ITEM_PATHS:
		var data: ItemData = load(path) as ItemData
		assert_true(data.icon != null, "%s must expose its HUD icon" % path)
		assert_true(data.scene != null, "%s must expose its pooled scene" % path)
		if data.scene != null:
			var instance: Node = data.scene.instantiate()
			assert_true(instance is ItemBase, "%s scene must inherit ItemBase" % path)
			instance.free()


func test_item_box_collection_decides_result_immediately_but_starts_roulette() -> void:
	var manager: Node = _make_manager()
	if manager == null:
		return
	var kart: KartController = _make_kart_with_slot("KartOne")
	manager.call("register_kart", kart)
	manager.call("collect_item_box", kart)
	var slot: ItemSlot = kart.get_node("ItemSlot") as ItemSlot
	assert_true(slot.roulette_active)
	assert_not_null(slot.call("get_roulette_result"))
	assert_false(slot.has_item())


func test_use_starts_cooldown_and_rejects_reuse_until_it_expires() -> void:
	var manager: Node = _make_manager()
	if manager == null:
		return
	var kart: KartController = _make_kart_with_slot("KartOne")
	manager.call("register_kart", kart)
	var item: ItemData = preload("res://data/items/nitro_can.tres")
	manager.call("give_item", kart, item)
	assert_true(bool(manager.call("use_item", kart, InputFrame.new())))
	manager.call("give_item", kart, item)
	assert_false(bool(manager.call("use_item", kart, InputFrame.new())))
	manager.call("_physics_process", item.cooldown)
	assert_true(bool(manager.call("use_item", kart, InputFrame.new())))


func test_projectile_cap_rejects_new_use_and_preserves_the_slot() -> void:
	var manager: Node = _make_manager()
	if manager == null:
		return
	manager.set("max_active_projectiles", 1)
	var first: KartController = _make_kart_with_slot("First")
	var second: KartController = _make_kart_with_slot("Second")
	manager.call("register_kart", first)
	manager.call("register_kart", second)
	var dart: ItemData = preload("res://data/items/rocket_dart.tres")
	manager.call("give_item", first, dart)
	manager.call("give_item", second, dart)
	assert_true(bool(manager.call("use_item", first, InputFrame.new())))
	assert_false(bool(manager.call("use_item", second, InputFrame.new())))
	assert_true((second.get_node("ItemSlot") as ItemSlot).has_item())
	assert_eq(int(manager.call("get_active_projectile_count")), 1)


func test_finished_projectile_returns_to_its_pool_and_leaves_registry() -> void:
	var manager: Node = _make_manager()
	if manager == null:
		return
	var kart: KartController = _make_kart_with_slot("KartOne")
	manager.call("register_kart", kart)
	var dart: ItemData = preload("res://data/items/rocket_dart.tres")
	manager.call("give_item", kart, dart)
	assert_true(bool(manager.call("use_item", kart, InputFrame.new())))
	var active: Array = manager.call("get_active_projectiles") as Array
	assert_eq(active.size(), 1)
	(active[0] as ItemBase).expire()
	manager.call("_physics_process", 0.0)
	assert_eq(int(manager.call("get_active_projectile_count")), 0)
	assert_eq(int(manager.call("get_available_count_for", dart)), 1)


func _make_manager() -> Node:
	if not ResourceLoader.exists(MANAGER_PATH):
		fail_test("ItemManager script is missing")
		return null
	var manager: Node = (load(MANAGER_PATH) as GDScript).new() as Node
	add_child_autofree(manager)
	manager.call("setup", null, null, null, 99)
	return manager


func _make_kart_with_slot(kart_name: String) -> KartController:
	var kart: KartController = KART_SCENE.instantiate() as KartController
	kart.name = kart_name
	if kart.get_node_or_null("ItemSlot") == null:
		var slot: ItemSlot = ItemSlot.new()
		slot.name = "ItemSlot"
		kart.add_child(slot)
	add_child_autofree(kart)
	return kart
