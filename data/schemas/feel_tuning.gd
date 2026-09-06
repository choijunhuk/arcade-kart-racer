class_name FeelTuning
extends Resource

@export_group("Camera")
@export var camera_distance: float = 5.5
@export var camera_height: float = 2.2
@export var follow_stiffness: float = 10.0
@export var base_fov: float = 70.0
@export var speed_fov_add: float = 14.0
@export var boost_fov_add: float = 8.0
@export var drift_side_offset: float = 0.7
@export var drift_camera_roll_degrees: float = 2.0
@export var trauma_decay: float = 1.5
@export var maximum_shake_rotation_degrees: float = 2.0
@export var maximum_shake_position: float = 0.15
@export var look_back_blend_time: float = 0.15

@export_group("Kart Body")
@export var roll_per_lateral: float = 0.025
@export var maximum_body_roll_degrees: float = 12.0
@export var acceleration_pitch_degrees: float = 3.0
@export var braking_pitch_degrees: float = 4.0
@export var suspension_bob_amplitude: float = 0.04
@export var suspension_bob_frequency: float = 7.0
@export var suspension_stiffness: float = 18.0
@export var suspension_damping: float = 8.0
@export var maximum_wheel_steer_degrees: float = 28.0
@export var drift_wheel_jitter: float = 0.02

@export_group("Effects")
@export var particle_nodes_per_kart: int = 6
@export var central_clear_fraction: float = 0.4
@export var speed_line_strength: float = 1.0
@export var hit_flash_duration: float = 0.1
@export var hit_flash_count: int = 2
@export var hit_stop_duration: float = 0.05
@export var hit_stop_time_scale: float = 0.3
