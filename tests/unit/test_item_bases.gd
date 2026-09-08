extends GutTest

const PROJECTILE_PATH: String = "res://items/base/projectile_item.gd"
const HOMING_PATH: String = "res://items/base/homing_item.gd"
const TRAP_PATH: String = "res://items/base/trap_item.gd"
const AREA_PATH: String = "res://items/base/area_item.gd"
const LEADER_PATH: String = "res://items/base/leader_strike_item.gd"
const CONTEXT_PATH: String = "res://items/base/item_context.gd"
const KART_SCENE: PackedScene = preload("res://kart/kart.tscn")
const EPSILON: float = 0.001


func test_projectile_reflection_mirrors_velocity_across_wall_normal() -> void:
	var script: GDScript = _require_script(PROJECTILE_PATH)
	if script == null:
		return
	var reflected: Vector3 = script.call("reflect_velocity", Vector3(4.0, 0.0, -2.0), Vector3.LEFT) as Vector3
	assert_almost_eq(reflected.x, -4.0, EPSILON)
	assert_almost_eq(reflected.z, -2.0, EPSILON)


func test_projectile_bounce_budget_accepts_exactly_max_bounces() -> void:
	var script: GDScript = _require_script(PROJECTILE_PATH)
	if script == null:
		return
	assert_true(bool(script.call("can_reflect", 0, 3)))
	assert_true(bool(script.call("can_reflect", 2, 3)))
	assert_false(bool(script.call("can_reflect", 3, 3)))


func test_projectile_lifetime_expires_on_boundary() -> void:
	var script: GDScript = _require_script(PROJECTILE_PATH)
	if script == null:
		return
	assert_false(bool(script.call("lifetime_expired", 5.999, 6.0)))
	assert_true(bool(script.call("lifetime_expired", 6.0, 6.0)))


func test_homing_selects_the_next_kart_ahead_in_ranking() -> void:
	var script: GDScript = _require_script(HOMING_PATH)
	if script == null:
		return
	var leader: KartController = _make_kart("Leader")
	var owner: KartController = _make_kart("Owner")
	var trailer: KartController = _make_kart("Trailer")
	var ranking: Array[KartController] = [leader, owner, trailer]
	assert_same(script.call("select_target", owner, ranking), leader)


func test_homing_has_no_target_when_owner_is_rank_one() -> void:
	var script: GDScript = _require_script(HOMING_PATH)
	if script == null:
		return
	var owner: KartController = _make_kart("Leader")
	var trailer: KartController = _make_kart("Trailer")
	var ranking: Array[KartController] = [owner, trailer]
	assert_null(script.call("select_target", owner, ranking))


func test_trap_arms_only_after_half_second_delay() -> void:
	var script: GDScript = _require_script(TRAP_PATH)
	if script == null:
		return
	assert_false(bool(script.call("is_armed_after", 0.499, 0.5)))
	assert_true(bool(script.call("is_armed_after", 0.5, 0.5)))


func test_trap_owner_cap_rejects_the_third_active_trap() -> void:
	var script: GDScript = _require_script(TRAP_PATH)
	if script == null:
		return
	assert_true(bool(script.call("within_owner_cap", 1, 2)))
	assert_false(bool(script.call("within_owner_cap", 2, 2)))


func test_area_detonates_only_after_telegraph_boundary() -> void:
	var script: GDScript = _require_script(AREA_PATH)
	if script == null:
		return
	assert_false(bool(script.call("telegraph_complete", 0.299, 0.3)))
	assert_true(bool(script.call("telegraph_complete", 0.3, 0.3)))


func test_leader_strike_targets_rank_one_unless_it_is_the_owner() -> void:
	var script: GDScript = _require_script(LEADER_PATH)
	if script == null:
		return
	var leader: KartController = _make_kart("Leader")
	var owner: KartController = _make_kart("Owner")
	var ranking: Array[KartController] = [leader, owner]
	assert_same(script.call("select_target", owner, ranking), leader)
	assert_null(script.call("select_target", leader, ranking))


func test_leader_strike_is_unusable_from_rank_one() -> void:
	var script: GDScript = _require_script(LEADER_PATH)
	if script == null:
		return
	assert_false(bool(script.call("can_activate_from_rank", 1)))
	assert_true(bool(script.call("can_activate_from_rank", 2)))


func test_item_context_returns_defensive_kart_array_copy() -> void:
	var script: GDScript = _require_script(CONTEXT_PATH)
	if script == null:
		return
	var first: KartController = _make_kart("First")
	var karts: Array[KartController] = [first]
	var context: RefCounted = script.new() as RefCounted
	context.call("configure", karts, null, null, RandomNumberGenerator.new(), null)
	var received: Array[KartController] = context.call("get_karts") as Array[KartController]
	received.clear()
	assert_eq((context.call("get_karts") as Array[KartController]).size(), 1)


func _make_kart(kart_name: String) -> KartController:
	var kart: KartController = KART_SCENE.instantiate() as KartController
	kart.name = kart_name
	add_child_autofree(kart)
	return kart


func _require_script(path: String) -> GDScript:
	if ResourceLoader.exists(path):
		return load(path) as GDScript
	fail_test("Required item base script is missing: %s" % path)
	return null
