class_name SpeedLines
extends CanvasLayer

## Full-screen edge-only radial lines driven by speed-squared and boost state.

@export var tuning: FeelTuning = preload("res://data/tuning/feel_default.tres")

@onready var _material: ShaderMaterial = $Lines.material as ShaderMaterial

var _target: KartController


## Assigns the kart observed by this presentation-only screen effect.
func set_target(target: KartController) -> void:
	_target = target


func _ready() -> void:
	_material.set_shader_parameter("central_clear_fraction", tuning.central_clear_fraction)


func _process(_delta: float) -> void:
	var intensity: float = 0.0
	if _target != null and bool(SettingsManager.get_setting(&"accessibility", &"speed_lines", true)):
		var speed_ratio: float = _target.get_speed_ratio()
		intensity = speed_ratio * speed_ratio
		if _target.is_boosting():
			intensity += tuning.boost_speed_line_add
		intensity = clampf(intensity * tuning.speed_line_strength, 0.0, 1.0)
	_material.set_shader_parameter("intensity", intensity)
