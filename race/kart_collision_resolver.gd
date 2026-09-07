class_name KartCollisionResolver
extends Node

## Resolves each overlapping BumpArea pair once per physics tick with a
## predictable mass-weighted arcade impulse. Kart contact never enters HIT.

class ImpulseResult extends RefCounted:
	var delta_velocity_a: Vector3 = Vector3.ZERO
	var delta_velocity_b: Vector3 = Vector3.ZERO


@export var tuning: PhysicsTuning = preload("res://data/tuning/physics_default.tres")

var _karts: Array[KartController] = []


func _physics_process(_delta: float) -> void:
	var resolved_pairs: Dictionary[int, bool] = {}
	for kart_a: KartController in _karts:
		if not is_instance_valid(kart_a):
			continue
		var bump_area: Area3D = kart_a.get_node_or_null("BumpArea") as Area3D
		if bump_area == null:
			continue
		for other_area: Area3D in bump_area.get_overlapping_areas():
			var kart_b: KartController = other_area.get_parent() as KartController
			if kart_b == null or kart_b == kart_a or not _karts.has(kart_b):
				continue
			var pair_key: int = _pair_key(kart_a.get_instance_id(), kart_b.get_instance_id())
			if resolved_pairs.has(pair_key):
				continue
			resolved_pairs[pair_key] = true
			_resolve_pair(kart_a, kart_b)


## Registers a kart for pair collection. Re-registering is idempotent.
func register_kart(kart: KartController) -> void:
	if not _karts.has(kart):
		_karts.append(kart)


## Stops resolving contacts for a kart.
func unregister_kart(kart: KartController) -> void:
	_karts.erase(kart)


## Pure normal impulse split. The kart receiving the larger opposing mass
## receives the larger velocity change, while separating pairs receive none.
static func compute_impulse(
	velocity_a: Vector3, velocity_b: Vector3, normal_a_to_b: Vector3,
	mass_a: float, mass_b: float, restitution: float,
) -> ImpulseResult:
	var result: ImpulseResult = ImpulseResult.new()
	var normal: Vector3 = normal_a_to_b.normalized()
	if normal.length() < 0.001:
		return result
	var closing_speed: float = (velocity_a - velocity_b).dot(normal)
	if closing_speed <= 0.0:
		return result
	var total_mass: float = maxf(mass_a + mass_b, 0.001)
	var impulse_speed: float = closing_speed * maxf(restitution, 0.0)
	result.delta_velocity_a = -normal * impulse_speed * (mass_b / total_mass)
	result.delta_velocity_b = normal * impulse_speed * (mass_a / total_mass)
	return result


func _resolve_pair(kart_a: KartController, kart_b: KartController) -> void:
	var offset: Vector3 = kart_b.global_position - kart_a.global_position
	offset.y = 0.0
	var normal: Vector3 = offset.normalized() if offset.length() > 0.001 else kart_a.get_forward()
	var result: ImpulseResult = compute_impulse(
		kart_a.velocity, kart_b.velocity, normal, kart_a.get_mass(),
		kart_b.get_mass(), tuning.kart_collision_restitution,
	)
	var yaw_a: float = 0.0
	var yaw_b: float = 0.0
	var forward_alignment: float = absf(kart_a.get_forward().dot(normal))
	if forward_alignment < tuning.kart_side_hit_threshold:
		var lateral_exchange: Vector3 = (kart_b.velocity - kart_a.velocity) * tuning.kart_side_lateral_exchange
		result.delta_velocity_a += lateral_exchange
		result.delta_velocity_b -= lateral_exchange
		var yaw_sign: float = signf(kart_a.get_forward().cross(normal).y)
		yaw_a = -yaw_sign * tuning.kart_side_yaw_nudge
		yaw_b = yaw_sign * tuning.kart_side_yaw_nudge
	elif kart_a.get_forward().dot(normal) > tuning.kart_side_hit_threshold:
		var rear_push: Vector3 = kart_a.get_forward() * maxf(kart_a.get_speed(), 0.0) * tuning.kart_rear_push_factor
		result.delta_velocity_b += rear_push
		result.delta_velocity_a -= rear_push * (kart_b.get_mass() / maxf(kart_a.get_mass(), 0.001))
	kart_a.apply_impulse_arcade(result.delta_velocity_a, yaw_a)
	kart_b.apply_impulse_arcade(result.delta_velocity_b, yaw_b)
	_apply_separation(kart_a, kart_b, normal)


func _apply_separation(kart_a: KartController, kart_b: KartController, normal: Vector3) -> void:
	var total_mass: float = maxf(kart_a.get_mass() + kart_b.get_mass(), 0.001)
	kart_a.global_position -= normal * tuning.separation_push * (kart_b.get_mass() / total_mass)
	kart_b.global_position += normal * tuning.separation_push * (kart_a.get_mass() / total_mass)


func _pair_key(id_a: int, id_b: int) -> int:
	var low: int = mini(id_a, id_b)
	var high: int = maxi(id_a, id_b)
	return hash("%d:%d" % [low, high])
