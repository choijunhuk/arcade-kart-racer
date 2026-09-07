class_name PhysicsTuning
extends Resource

@export_group("Longitudinal")
@export var gravity: float = 24.0
@export var reverse_max_speed: float = 8.0
@export var brake_force: float = 22.0
@export var drag: float = 4.0
@export var overspeed_decay: float = 8.0
@export var accel_curve: Curve

@export_group("Steering and Grip")
@export var base_turn_rate: float = 2.4
@export var min_steer_speed: float = 0.5
@export var steer_smoothing: float = 8.0
@export var steer_curve: Curve
@export var grip: float = 9.0
@export var drift_grip: float = 2.2

@export_group("Slipstream")
@export var slipstream_range: float = 18.0
@export var slipstream_time: float = 1.5
@export var slipstream_speed_mult: float = 1.08
@export var slipstream_exit_duration: float = 0.8
@export var slipstream_exit_boost: BoostSpecData

@export_group("Ground and Air")
@export var min_grounded_rays: int = 2
@export var ground_ray_length: float = 0.8
@export var hover_height: float = 0.35
@export var floor_snap_length: float = 0.6
@export var gravity_along_slope: float = 1.0
@export var max_climb_angle_degrees: float = 50.0
@export var air_steer_factor: float = 0.35
@export var landing_speed_loss: float = 0.03
@export var landing_speed_loss_cap: float = 0.25
@export var landing_align_threshold_degrees: float = 35.0
@export var hover_snap_speed: float = 10.0
@export var up_align_speed_grounded: float = 15.0
@export var up_align_speed_airborne: float = 3.0

@export_group("Walls and Kart Contact")
@export var wall_normal_threshold: float = 0.55
@export var wall_graze_angle_degrees: float = 30.0
@export var wall_head_on_angle_degrees: float = 60.0
@export var wall_graze_loss: float = 0.92
@export var wall_head_on_loss: float = 0.35
@export var wall_bounce: float = 0.25
## Metres of positional push-back per unit of bounce on a wall hit.
@export var wall_bounce_push: float = 0.1
@export var wall_push_out: float = 1.5
@export var separation_push: float = 0.25

@export_group("Drift")
@export var drift_min_steer: float = 0.35
@export var drift_min_speed: float = 6.0
@export var drift_hop_duration: float = 0.15
@export var drift_cancel_speed: float = 2.0
@export var drift_cancel_delay: float = 0.4
@export var drift_airborne_cancel_time: float = 0.5
@export var drift_opposite_cancel_delay: float = 0.3
@export var drift_base_turn: float = 1.6
@export var drift_steer_influence: float = 1.1
@export var drift_speed_retention: float = 0.97
@export var drift_visual_angles_degrees: PackedFloat32Array = PackedFloat32Array([15.0, 22.0, 28.0])
@export var base_charge_rate: float = 1.0
@export var steer_alignment_bonus: float = 0.5
@export var min_drift_yaw_rate: float = 0.35
@export var low_turn_quality_mult: float = 0.3
@export var drift_cooldown: float = 0.35

@export_group("Trick and Boost")
@export var trick_min_air_time: float = 0.35
@export var trick_boost: BoostSpecData
@export var mini_turbo_tiers: Array[MiniTurboTier] = []
@export var boost_pad_boost: BoostSpecData
@export var item_boost: BoostSpecData
@export var start_boost_tier_one: BoostSpecData
@export var start_boost_tier_two: BoostSpecData
@export var start_boost_window: float = 0.35
@export var early_acceleration_spin_duration: float = 0.8
@export var max_boost_duration: float = 4.0
