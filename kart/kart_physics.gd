class_name KartPhysics
extends Node

## Longitudinal/lateral scalar model, ground probing, and wall response for the
## kart's `CharacterBody3D`. Spec: KART_RACING_DEV_PROMPT.md §9.4-§9.8. Phase 1
## implements accel/brake/reverse/steer/grip/ground/slope/wall; slipstream,
## terrain friction, and kart-kart collision are Phase 2 (kept neutral here).

## Result of a single ground probe: whether enough rays hit a driveable
## surface, and the averaged surface normal of the hits that count.
class GroundProbe extends RefCounted:
	var grounded: bool = false
	var normal: Vector3 = Vector3.UP
	var hit_count: int = 0
	var center_distance: float = -1.0
	## Mean hit distance over every colliding ray; fallback when the center ray misses.
	var average_distance: float = -1.0


## Neutral terrain sample. TODO(phase-2): replace with `TerrainSensor` output
## (speed/grip/drag multipliers per surface type).
class TerrainSample extends RefCounted:
	var speed_mult: float = 1.0
	var grip_mult: float = 1.0
	var drag_mult: float = 1.0
	var terrain_id: StringName = &"asphalt"
	## TODO(phase-3): BoostController supplies this hook for boost-pad/item boosts.
	var ignores_offroad: bool = false


## Neutral drift result. TODO(phase-3): replace with `DriftController` output
## (drift direction, visual angle, grip override).
class DriftResult extends RefCounted:
	var is_drifting: bool = false
	var drift_dir: float = 0.0


## Neutral boost result. TODO(phase-3): replace with `BoostController` output
## (active speed/accel multipliers and offroad-ignore flag).
class BoostResult extends RefCounted:
	var speed_mult: float = 1.0
	var accel_mult: float = 1.0
	var ignores_offroad: bool = false


## Pure wall-collision response: speed retained and outward bounce fraction.
class WallResponse extends RefCounted:
	var speed_mult: float = 1.0
	var bounce_mult: float = 0.0

const CENTER_RAY_INDEX: int = 4

## Longitudinal scalar speed in the kart's forward direction (negative = reverse).
var speed: float = 0.0
## Lateral scalar speed in the kart's right direction (slip/slide component).
var lateral: float = 0.0
var grounded: bool = false
var ground_normal: Vector3 = Vector3.UP
var air_time: float = 0.0

var _body: CharacterBody3D
var _rays: Array[RayCast3D] = []
var _tuning: PhysicsTuning
var _kart_data: KartData
var _vertical_speed: float = 0.0
var _current_up: Vector3 = Vector3.UP
var _was_grounded: bool = true
var _wall_contact_active: bool = false

signal wall_head_on()


## Wires the physics component to its owning body, ground rays, and data.
func setup(body: CharacterBody3D, ground_rays: Array[RayCast3D], tuning: PhysicsTuning, kart_data: KartData) -> void:
	_body = body
	_rays = ground_rays
	_tuning = tuning
	_kart_data = kart_data
	_body.up_direction = Vector3.UP
	_body.floor_snap_length = tuning.floor_snap_length


## Casts the 5 ground rays and returns the averaged grounded state and normal.
## Surfaces steeper than `max_climb_angle_degrees` are excluded from the
## average and do not count toward `min_grounded_rays` (spec §9.7: treated as
## a wall rather than driveable ground).
func probe_ground() -> GroundProbe:
	var probe: GroundProbe = GroundProbe.new()
	var normal_sum: Vector3 = Vector3.ZERO
	var distance_sum: float = 0.0
	var max_climb_rad: float = deg_to_rad(_tuning.max_climb_angle_degrees)
	for index: int in _rays.size():
		var ray: RayCast3D = _rays[index]
		ray.force_raycast_update()
		if not ray.is_colliding():
			continue
		var normal: Vector3 = ray.get_collision_normal()
		if normal.angle_to(Vector3.UP) > max_climb_rad:
			continue
		probe.hit_count += 1
		normal_sum += normal
		var hit_distance: float = ray.global_position.distance_to(ray.get_collision_point())
		distance_sum += hit_distance
		if index == CENTER_RAY_INDEX:
			probe.center_distance = hit_distance
	probe.grounded = probe.hit_count >= _tuning.min_grounded_rays
	if probe.hit_count > 0:
		probe.average_distance = distance_sum / float(probe.hit_count)
	if probe.hit_count > 0 and normal_sum.length() > 0.001:
		probe.normal = normal_sum.normalized()
	grounded = probe.grounded
	ground_normal = probe.normal
	return probe


## Integrates one physics tick: longitudinal speed, steering/yaw, lateral
## slip, gravity/slope, hover/up alignment, `move_and_slide()`, and wall
## response post-processing. Spec §9.3 step 6 / §9.4-§9.8.
func integrate(
	input: InputFrame,
	terrain: TerrainSample,
	ground: GroundProbe,
	drift: DriftResult,
	boost: BoostResult,
	dt: float,
) -> void:
	var effective_grip: float = _tuning.grip * _kart_data.traction * terrain.grip_mult
	_integrate_longitudinal(input, terrain, boost, dt)
	var yaw_delta: float = _integrate_steering(input, ground, dt)
	lateral += speed * sin(yaw_delta)
	lateral *= exp(-effective_grip * dt)
	_integrate_vertical(ground, dt)
	_integrate_slope(ground, dt)
	_integrate_up_alignment(ground, dt)
	_apply_landing_loss(ground)
	_was_grounded = ground.grounded
	var forward: Vector3 = -_body.global_transform.basis.z
	var right: Vector3 = _body.global_transform.basis.x
	_body.velocity = forward * speed + right * lateral + Vector3.UP * _vertical_speed
	var incoming_velocity: Vector3 = _body.velocity
	_body.move_and_slide()
	_resolve_wall_collisions(dt, incoming_velocity)


func _effective_max_speed(terrain: TerrainSample, boost: BoostResult) -> float:
	return _kart_data.max_speed * terrain.speed_mult * boost.speed_mult


func _integrate_longitudinal(input: InputFrame, terrain: TerrainSample, boost: BoostResult, dt: float) -> void:
	var max_speed: float = _effective_max_speed(terrain, boost)
	if input.throttle > 0.0:
		var ratio: float = clampf(absf(speed) / maxf(max_speed, 0.001), 0.0, 1.0)
		var curve_mult: float = _tuning.accel_curve.sample(ratio) if _tuning.accel_curve != null else 1.0
		speed += _kart_data.acceleration * curve_mult * boost.accel_mult * input.throttle * dt
	elif input.brake > 0.0:
		if speed > 0.0:
			speed = maxf(0.0, speed - _tuning.brake_force * input.brake * dt)
		else:
			speed = maxf(-_tuning.reverse_max_speed, speed - _tuning.brake_force * input.brake * dt)
	else:
		speed = move_toward(speed, 0.0, _tuning.drag * terrain.drag_mult * dt)
	if speed > max_speed:
		speed = move_toward(speed, max_speed, _tuning.overspeed_decay * dt)


## Applies speed-based steering around the ground normal and returns the yaw
## delta actually applied this tick (used to derive lateral slip).
func _integrate_steering(input: InputFrame, ground: GroundProbe, dt: float) -> float:
	if absf(speed) < _tuning.min_steer_speed:
		return 0.0
	var speed_ratio: float = clampf(absf(speed) / maxf(_kart_data.max_speed, 0.001), 0.0, 1.0)
	var curve_mult: float = _tuning.steer_curve.sample(speed_ratio) if _tuning.steer_curve != null else 1.0
	var direction_sign: float = signf(speed)
	var yaw_rate: float = input.steer * _tuning.base_turn_rate * curve_mult * _kart_data.handling * direction_sign
	if not ground.grounded:
		yaw_rate *= _tuning.air_steer_factor
	var yaw_delta: float = yaw_rate * dt
	var axis: Vector3 = ground.normal if ground.grounded else Vector3.UP
	_body.rotate(axis, yaw_delta)
	return yaw_delta


func _integrate_vertical(ground: GroundProbe, dt: float) -> void:
	if ground.grounded:
		# Prefer the center ray; when it misses (crest, tilted landing) degrade to the mean of the hitting rays.
		var target_distance: float = ground.center_distance if ground.center_distance >= 0.0 else ground.average_distance
		var height_error: float = _tuning.hover_height - target_distance
		_vertical_speed = clampf(height_error * _tuning.hover_snap_speed, -_tuning.hover_snap_speed, _tuning.hover_snap_speed)
		air_time = 0.0
	else:
		_vertical_speed -= _tuning.gravity * dt
		air_time += dt


## Adds the gravity component tangential to the slope to `speed` so uphill
## sections decelerate and downhill sections accelerate (spec §9.7).
func _integrate_slope(ground: GroundProbe, dt: float) -> void:
	if not ground.grounded:
		return
	var gravity_vector: Vector3 = Vector3.DOWN * _tuning.gravity
	var slope_gravity: Vector3 = gravity_vector - ground.normal * ground.normal.dot(gravity_vector)
	var forward: Vector3 = -_body.global_transform.basis.z
	var along: float = slope_gravity.dot(forward)
	speed += along * _tuning.gravity_along_slope * dt


func _integrate_up_alignment(ground: GroundProbe, dt: float) -> void:
	var target_up: Vector3 = ground.normal if ground.grounded else Vector3.UP
	var rate: float = _tuning.up_align_speed_grounded if ground.grounded else _tuning.up_align_speed_airborne
	_current_up = _slerp_up_vector(_current_up, target_up, clampf(rate * dt, 0.0, 1.0))
	_body.up_direction = _current_up


## Spherical interpolation between two up-vector candidates that never feeds
## `Basis.set_axis_angle()` a degenerate axis, unlike `Vector3.slerp()` when
## the inputs are (near-)parallel or (near-)antiparallel — both routinely
## happen here (flat ground repeats the same normal every tick; a sharp
## slope-normal flip can momentarily face the opposite way).
static func _slerp_up_vector(from: Vector3, to: Vector3, weight: float) -> Vector3:
	var from_unit: Vector3 = from.normalized()
	var to_unit: Vector3 = to.normalized()
	var cos_angle: float = clampf(from_unit.dot(to_unit), -1.0, 1.0)
	if cos_angle > 0.9999:
		return from_unit
	if cos_angle < -0.9999:
		var nudged: Vector3 = from_unit.lerp(to_unit, weight)
		return nudged.normalized() if nudged.length() > 0.001 else to_unit
	var angle: float = acos(cos_angle) * weight
	var relative: Vector3 = (to_unit - from_unit * cos_angle).normalized()
	return from_unit * cos(angle) + relative * sin(angle)


## Reduces speed on the first tick a landing is detected, capped by
## `landing_speed_loss_cap` (spec §9.7).
## TODO(phase-2): landing alignment — remove part of `lateral` when the landing
## heading deviates from travel by more than `landing_align_threshold_degrees`.
func _apply_landing_loss(ground: GroundProbe) -> void:
	if _was_grounded or not ground.grounded:
		return
	var loss: float = clampf(absf(_vertical_speed) * _tuning.landing_speed_loss, 0.0, _tuning.landing_speed_loss_cap)
	speed *= (1.0 - loss)
	lateral = compute_landing_lateral(
		lateral, speed, _tuning.landing_align_threshold_degrees,
		_tuning.landing_lateral_retention,
	)


func _resolve_wall_collisions(dt: float, incoming_velocity: Vector3) -> void:
	var found_wall: bool = false
	for index: int in _body.get_slide_collision_count():
		var collision: KinematicCollision3D = _body.get_slide_collision(index)
		var normal: Vector3 = collision.get_normal()
		if absf(normal.dot(Vector3.UP)) >= _tuning.wall_normal_threshold:
			continue
		found_wall = true
		_body.global_position += normal * _tuning.wall_push_out * dt
		if _wall_contact_active:
			continue
		var travel_dir: Vector3 = incoming_velocity.normalized() if incoming_velocity.length() > 0.01 else -_body.global_transform.basis.z
		var incidence_degrees: float = rad_to_deg(asin(clampf(absf(travel_dir.dot(normal)), 0.0, 1.0)))
		var response: WallResponse = compute_wall_response(incidence_degrees, _tuning)
		speed *= response.speed_mult
		lateral *= response.speed_mult
		if response.bounce_mult > 0.0:
			_body.global_position += normal * response.bounce_mult * _tuning.wall_bounce_push
		if incidence_degrees >= _tuning.wall_head_on_angle_degrees:
			wall_head_on.emit()
	_wall_contact_active = found_wall


## Pure wall-incidence response (spec §9.8): graze below `wall_graze_angle_degrees`,
## head-on above `wall_head_on_angle_degrees`, linear interpolation between.
## Factored out of scene state so it is unit-testable on its own.
static func compute_wall_response(incidence_degrees: float, tuning: PhysicsTuning) -> WallResponse:
	var response: WallResponse = WallResponse.new()
	var graze: float = tuning.wall_graze_angle_degrees
	var head_on: float = tuning.wall_head_on_angle_degrees
	if incidence_degrees <= graze:
		response.speed_mult = tuning.wall_graze_loss
		response.bounce_mult = 0.0
	elif incidence_degrees >= head_on:
		response.speed_mult = tuning.wall_head_on_loss
		response.bounce_mult = tuning.wall_bounce
	else:
		var t: float = (incidence_degrees - graze) / (head_on - graze)
		response.speed_mult = lerpf(tuning.wall_graze_loss, tuning.wall_head_on_loss, t)
		response.bounce_mult = lerpf(0.0, tuning.wall_bounce, t)
	return response


## Pure landing correction: large travel/heading misalignment retains only a
## tunable fraction of lateral velocity; aligned landings keep their slide.
static func compute_landing_lateral(
	lateral_speed: float, forward_speed: float, threshold_degrees: float,
	retention: float,
) -> float:
	var angle_degrees: float = rad_to_deg(atan2(absf(lateral_speed), maxf(absf(forward_speed), 0.001)))
	if angle_degrees <= threshold_degrees:
		return lateral_speed
	return lateral_speed * clampf(retention, 0.0, 1.0)


## Adds a world-space arcade impulse to the local scalar velocity model.
func apply_world_delta_velocity(delta_velocity: Vector3) -> void:
	var forward: Vector3 = -_body.global_transform.basis.z
	var right: Vector3 = _body.global_transform.basis.x
	speed += delta_velocity.dot(forward)
	lateral += delta_velocity.dot(right)
	_vertical_speed += delta_velocity.y


## Applies a one-shot multiplier to forward and lateral motion.
func scale_speed(factor: float) -> void:
	speed *= factor
	lateral *= factor


## Caps forward speed against a fraction of the kart's base maximum.
func cap_speed(max_speed_factor: float) -> void:
	var cap: float = _kart_data.max_speed * max_speed_factor
	speed = clampf(speed, -cap, cap)


## Clears all local and CharacterBody velocity components for respawn.
func reset_motion() -> void:
	speed = 0.0
	lateral = 0.0
	_vertical_speed = 0.0
	air_time = 0.0
	_body.velocity = Vector3.ZERO


## Rebinds per-kart handling and mass data after sandbox swaps.
func set_kart_data(kart_data: KartData) -> void:
	_kart_data = kart_data
