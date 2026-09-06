class_name AIDifficultyProfile
extends Resource

@export var id: StringName = &"normal"
@export var display_name: String = "Normal"
@export_range(0.0, 1.0) var speed_confidence: float = 0.94
@export var look_ahead_time: float = 0.7
@export var steer_kp: float = 1.8
@export var steer_kd: float = 0.35
@export var steer_noise: float = 0.06
@export_range(0.0, 1.0) var drift_skill: float = 0.7
@export_range(1, 3) var target_tier: int = 2
@export_range(0.0, 1.0) var late_brake_prob: float = 0.1
@export_range(0.0, 1.0) var shortcut_take_prob: float = 0.5
@export var item_decision_delay: float = 0.6
@export_range(0.0, 1.0) var projectile_dodge_prob: float = 0.4
@export var rubber_band_strength: float = 0.04
@export_range(0.0, 1.0) var item_use_accuracy: float = 0.75
@export_range(0.0, 1.0) var start_boost_skill: float = 0.65
@export_range(0.0, 1.0) var trick_prob: float = 0.7
