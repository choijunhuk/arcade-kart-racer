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
@export var velocity_drift_blend: float = 0.5
@export var camera_clip_margin: float = 0.25
@export_flags_3d_physics var camera_collision_mask: int = 1
@export var shake_noise_frequency: float = 18.0
@export var wall_head_on_trauma: float = 0.5
@export var landing_trauma_min: float = 0.2
@export var landing_trauma_max: float = 0.5
@export var landing_shake_min_speed: float = 4.0
@export var landing_shake_max_speed: float = 18.0
@export var kart_hit_trauma: float = 0.6
@export var item_explosion_trauma: float = 0.7
@export var item_explosion_shake_radius: float = 25.0

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
@export var drift_wheel_jitter_frequency: float = 24.0
@export var body_roll_steer_degrees: float = 5.0
@export var squash_vertical_scale: float = 0.45
@export var squash_horizontal_scale: float = 1.15
@export var landing_bob_velocity_scale: float = 0.012

@export_group("Effects")
@export var particle_nodes_per_kart: int = 6
@export var central_clear_fraction: float = 0.4
@export var speed_line_strength: float = 1.0
@export var hit_flash_duration: float = 0.1
@export var hit_flash_count: int = 2
@export var hit_stop_duration: float = 0.05
@export var hit_stop_time_scale: float = 0.3
@export var hit_stop_enabled: bool = true
@export var total_gpu_particle_nodes: int = 60
@export var particle_lod_distance: float = 80.0
@export var impact_pool_capacity: int = 12
@export var impact_duration: float = 0.25
@export var landing_dust_min_speed: float = 4.0
@export var skid_mark_alpha: float = 0.75
@export var skid_mark_ground_offset: float = 0.28
@export var boost_speed_line_add: float = 0.45
@export var smoke_brake_threshold: float = 0.7
@export var smoke_min_speed_ratio: float = 0.35
@export var drift_tier_cyan: Color = Color(0.1, 0.9, 1.0)
@export var drift_tier_amber: Color = Color(1.0, 0.62, 0.1)
@export var drift_tier_magenta: Color = Color(1.0, 0.1, 0.72)
@export var feedback_lerp_speed: float = 10.0
@export var boost_fov_spring_stiffness: float = 40.0
@export var boost_fov_spring_damping: float = 10.0
@export var trick_spin_speed: float = 9.0
@export var skid_mark_max_segments: int = 96
@export var skid_mark_half_width: float = 0.65
@export var skid_mark_min_spacing: float = 0.18

@export_group("UI Motion")
@export var position_punch_scale: float = 1.3
@export var position_punch_seconds: float = 0.09
@export var lap_slide_distance: float = 48.0
@export var lap_slide_seconds: float = 0.18
@export var roulette_turn_seconds: float = 0.25
@export var results_row_offset: float = 56.0
@export var results_row_delay: float = 0.08
@export var results_row_duration: float = 0.24
