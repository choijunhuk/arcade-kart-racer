class_name RaceCamera
extends Camera3D

## Scene-independent Phase 8 chase camera. Reads only KartController APIs and
## EventBus presentation signals; never mutates gameplay state.

@export var tuning: FeelTuning = preload("res://data/tuning/camera_default.tres")

const MIN_LOOK_SPEED: float = 0.5
const LOOK_TARGET_HEIGHT: float = 1.0
const POSITION_EPSILON: float = 0.01

var _target: KartController
var _drift_offset: float = 0.0
var _look_back_blend: float = 0.0
var _shake: CameraShake = CameraShake.new()
var _fov_model: CameraFov = CameraFov.new()


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_shake.configure(tuning)
	_fov_model.configure(tuning)
	_connect_events()


func _exit_tree() -> void:
	_disconnect_events()


## Assigns the followed kart and snaps immediately to its unclipped chase pose.
func set_target(target: KartController) -> void:
	_target = target
	_drift_offset = 0.0
	_look_back_blend = 0.0
	_shake.clear()
	if _target == null:
		return
	global_position = _desired_position(_look_direction(), 1.0)
	_apply_look_rotation(Vector3.ZERO)


func _process(delta: float) -> void:
	if _target == null:
		return
	_update_look_back(delta)
	var look_direction: Vector3 = _look_direction().rotated(Vector3.UP, PI * _look_back_blend)
	var drift_weight: float = clampf(tuning.feedback_lerp_speed * delta, 0.0, 1.0)
	var desired: Vector3 = _resolve_clipping(_desired_position(look_direction, drift_weight))
	global_position = global_position.lerp(desired, clampf(tuning.follow_stiffness * delta, 0.0, 1.0))
	var sample: CameraShake.Sample = _shake.step(delta, SettingsManager.get_shake_strength())
	_apply_look_rotation(sample.rotation_offset)
	global_position += global_basis * sample.position_offset
	fov = _fov_model.step(
		_target.get_speed_ratio(), _target.is_boosting(), delta,
		SettingsManager.get_fov_effect_strength(),
	)


## Adds trauma through the bounded camera model for tests and local effects.
func add_trauma(amount: float) -> void:
	_shake.add_trauma(amount)


## Returns current trauma for the debug overlay and integration tests.
func get_trauma() -> float:
	return _shake.get_trauma()


func _desired_position(look_direction: Vector3, drift_weight: float) -> Vector3:
	var target_offset: float = -float(_target.get_drift_direction()) * tuning.drift_side_offset
	_drift_offset = lerpf(_drift_offset, target_offset, drift_weight)
	var right: Vector3 = look_direction.cross(Vector3.UP).normalized()
	return _target.global_position - look_direction * tuning.camera_distance + Vector3.UP * tuning.camera_height + right * _drift_offset


func _look_direction() -> Vector3:
	var body_forward: Vector3 = _target.get_forward()
	var velocity: Vector3 = _target.get_velocity()
	var flat_velocity: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	if flat_velocity.length() <= MIN_LOOK_SPEED:
		return body_forward
	var velocity_forward: Vector3 = flat_velocity.normalized()
	if _target.get_drift_state() == DriftController.DriftState.HOLD:
		return velocity_forward.slerp(body_forward, tuning.velocity_drift_blend).normalized()
	return velocity_forward


func _apply_look_rotation(shake_rotation: Vector3) -> void:
	var focus: Vector3 = _target.global_position + Vector3.UP * LOOK_TARGET_HEIGHT
	if focus.distance_to(global_position) <= POSITION_EPSILON:
		return
	look_at(focus, Vector3.UP)
	var drift_roll: float = deg_to_rad(
		-float(_target.get_drift_direction()) * tuning.drift_camera_roll_degrees,
	)
	rotate_object_local(Vector3.RIGHT, shake_rotation.x)
	rotate_object_local(Vector3.UP, shake_rotation.y)
	rotate_object_local(Vector3.BACK, drift_roll + shake_rotation.z)


func _update_look_back(delta: float) -> void:
	var target_blend: float = 1.0 if _target.get_input_frame_snapshot().look_back else 0.0
	var duration: float = maxf(tuning.look_back_blend_time, 0.001)
	_look_back_blend = move_toward(_look_back_blend, target_blend, maxf(delta, 0.0) / duration)


func _resolve_clipping(desired: Vector3) -> Vector3:
	if not is_inside_tree() or get_world_3d() == null:
		return desired
	var focus: Vector3 = _target.global_position + Vector3.UP * LOOK_TARGET_HEIGHT
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		focus, desired, tuning.camera_collision_mask, [_target.get_rid()],
	)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return desired
	return (hit["position"] as Vector3) + (hit["normal"] as Vector3) * tuning.camera_clip_margin


func _connect_events() -> void:
	if not EventBus.kart_hit.is_connected(_on_kart_hit):
		EventBus.kart_hit.connect(_on_kart_hit)
	if not EventBus.wall_head_on.is_connected(_on_wall_head_on):
		EventBus.wall_head_on.connect(_on_wall_head_on)
	if not EventBus.kart_landed.is_connected(_on_kart_landed):
		EventBus.kart_landed.connect(_on_kart_landed)
	if not EventBus.item_exploded.is_connected(_on_item_exploded):
		EventBus.item_exploded.connect(_on_item_exploded)


func _disconnect_events() -> void:
	if EventBus.kart_hit.is_connected(_on_kart_hit):
		EventBus.kart_hit.disconnect(_on_kart_hit)
	if EventBus.wall_head_on.is_connected(_on_wall_head_on):
		EventBus.wall_head_on.disconnect(_on_wall_head_on)
	if EventBus.kart_landed.is_connected(_on_kart_landed):
		EventBus.kart_landed.disconnect(_on_kart_landed)
	if EventBus.item_exploded.is_connected(_on_item_exploded):
		EventBus.item_exploded.disconnect(_on_item_exploded)


func _on_kart_hit(kart: Node, _hit_type: int) -> void:
	if kart == _target:
		_shake.add_trauma(tuning.kart_hit_trauma)


func _on_wall_head_on(kart: Node) -> void:
	if kart == _target:
		_shake.add_trauma(tuning.wall_head_on_trauma)


func _on_kart_landed(kart: Node, vertical_speed: float) -> void:
	if kart != _target:
		return
	_shake.add_trauma(landing_trauma(
		vertical_speed, tuning.landing_shake_min_speed, tuning.landing_shake_max_speed,
		tuning.landing_trauma_min, tuning.landing_trauma_max,
	))


func _on_item_exploded(world_position: Vector3) -> void:
	if _target == null:
		return
	var distance: float = _target.global_position.distance_to(world_position)
	_shake.add_trauma(explosion_trauma(
		distance, tuning.item_explosion_shake_radius, tuning.item_explosion_trauma,
	))


## Pure landing-speed mapping for the specified 0.2-0.5 trauma range.
static func landing_trauma(
	vertical_speed: float, minimum_speed: float, maximum_speed: float,
	minimum_trauma: float, maximum_trauma: float,
) -> float:
	var speed_range: float = maxf(maximum_speed - minimum_speed, 0.001)
	var weight: float = clampf((vertical_speed - minimum_speed) / speed_range, 0.0, 1.0)
	return lerpf(minimum_trauma, maximum_trauma, weight)


## Pure linear distance falloff for item explosion trauma.
static func explosion_trauma(distance: float, radius: float, maximum_trauma: float) -> float:
	var falloff: float = 1.0 - clampf(distance / maxf(radius, 0.001), 0.0, 1.0)
	return maxf(maximum_trauma, 0.0) * falloff
