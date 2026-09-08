class_name KartVisuals
extends Node3D

## Presentation-only body, wheel, suspension, trick, hit, and flash motion.

const WHEEL_RADIUS: float = 0.28
const MIN_BOB_SPEED_RATIO: float = 0.25
const BOB_NOISE_SEED: int = 3_141

@export var feel_tuning: FeelTuning = preload("res://data/tuning/feel_default.tres")

@onready var _controller: KartController = get_parent() as KartController
@onready var _body_mesh: MeshInstance3D = $Body
@onready var _driver_mesh: MeshInstance3D = $Driver
@onready var _wheel_fl: Node3D = $WheelFL
@onready var _wheel_fr: Node3D = $WheelFR
@onready var _wheel_rl: Node3D = $WheelRL
@onready var _wheel_rr: Node3D = $WheelRR

var _wheel_spin_radians: float = 0.0
var _wheel_jitter_phase: float = 0.0
var _was_grounded: bool = true
var _bob_phase: float = 0.0
var _bob_offset: float = 0.0
var _bob_velocity: float = 0.0
var _base_local_y: float = 0.0
var _rear_left_base: Vector3 = Vector3.ZERO
var _rear_right_base: Vector3 = Vector3.ZERO
var _drift_yaw: float = 0.0
var _trick_spin: float = 0.0
var _flash_material: ShaderMaterial
var _flash_segments_remaining: int = 0
var _flash_segment_remaining: float = 0.0
var _bob_noise: FastNoiseLite = FastNoiseLite.new()


func _ready() -> void:
	_base_local_y = position.y
	_rear_left_base = _wheel_rl.position
	_rear_right_base = _wheel_rr.position
	_bob_noise.seed = BOB_NOISE_SEED
	_bob_noise.frequency = 1.0
	_install_hit_flash_material()
	apply_driver_data(_controller.get_driver_data())
	if not EventBus.kart_hit.is_connected(_on_kart_hit):
		EventBus.kart_hit.connect(_on_kart_hit)


func _exit_tree() -> void:
	if EventBus.kart_hit.is_connected(_on_kart_hit):
		EventBus.kart_hit.disconnect(_on_kart_hit)


func _process(delta: float) -> void:
	if _controller == null or delta <= 0.0:
		return
	_update_body_pose(delta)
	_update_wheels(delta)
	_update_suspension(delta)
	_update_hit_visual()
	_update_trick_visual(delta)
	_update_hit_flash(delta)


## Applies the selected driver's color to the placeholder capsule mesh.
func apply_driver_data(driver: DriverData) -> void:
	if driver == null:
		return
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = driver.driver_color
	material.roughness = 0.75
	_driver_mesh.material_override = material


func _update_body_pose(delta: float) -> void:
	var lateral_roll: float = -_controller.get_lateral_speed() * feel_tuning.roll_per_lateral
	var steer_roll: float = -_controller.get_steer_input() * feel_tuning.body_roll_steer_degrees
	var roll_degrees: float = clampf(
		lateral_roll + steer_roll,
		-feel_tuning.maximum_body_roll_degrees,
		feel_tuning.maximum_body_roll_degrees,
	)
	var pitch_degrees: float = (
		_controller.get_throttle_input() * feel_tuning.acceleration_pitch_degrees
		- _controller.get_brake_input() * feel_tuning.braking_pitch_degrees
	)
	var target_yaw: float = deg_to_rad(_controller.get_drift_visual_angle_degrees())
	var weight: float = clampf(feel_tuning.feedback_lerp_speed * delta, 0.0, 1.0)
	_drift_yaw = lerpf(_drift_yaw, target_yaw, weight)
	_body_mesh.rotation = Vector3(deg_to_rad(pitch_degrees), _drift_yaw, deg_to_rad(roll_degrees))


func _update_wheels(delta: float) -> void:
	_wheel_spin_radians -= (_controller.get_speed() / WHEEL_RADIUS) * delta
	var steer_radians: float = deg_to_rad(
		_controller.get_steer_input() * feel_tuning.maximum_wheel_steer_degrees,
	)
	_wheel_fl.rotation = Vector3(_wheel_spin_radians, steer_radians, 0.0)
	_wheel_fr.rotation = Vector3(_wheel_spin_radians, steer_radians, 0.0)
	_wheel_rl.rotation = Vector3(_wheel_spin_radians, 0.0, 0.0)
	_wheel_rr.rotation = Vector3(_wheel_spin_radians, 0.0, 0.0)
	_wheel_jitter_phase += feel_tuning.drift_wheel_jitter_frequency * delta
	var jitter: float = 0.0
	if _controller.get_drift_state() == DriftController.DriftState.HOLD:
		jitter = sin(_wheel_jitter_phase) * feel_tuning.drift_wheel_jitter
	_wheel_rl.position = _rear_left_base + Vector3(jitter, 0.0, 0.0)
	_wheel_rr.position = _rear_right_base - Vector3(jitter, 0.0, 0.0)


func _update_suspension(delta: float) -> void:
	var grounded: bool = _controller.is_grounded()
	if grounded and not _was_grounded:
		_bob_velocity -= _controller.get_last_landing_speed() * feel_tuning.landing_bob_velocity_scale
	_was_grounded = grounded
	var speed_scale: float = lerpf(MIN_BOB_SPEED_RATIO, 1.0, _controller.get_speed_ratio())
	_bob_phase += feel_tuning.suspension_bob_frequency * speed_scale * delta
	var road_noise: float = _bob_noise.get_noise_1d(_bob_phase) * feel_tuning.suspension_bob_amplitude if grounded else 0.0
	var acceleration: float = (
		(road_noise - _bob_offset) * feel_tuning.suspension_stiffness
		- _bob_velocity * feel_tuning.suspension_damping
	)
	_bob_velocity += acceleration * delta
	_bob_offset += _bob_velocity * delta
	position.y = _base_local_y + _bob_offset


func _update_hit_visual() -> void:
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
			scale = Vector3(
				feel_tuning.squash_horizontal_scale,
				feel_tuning.squash_vertical_scale,
				feel_tuning.squash_horizontal_scale,
			)


func _update_trick_visual(delta: float) -> void:
	if _controller.get_hit_state() >= 0:
		return
	if _controller.is_trick_armed():
		_trick_spin = fposmod(_trick_spin + feel_tuning.trick_spin_speed * delta, TAU)
	else:
		_trick_spin = lerpf(
			_trick_spin, 0.0,
			clampf(feel_tuning.feedback_lerp_speed * delta, 0.0, 1.0),
		)
	rotation.y = _trick_spin


func _install_hit_flash_material() -> void:
	var shader: Shader = load("res://effects/hit_flash.gdshader") as Shader
	_flash_material = ShaderMaterial.new()
	_flash_material.shader = shader
	var source: StandardMaterial3D = _body_mesh.get_active_material(0) as StandardMaterial3D
	if source != null:
		_flash_material.set_shader_parameter("albedo_color", source.albedo_color)
		_flash_material.set_shader_parameter("metallic", source.metallic)
		_flash_material.set_shader_parameter("roughness", source.roughness)
	_body_mesh.material_override = _flash_material


func _on_kart_hit(kart: Node, _hit_type: int) -> void:
	if kart != _controller:
		return
	_flash_segments_remaining = feel_tuning.hit_flash_count * 2
	_flash_segment_remaining = feel_tuning.hit_flash_duration


func _update_hit_flash(delta: float) -> void:
	if _flash_material == null or _flash_segments_remaining <= 0:
		return
	_flash_segment_remaining -= delta
	while _flash_segment_remaining <= 0.0 and _flash_segments_remaining > 0:
		_flash_segments_remaining -= 1
		_flash_segment_remaining += feel_tuning.hit_flash_duration
	var strength: float = 1.0 if _flash_segments_remaining > 0 and _flash_segments_remaining % 2 == 0 else 0.0
	_flash_material.set_shader_parameter("flash_strength", strength)
