class_name RaceCamera
extends Camera3D

## Phase 1 minimal spring-follow camera (spec §16). Follows behind the target
## kart, looks along its velocity direction (forward when slow), and applies
## speed-based FOV. No drift offset, shake, or look-back yet — Phase 3/8 scope.

@export var tuning: FeelTuning = preload("res://data/tuning/camera_default.tres")

const MIN_LOOK_SPEED: float = 0.5
const LOOK_TARGET_HEIGHT: float = 1.0

var _target: KartController


## Assigns the followed kart and snaps immediately so the camera does not
## fly in from its scene-authored starting position.
func set_target(target: KartController) -> void:
	_target = target
	if _target == null:
		return
	global_position = _desired_position()
	_look_at_target()


func _process(delta: float) -> void:
	if _target == null:
		return
	var desired: Vector3 = _desired_position()
	global_position = global_position.lerp(desired, clampf(tuning.follow_stiffness * delta, 0.0, 1.0))
	_look_at_target()
	var speed_ratio: float = _target.get_speed_ratio()
	fov = tuning.base_fov + tuning.speed_fov_add * speed_ratio * speed_ratio


func _desired_position() -> Vector3:
	var look_dir: Vector3 = _look_direction()
	return _target.global_position - look_dir * tuning.camera_distance + Vector3.UP * tuning.camera_height


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
