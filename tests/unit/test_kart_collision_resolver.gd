extends GutTest

## Contact-edge rule of KartCollisionResolver: a pair receives its impulses
## (normal split, side exchange, rear push, shield push) only on the tick it
## first touches, while separation keeps running every tick it overlaps.

const KART_SCENE: PackedScene = preload("res://kart/kart.tscn")
const PAIR_KEY: int = 1

class _CountingResolver extends KartCollisionResolver:
	var impulse_calls: int = 0
	var shield_push_calls: int = 0
	var separation_calls: int = 0

	func _apply_contact_impulse(kart_a: KartController, kart_b: KartController, normal: Vector3) -> void:
		impulse_calls += 1
		super(kart_a, kart_b, normal)

	func _apply_shield_contact_push(kart_a: KartController, kart_b: KartController, normal: Vector3) -> void:
		shield_push_calls += 1
		super(kart_a, kart_b, normal)

	func _apply_separation(kart_a: KartController, kart_b: KartController, normal: Vector3) -> void:
		separation_calls += 1
		super(kart_a, kart_b, normal)


var _resolver: _CountingResolver
var _kart_a: KartController
var _kart_b: KartController


func before_each() -> void:
	_resolver = _CountingResolver.new()
	add_child_autofree(_resolver)
	_resolver.set_physics_process(false)
	# Both karts face -Z; kart_b sits directly ahead so kart_a rams it from behind.
	_kart_a = _spawn_kart(Vector3.ZERO)
	_kart_b = _spawn_kart(Vector3(0.0, 0.0, -2.0))
	_resolver.register_kart(_kart_a)
	_resolver.register_kart(_kart_b)


func _spawn_kart(position: Vector3) -> KartController:
	var kart: KartController = KART_SCENE.instantiate() as KartController
	add_child_autofree(kart)
	kart.global_position = position
	return kart


func _overlapping() -> Dictionary[int, Array]:
	var pairs: Dictionary[int, Array] = {}
	pairs[PAIR_KEY] = [_kart_a, _kart_b]
	return pairs


func _separated() -> Dictionary[int, Array]:
	var pairs: Dictionary[int, Array] = {}
	return pairs


func test_three_consecutive_overlapping_ticks_apply_impulse_once_and_separation_thrice() -> void:
	for _tick: int in range(3):
		_resolver._resolve_contacts(_overlapping())
	assert_eq(_resolver.impulse_calls, 1, "impulse must fire only on the first contact tick")
	assert_eq(_resolver.shield_push_calls, 1, "shield push must fire only on the first contact tick")
	assert_eq(_resolver.separation_calls, 3, "separation must run on every overlapping tick")


func test_breaking_and_re_touching_contact_applies_a_second_impulse() -> void:
	_resolver._resolve_contacts(_overlapping())
	_resolver._resolve_contacts(_overlapping())
	_resolver._resolve_contacts(_separated())
	_resolver._resolve_contacts(_overlapping())
	_resolver._resolve_contacts(_overlapping())
	assert_eq(_resolver.impulse_calls, 2, "a new contact after separating must impulse again")
	assert_eq(_resolver.separation_calls, 4)


func test_rear_push_does_not_accumulate_while_bumpers_stay_in_contact() -> void:
	_kart_a.apply_impulse_arcade(Vector3(0.0, 0.0, -10.0), 0.0)
	_resolver._resolve_contacts(_overlapping())
	var pushed_speed: float = _kart_b.get_speed()
	assert_gt(pushed_speed, 0.0, "the rammed kart must be pushed on first contact")
	_resolver._resolve_contacts(_overlapping())
	_resolver._resolve_contacts(_overlapping())
	assert_almost_eq(_kart_b.get_speed(), pushed_speed, 0.0001, "sustained contact must not keep adding rear push")


func test_clear_karts_forgets_active_pairs_so_a_restart_contact_impulses_again() -> void:
	_resolver._resolve_contacts(_overlapping())
	_resolver.clear_karts()
	_resolver.register_kart(_kart_a)
	_resolver.register_kart(_kart_b)
	_resolver._resolve_contacts(_overlapping())
	assert_eq(_resolver.impulse_calls, 2)
