class_name DriftMeter
extends Control

const PERCENT_MAX: float = 100.0

@export var tuning: FeelTuning = preload("res://data/tuning/feel_default.tres")

@onready var _bar: ProgressBar = $Panel/ChargeBar
@onready var _tier_label: Label = $Panel/TierLabel
var _controller: DriftController
## Mirrors `accessibility.drift_tier_icons`: when off, the label stays a plain
## "DRIFT" in the base colour instead of flashing tier text/colours.
var _tier_icons: bool = true


func _ready() -> void:
	_refresh_tier_icons(&"accessibility")
	SettingsManager.settings_changed.connect(_refresh_tier_icons)


func _exit_tree() -> void:
	if SettingsManager.settings_changed.is_connected(_refresh_tier_icons):
		SettingsManager.settings_changed.disconnect(_refresh_tier_icons)


## Assigns the observed controller; the meter never mutates gameplay state.
func set_controller(controller: DriftController) -> void:
	_controller = controller


func _process(_delta: float) -> void:
	if _controller == null:
		return
	_bar.value = _controller.get_charge_ratio() * PERCENT_MAX
	var tier: int = _controller.get_tier()
	_tier_label.text = "DRIFT T%d" % tier if tier > 0 and _tier_icons else "DRIFT"
	_tier_label.modulate = _tier_color(tier) if _tier_icons else tuning.drift_tier_cyan


func _refresh_tier_icons(section: StringName) -> void:
	if section == &"accessibility":
		_tier_icons = bool(SettingsManager.get_setting(&"accessibility", &"drift_tier_icons", true))


func _tier_color(tier: int) -> Color:
	match tier:
		2:
			return tuning.drift_tier_amber
		3:
			return tuning.drift_tier_magenta
		_:
			return tuning.drift_tier_cyan
