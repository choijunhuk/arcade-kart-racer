extends GutTest

const HIT_REACTOR_PATH: String = "res://kart/hit_reactor.gd"
const EPSILON: float = 0.001

var _tuning: PhysicsTuning
var _reactor: Node


func before_each() -> void:
	_tuning = load("res://data/tuning/physics_default.tres") as PhysicsTuning
	if not ResourceLoader.exists(HIT_REACTOR_PATH):
		return
	var script: GDScript = load(HIT_REACTOR_PATH) as GDScript
	_reactor = script.new() as Node
	add_child_autofree(_reactor)
	_reactor.call("setup", null, null, _tuning)


func test_hit_reactor_script_exists() -> void:
	assert_true(ResourceLoader.exists(HIT_REACTOR_PATH))


func test_spin_out_uses_configured_duration_and_speed_factor() -> void:
	if _reactor == null:
		return
	var accepted: bool = bool(_reactor.call("apply", 1, null))

	assert_true(accepted)
	assert_almost_eq(float(_reactor.call("get_remaining_time")), _tuning.hit_spin_out_duration, EPSILON)
	assert_almost_eq(float(_reactor.call("get_speed_factor")), _tuning.hit_spin_out_speed_factor, EPSILON)


func test_tumble_and_squash_use_distinct_configured_durations() -> void:
	if _reactor == null:
		return
	_reactor.call("apply", 2, null)
	var tumble_duration: float = float(_reactor.call("get_remaining_time"))
	_reactor.call("clear")
	_reactor.call("apply", 3, null)
	var squash_duration: float = float(_reactor.call("get_remaining_time"))

	assert_almost_eq(tumble_duration, _tuning.hit_tumble_duration, EPSILON)
	assert_almost_eq(squash_duration, _tuning.hit_squash_duration, EPSILON)
	assert_gt(squash_duration, tumble_duration)


func test_second_hit_is_rejected_while_invulnerable() -> void:
	if _reactor == null:
		return
	assert_true(bool(_reactor.call("apply", 0, null)))
	assert_false(bool(_reactor.call("apply", 1, null)))


func test_hit_recovers_but_invulnerability_continues() -> void:
	if _reactor == null:
		return
	_reactor.call("apply", 0, null)
	_reactor.call("tick", _tuning.hit_bump_duration)

	assert_false(bool(_reactor.call("is_active")))
	assert_true(bool(_reactor.call("is_invulnerable")))


func test_new_hit_is_accepted_after_invulnerability_expires() -> void:
	if _reactor == null:
		return
	_reactor.call("apply", 0, null)
	_reactor.call("tick", _tuning.hit_invulnerability_duration)

	assert_true(bool(_reactor.call("apply", 1, null)))


func test_hit_types_expose_bump_weaken_spin_off_and_squash_control() -> void:
	if _reactor == null:
		return
	_reactor.call("apply", 0, null)
	assert_almost_eq(float(_reactor.call("get_control_factor")), _tuning.hit_bump_control_factor, EPSILON)
	_reactor.call("clear")
	_reactor.call("apply", 1, null)
	assert_almost_eq(float(_reactor.call("get_control_factor")), 0.0, EPSILON)
	_reactor.call("clear")
	_reactor.call("apply", 3, null)
	assert_almost_eq(float(_reactor.call("get_control_factor")), 1.0, EPSILON)
