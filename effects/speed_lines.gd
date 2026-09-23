class_name SpeedLines
extends CanvasLayer

## Edge-only radial streaks that appear only near top speed or while boosting,
## easing in/out so they never pop. Drawn beneath the HUD canvas layers.

## Fraction of max speed below which no streaks show; full strength at max.
const SPEED_THRESHOLD: float = 0.82
const FADE_IN_PER_SECOND: float = 2.5
const FADE_OUT_PER_SECOND: float = 1.6

@export var tuning: FeelTuning = preload("res://data/tuning/feel_default.tres")

@onready var _material: ShaderMaterial = $Lines.material as ShaderMaterial

var _target: KartController
var _intensity: float = 0.0


## Assigns the kart observed by this presentation-only screen effect.
func set_target(target: KartController) -> void:
	_target = target
	_intensity = 0.0


func _ready() -> void:
	_material.set_shader_parameter("central_clear_fraction", tuning.central_clear_fraction)


func _process(delta: float) -> void:
	var goal: float = 0.0
	if _target != null and bool(SettingsManager.get_setting(&"accessibility", &"speed_lines", true)):
		goal = target_intensity(
			_target.get_speed_ratio(), _target.is_boosting(),
			tuning.boost_speed_line_add, tuning.speed_line_strength,
		)
	var rate: float = FADE_IN_PER_SECOND if goal > _intensity else FADE_OUT_PER_SECOND
	_intensity = move_toward(_intensity, goal, rate * maxf(delta, 0.0))
	_material.set_shader_parameter("intensity", _intensity)
	$Lines.visible = _intensity > 0.001


## Pure mapping: zero below SPEED_THRESHOLD, eased to 1 at max speed, plus boost.
static func target_intensity(speed_ratio: float, boosting: bool, boost_add: float, strength: float) -> float:
	var ramp: float = smoothstep(SPEED_THRESHOLD, 1.0, clampf(speed_ratio, 0.0, 1.0))
	var value: float = ramp * 0.7 + (boost_add + 0.3 if boosting else 0.0)
	return clampf(value * strength, 0.0, 1.0)
