class_name RaceCamera
extends Camera3D

## Spring-follow camera (spec §16). Follows behind the target kart, looks
## along its velocity direction (forward when slow), applies speed-based and
## boost FOV, and offsets sideways opposite the active drift direction.
## Shake and look-back are still Phase 8 scope.

@export var tuning: FeelTuning = preload("res://data/tuning/camera_default.tres")

const MIN_LOOK_SPEED: float = 0.5
const LOOK_TARGET_HEIGHT: float = 1.0

var _target: KartController
var _drift_offset: float = 0.0
var _boost_fov: float = 0.0
var _boost_fov_velocity: float = 0.0


## Assigns the followed kart and snaps immediately so the camera does not
## fly in from its scene-authored starting position.
func set_target(target: KartController) -> void:
	_target = target
	if _target == null:
		return
	_target.boost_controller.boost_started.connect(_on_boost_started)
	_target.boost_controller.boost_ended.connect(_on_boost_ended)
	global_position = _desired_position()
	_look_at_target()


func _process(delta: float) -> void:
	if _target == null:
		return
	var desired: Vector3 = _desired_position()
	global_position = global_position.lerp(desired, clampf(tuning.follow_stiffness * delta, 0.0, 1.0))
	_look_at_target()
	var speed_ratio: float = _target.get_speed_ratio()
	_update_boost_fov_spring(delta)
	fov = tuning.base_fov + tuning.speed_fov_add * speed_ratio * speed_ratio + _boost_fov


func _desired_position() -> Vector3:
	var look_dir: Vector3 = _look_direction()
	var target_offset: float = -float(_target.get_drift_direction()) * tuning.drift_side_offset
	_drift_offset = lerpf(_drift_offset, target_offset, 0.15)
	var right: Vector3 = look_dir.cross(Vector3.UP).normalized()
	return _target.global_position - look_dir * tuning.camera_distance + Vector3.UP * tuning.camera_height + right * _drift_offset


func _look_direction() -> Vector3:
	var velocity: Vector3 = _target.get_velocity()
	var flat_velocity: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	if flat_velocity.length() > MIN_LOOK_SPEED:
		return flat_velocity.normalized()
	return _target.get_forward()


func _look_at_target() -> void:
	var focus: Vector3 = _target.global_position + Vector3.UP * LOOK_TARGET_HEIGHT
	if focus.distance_to(global_position) < 0.01:
		return
	look_at(focus, Vector3.UP)


func _update_boost_fov_spring(delta: float) -> void:
	var target: float = tuning.boost_fov_add if _target.is_boosting() else 0.0
	var acceleration: float = (target - _boost_fov) * tuning.boost_fov_spring_stiffness
	acceleration -= _boost_fov_velocity * tuning.boost_fov_spring_damping
	_boost_fov_velocity += acceleration * delta
	_boost_fov += _boost_fov_velocity * delta


func _on_boost_started(_spec: BoostSpecData) -> void:
	pass


func _on_boost_ended() -> void:
	pass
