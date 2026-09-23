class_name DriftMeter
extends Control

## Mini-turbo charge bar. The bar fill takes the colour of the tier already
## reached (white -> cyan -> amber -> magenta), three tier pips light up as
## thresholds pass, and the whole meter dims while no drift is charging.

const PERCENT_MAX: float = 100.0
const TIER_COUNT: int = 3
const IDLE_ALPHA: float = 0.42
const FADE_SPEED: float = 10.0
const UNCHARGED_COLOR: Color = Color(0.86, 0.9, 1.0)
const PIP_OFF: Color = Color(1.0, 1.0, 1.0, 0.16)

@export var tuning: FeelTuning = preload("res://data/tuning/feel_default.tres")

@onready var _bar: ProgressBar = $Panel/ChargeBar
@onready var _tier_label: Label = $Panel/TierLabel
var _controller: DriftController
## Mirrors `accessibility.drift_tier_icons`: when off, the label stays a plain
## "DRIFT" in the base colour instead of flashing tier text/colours.
var _tier_icons: bool = true
var _fill: StyleBoxFlat
var _shown_tier: int = -1


func _ready() -> void:
	_refresh_tier_icons(&"accessibility")
	SettingsManager.settings_changed.connect(_refresh_tier_icons)
	_fill = (_bar.get_theme_stylebox(&"fill") as StyleBoxFlat).duplicate() as StyleBoxFlat
	_bar.add_theme_stylebox_override(&"fill", _fill)
	modulate.a = IDLE_ALPHA


func _exit_tree() -> void:
	if SettingsManager.settings_changed.is_connected(_refresh_tier_icons):
		SettingsManager.settings_changed.disconnect(_refresh_tier_icons)


## Assigns the observed controller; the meter never mutates gameplay state.
func set_controller(controller: DriftController) -> void:
	_controller = controller


func _process(delta: float) -> void:
	if _controller == null:
		return
	var charge: float = _controller.get_charge_ratio()
	_bar.value = charge * PERCENT_MAX
	var tier: int = _controller.get_tier()
	_tier_label.text = "DRIFT T%d" % tier if tier > 0 and _tier_icons else "DRIFT"
	_tier_label.modulate = _tier_color(tier) if _tier_icons else tuning.drift_tier_cyan
	_fill.bg_color = (_tier_color(tier) if tier > 0 else UNCHARGED_COLOR) if _tier_icons else tuning.drift_tier_cyan
	modulate.a = lerpf(modulate.a, 1.0 if charge > 0.0 else IDLE_ALPHA, 1.0 - exp(-FADE_SPEED * delta))
	if tier != _shown_tier:
		_shown_tier = tier
		queue_redraw()


func _draw() -> void:
	var pip_height: float = maxf(6.0, size.y * 0.2)
	var pip_width: float = pip_height * 2.4
	var gap: float = pip_height * 0.6
	var skew: float = pip_height * 0.5
	for index: int in range(TIER_COUNT):
		var right: float = size.x - float(TIER_COUNT - 1 - index) * (pip_width + gap) - skew
		var left: float = right - pip_width
		var top: float = maxf(0.0, size.y * 0.42 - pip_height - 4.0)
		var lit: bool = _tier_icons and _shown_tier > index
		var color: Color = _tier_color(index + 1) if lit else PIP_OFF
		draw_colored_polygon(PackedVector2Array([
			Vector2(left + skew, top), Vector2(right + skew, top),
			Vector2(right, top + pip_height), Vector2(left, top + pip_height),
		]), color)


func _refresh_tier_icons(section: StringName) -> void:
	if section == &"accessibility":
		_tier_icons = bool(SettingsManager.get_setting(&"accessibility", &"drift_tier_icons", true))
		queue_redraw()


func _tier_color(tier: int) -> Color:
	match tier:
		2:
			return tuning.drift_tier_amber
		3:
			return tuning.drift_tier_magenta
		_:
			return tuning.drift_tier_cyan
