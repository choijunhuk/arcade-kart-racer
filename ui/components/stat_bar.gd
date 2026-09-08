class_name StatBar
extends HBoxContainer

## Configures one labeled normalized stat value for a selection card.
func configure(stat_name: String, normalized_value: float, signed_text: String = "") -> void:
	var name_label: Label = $Name as Label
	var value_bar: ProgressBar = $Value as ProgressBar
	name_label.text = stat_name
	value_bar.value = clampf(normalized_value, 0.0, 1.0) * 100.0
	value_bar.tooltip_text = signed_text
