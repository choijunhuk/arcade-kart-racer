class_name KartVisuals
extends Node3D

## Purely presentational: body roll/pitch, wheel spin/steer, and a landing
## suspension bob. Reads only `KartController`'s public API and never mutates
## physics state (spec §17, coding rule 6: `_process` is presentation only).

const WHEEL_RADIUS: float = 0.28

@export var feel_tuning: FeelTuning = preload("res://data/tuning/feel_default.tres")

@onready var _controller: KartController = get_parent() as KartController
@onready var _body_mesh: Node3D = $Body
@onready var _wheel_fl: Node3D = $WheelFL
@onready var _wheel_fr: Node3D = $WheelFR
@onready var _wheel_rl: Node3D = $WheelRL
@onready var _wheel_rr: Node3D = $WheelRR

var _wheel_spin_radians: float = 0.0
var _was_grounded: bool = true
var _bob_offset: float = 0.0
var _bob_velocity: float = 0.0
var _base_local_y: float = 0.0
var _previous_speed: float = 0.0


func _ready() -> void:
	_base_local_y = position.y
	# Note: KartController's @onready fields are not initialized yet here
	# (children ready before their parent), so _previous_speed starts at 0
	# and self-corrects on the first _process() call.


func _process(delta: float) -> void:
	if _controller == null or delta <= 0.0:
		return
	var lateral_estimate: float = _estimate_lateral_speed()
	_update_body_roll_and_pitch(delta, lateral_estimate)
	_update_wheels(delta, lateral_estimate)
	_update_suspension_bob(delta)
	_update_hit_visual(delta)
	_previous_speed = _controller.get_speed()


## Approximates sideways slip from world velocity and heading since Phase 1's
## public API exposes velocity/forward but not the physics component's raw
## lateral scalar directly.
func _estimate_lateral_speed() -> float:
	var forward: Vector3 = _controller.get_forward()
	var right: Vector3 = forward.cross(Vector3.UP)
	if right.length() < 0.001:
		return 0.0
	right = right.normalized()
	return _controller.get_velocity().dot(right)


func _update_body_roll_and_pitch(delta: float, lateral_speed: float) -> void:
	var roll_degrees: float = clampf(
		-lateral_speed * feel_tuning.roll_per_lateral,
		-feel_tuning.maximum_body_roll_degrees,
		feel_tuning.maximum_body_roll_degrees,
	)
	var acceleration: float = (_controller.get_speed() - _previous_speed) / delta
	var pitch_degrees: float = 0.0
	if acceleration > 0.0:
		pitch_degrees = feel_tuning.acceleration_pitch_degrees
	elif acceleration < 0.0:
		pitch_degrees = -feel_tuning.braking_pitch_degrees
	_body_mesh.rotation = Vector3(deg_to_rad(pitch_degrees), 0.0, deg_to_rad(roll_degrees))


func _update_wheels(delta: float, lateral_speed: float) -> void:
	_wheel_spin_radians -= (_controller.get_speed() / WHEEL_RADIUS) * delta
	var steer_ratio: float = clampf(lateral_speed / maxf(_controller.get_kart_data().max_speed, 0.001), -1.0, 1.0)
	var steer_radians: float = deg_to_rad(steer_ratio * feel_tuning.maximum_wheel_steer_degrees)
	_wheel_fl.rotation = Vector3(_wheel_spin_radians, steer_radians, 0.0)
	_wheel_fr.rotation = Vector3(_wheel_spin_radians, steer_radians, 0.0)
	_wheel_rl.rotation = Vector3(_wheel_spin_radians, 0.0, 0.0)
	_wheel_rr.rotation = Vector3(_wheel_spin_radians, 0.0, 0.0)


func _update_suspension_bob(delta: float) -> void:
	var grounded: bool = _controller.is_grounded()
	if grounded and not _was_grounded:
		_bob_offset = -feel_tuning.suspension_bob_amplitude
	_was_grounded = grounded
	var acceleration: float = -feel_tuning.suspension_stiffness * _bob_offset - feel_tuning.suspension_damping * _bob_velocity
	_bob_velocity += acceleration * delta
	_bob_offset += _bob_velocity * delta
	position.y = _base_local_y + _bob_offset


func _update_hit_visual(_delta: float) -> void:
	var hit_state: int = _controller.get_hit_state()
	var progress: float = _controller.get_hit_progress()
	rotation = Vector3.ZERO
	scale = Vector3.ONE
	match hit_state:
		HitReactor.HitType.SPIN_OUT:
			rotation.y = TAU * progress
		HitReactor.HitType.TUMBLE:
			rotation.x = TAU * progress
		HitReactor.HitType.SQUASH:
			scale.y = _controller.tuning.hit_squash_visual_scale
