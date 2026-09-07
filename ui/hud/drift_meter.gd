class_name DriftMeter
extends Control

@export var tuning: FeelTuning = preload("res://data/tuning/feel_default.tres")

@onready var _bar: ProgressBar = $Panel/ChargeBar
@onready var _tier_label: Label = $Panel/TierLabel
var _controller: DriftController


## Assigns the observed controller; the meter never mutates gameplay state.
func set_controller(controller: DriftController) -> void:
	_controller = controller


func _process(_delta: float) -> void:
	if _controller == null:
		return
	_bar.value = _controller.get_charge_ratio() * 100.0
	var tier: int = _controller.get_tier()
	_tier_label.text = "DRIFT T%d" % tier if tier > 0 else "DRIFT"
	_tier_label.modulate = _tier_color(tier)


func _tier_color(tier: int) -> Color:
	match tier:
		2:
			return tuning.drift_tier_amber
		3:
			return tuning.drift_tier_magenta
		_:
			return tuning.drift_tier_cyan
