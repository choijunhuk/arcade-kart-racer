class_name KartVisuals
extends Node3D

## Presentation-only body, wheel, suspension, trick, hit, and flash motion.

const WHEEL_RADIUS: float = 0.28
const MIN_BOB_SPEED_RATIO: float = 0.25
const BOB_NOISE_SEED: int = 3_141
## Kart meshes render on their own layer so contact-shadow decals skip them.
const KART_RENDER_LAYER: int = 1 << 1
const CONTACT_SHADOW_CULL_MASK: int = 0xFFFFF & ~KART_RENDER_LAYER
const CONTACT_SHADOW_SIZE: Vector3 = Vector3(1.9, 1.2, 2.6)
const CONTACT_SHADOW_Y: float = -0.3
const CONTACT_SHADOW_ALPHA: float = 0.6
static var _shadow_texture: GradientTexture2D

@export var feel_tuning: FeelTuning = preload("res://data/tuning/feel_default.tres")

@onready var _controller: KartController = get_parent() as KartController
@onready var _body_mesh: MeshInstance3D = $Body
@onready var _driver_mesh: MeshInstance3D = $Driver
@onready var _wheel_fl: Node3D = $WheelFL
@onready var _wheel_fr: Node3D = $WheelFR
@onready var _wheel_rl: Node3D = $WheelRL
@onready var _wheel_rr: Node3D = $WheelRR

var network_pose: Transform3D = Transform3D.IDENTITY

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
var _contact_shadow: Decal
var _shadow_quality_enabled: bool = true
var _shadow_lod_enabled: bool = true


func _ready() -> void:
	_base_local_y = position.y
	_bob_noise.seed = BOB_NOISE_SEED
	_bob_noise.frequency = 1.0
	KartMeshBuilder.decorate(self, _controller.get_kart_data(), _controller.get_night_theme())
	_rear_left_base = _wheel_rl.position
	_rear_right_base = _wheel_rr.position
	_apply_livery(_controller.get_driver_data())
	_install_contact_shadow()
	if not EventBus.kart_hit.is_connected(_on_kart_hit):
		EventBus.kart_hit.connect(_on_kart_hit)


func _exit_tree() -> void:
	if EventBus.kart_hit.is_connected(_on_kart_hit):
		EventBus.kart_hit.disconnect(_on_kart_hit)


func _process(delta: float) -> void:
	if _controller == null or delta <= 0.0:
		return
	if _controller.network_replica:
		transform = Transform3D.IDENTITY
	_update_body_pose(delta)
	_update_wheels(delta)
	_update_suspension(delta)
	_update_hit_visual()
	_update_trick_visual(delta)
	_update_hit_flash(delta)
	if _controller.network_replica:
		transform = network_pose * transform
	_update_contact_shadow()


func _update_contact_shadow() -> void:
	if _contact_shadow == null:
		return
	var anchor: Transform3D = _controller.global_transform
	if _controller.network_replica:
		anchor = anchor * network_pose
	_contact_shadow.global_transform = anchor.translated_local(Vector3(0.0, CONTACT_SHADOW_Y, 0.0))


## Applies the selected driver's livery (paint, number, helmet, suit, rims).
func apply_driver_data(driver: DriverData) -> void:
	if driver == null:
		return
	_apply_livery(driver)


func _apply_livery(driver: DriverData) -> void:
	KartMeshBuilder.apply_paint_pattern(_body_mesh, driver, _controller.get_kart_data())
	_flash_material = _body_mesh.material_override as ShaderMaterial
	for node: Node in find_children("*", "GeometryInstance3D", true, false):
		(node as VisualInstance3D).layers = KART_RENDER_LAYER


## Soft blob shadow projected onto whatever is under the kart (never onto
## karts: their meshes live on KART_RENDER_LAYER, excluded from the cull mask).
func _install_contact_shadow() -> void:
	var decal: Decal = Decal.new()
	decal.name = "ContactShadow"
	decal.size = CONTACT_SHADOW_SIZE
	decal.position = Vector3(0.0, CONTACT_SHADOW_Y, 0.0)
	decal.texture_albedo = _contact_shadow_texture()
	decal.modulate = Color(0.0, 0.0, 0.0, CONTACT_SHADOW_ALPHA)
	decal.albedo_mix = 1.0
	decal.upper_fade = 0.2
	decal.lower_fade = 0.6
	decal.cull_mask = CONTACT_SHADOW_CULL_MASK
	decal.distance_fade_enabled = true
	decal.distance_fade_begin = QualityTier.DETAIL_DISTANCE
	decal.distance_fade_length = 15.0
	add_child(decal)
	_contact_shadow = decal
	_refresh_contact_shadow()


static func _contact_shadow_texture() -> GradientTexture2D:
	if _shadow_texture != null:
		return _shadow_texture
	var gradient: Gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	gradient.colors = PackedColorArray([Color(0, 0, 0, 1), Color(0, 0, 0, 0.7), Color(0, 0, 0, 0)])
	_shadow_texture = GradientTexture2D.new()
	_shadow_texture.gradient = gradient
	_shadow_texture.width = 64
	_shadow_texture.height = 64
	_shadow_texture.fill = GradientTexture2D.FILL_RADIAL
	_shadow_texture.fill_from = Vector2(0.5, 0.5)
	_shadow_texture.fill_to = Vector2(1.0, 0.5)
	return _shadow_texture


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


## Keeps the chassis visible while culling small distant accessories.
func set_detail_tier(tier: int) -> void:
	_driver_mesh.visible = tier < 2
	_shadow_lod_enabled = tier == 0
	_refresh_contact_shadow()
	for child: Node3D in _body_mesh.get_children():
		child.visible = tier == 0


## Quality gate for the contact-shadow decal: off on the Low tier.
func set_contact_shadow_quality(enabled: bool) -> void:
	_shadow_quality_enabled = enabled
	_refresh_contact_shadow()


func _refresh_contact_shadow() -> void:
	if _contact_shadow != null:
		_contact_shadow.visible = _shadow_quality_enabled and _shadow_lod_enabled
