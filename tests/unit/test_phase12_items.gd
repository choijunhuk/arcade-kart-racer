extends GutTest

const EPSILON: float = 0.00001
const DART_DATA: ItemData = preload("res://data/items/triple_dart.tres")
const DECOY_DATA: ItemData = preload("res://data/items/phantom_decoy.tres")


func test_triple_spread_is_normalized_symmetric_and_has_a_straight_center() -> void:
	var directions: Array[Vector3] = TripleDart.spread_directions(Vector3.FORWARD, 12.0)
	assert_eq(directions.size(), 3)
	assert_almost_eq(directions[1].distance_to(Vector3.FORWARD), 0.0, EPSILON)
	assert_almost_eq(directions[0].x, -directions[2].x, EPSILON)
	for direction: Vector3 in directions:
		assert_almost_eq(direction.length(), 1.0, EPSILON)
	assert_almost_eq(rad_to_deg(directions[0].angle_to(directions[2])), 24.0, 0.001)


func test_rear_spread_reverses_all_three_directions() -> void:
	var front: Array[Vector3] = TripleDart.spread_directions(Vector3.FORWARD, 12.0)
	var rear: Array[Vector3] = TripleDart.spread_directions(Vector3.BACK, 12.0)
	for index: int in range(front.size()):
		assert_almost_eq(front[index].distance_to(-rear[index]), 0.0, EPSILON)


func test_decoy_only_spins_out_a_collector_after_arming() -> void:
	var owner_kart: KartController = _kart(Vector3.ZERO)
	var target: KartController = _kart(Vector3(0.0, 0.0, 2.0))
	var context: ItemContext = ItemContext.new()
	context.configure([owner_kart, target], null, null, null, null)
	var decoy: PhantomDecoy = DECOY_DATA.scene.instantiate() as PhantomDecoy
	add_child_autofree(decoy)
	decoy.setup(DECOY_DATA, owner_kart, context)
	decoy.activate(InputFrame.zero())
	decoy.tick(decoy.arm_delay - 0.01)
	assert_eq(target.get_hit_state(), -1)
	assert_false(decoy.is_expired())
	decoy.tick(0.02)
	assert_eq(target.get_hit_state(), int(HitReactor.HitType.SPIN_OUT))
	assert_true(decoy.is_expired())
	assert_eq(owner_kart.get_hit_state(), -1)


func test_triple_darts_use_existing_manager_pool_and_release_all_registry_slots() -> void:
	var owner_kart: KartController = _kart(Vector3.ZERO)
	var manager: ItemManager = ItemManager.new()
	add_child_autofree(manager)
	manager.set_physics_process(false)
	manager.setup(null, null, null, 12)
	manager.register_kart(owner_kart)
	assert_true(manager.give_item(owner_kart, DART_DATA))
	assert_true(manager.use_item(owner_kart, InputFrame.zero()))
	assert_eq(manager.get_active_projectile_count(), 3)
	for projectile: ItemBase in manager.get_active_projectiles():
		assert_true(projectile is RocketDart)
		assert_eq(projectile.data.id, &"triple_dart")
	manager._physics_process(DART_DATA.lifetime + 0.01)
	assert_eq(manager.get_active_projectile_count(), 0)
	assert_eq(manager.get_available_count_for(DART_DATA), 1)
	assert_true(manager.give_item(owner_kart, DART_DATA))
	assert_true(manager.use_item(owner_kart, InputFrame.zero()))
	assert_eq(manager.get_active_projectile_count(), 3, "reused volley has exactly three live darts")
	manager.reset()
	assert_eq(manager.get_active_projectile_count(), 0)


func test_volley_cannot_exceed_the_existing_projectile_budget() -> void:
	var owner_kart: KartController = _kart(Vector3.ZERO)
	var manager: ItemManager = ItemManager.new()
	add_child_autofree(manager)
	manager.set_physics_process(false)
	manager.max_active_projectiles = 2
	manager.setup(null, null, null, 12)
	manager.register_kart(owner_kart)
	manager.give_item(owner_kart, DART_DATA)
	assert_false(manager.use_item(owner_kart, InputFrame.zero()))
	assert_true(owner_kart.item_slot.has_item())
	assert_eq(manager.get_active_projectile_count(), 0)


func _kart(position: Vector3) -> KartController:
	var kart: KartController = (load("res://kart/kart.tscn") as PackedScene).instantiate() as KartController
	add_child_autofree(kart)
	kart.global_position = position
	kart.set_physics_process(false)
	return kart
