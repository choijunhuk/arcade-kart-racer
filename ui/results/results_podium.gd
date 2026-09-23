class_name ResultsPodium
extends RefCounted

## Podium for the top three finishers (2nd | 1st | 3rd): name, kart, time on
## top of a gold/silver/bronze block whose height ranks them. Built fresh by
## ResultsScreen for every show_results() and animated rising in.

const PLACE_COLORS: Array[Color] = [Color(1.0, 0.8, 0.12), Color(0.8, 0.86, 0.96), Color(0.9, 0.52, 0.24)]
const BLOCK_HEIGHTS: Array[float] = [118.0, 86.0, 62.0]
const COLUMN_WIDTH: float = 250.0
const COLUMN_HEIGHT: float = 232.0
const DISPLAY_ORDER: Array[int] = [1, 0, 2]
const RISE_SECONDS: float = 0.42
const RISE_STAGGER: float = 0.14


## Fills `podium` (an HBoxContainer) from rank-ordered entries.
static func build(podium: HBoxContainer, ordered: Array[RaceResults.Entry], format_time: Callable) -> void:
	for child: Node in podium.get_children():
		child.free()
	for place: int in DISPLAY_ORDER:
		if place < ordered.size():
			podium.add_child(_column(ordered[place], place, format_time))


## Staggered rise (3rd, then 2nd, then 1st) of each podium block.
static func animate(podium: HBoxContainer) -> void:
	var tween: Tween = podium.create_tween().set_parallel(true)
	for column: Node in podium.get_children():
		var block: Control = column.get_node(^"Block") as Control
		var place: int = int(column.get_meta(&"place", 0))
		block.pivot_offset = Vector2(COLUMN_WIDTH * 0.5, BLOCK_HEIGHTS[place])
		block.scale = Vector2(1.0, 0.0)
		var info: Control = column.get_node(^"Info") as Control
		info.modulate.a = 0.0
		var delay: float = RISE_STAGGER * float(2 - place)
		tween.tween_property(block, "scale:y", 1.0, RISE_SECONDS).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(info, "modulate:a", 1.0, RISE_SECONDS).set_delay(delay + RISE_SECONDS * 0.5)


static func _column(entry: RaceResults.Entry, place: int, format_time: Callable) -> VBoxContainer:
	var column: VBoxContainer = VBoxContainer.new()
	column.name = "Place%d" % (place + 1)
	column.set_meta(&"place", place)
	column.custom_minimum_size = Vector2(COLUMN_WIDTH, COLUMN_HEIGHT)
	column.alignment = BoxContainer.ALIGNMENT_END
	column.add_theme_constant_override(&"separation", 6)
	var info: VBoxContainer = VBoxContainer.new()
	info.name = "Info"
	info.add_theme_constant_override(&"separation", 0)
	column.add_child(info)
	if entry.is_human:
		_label(info, "YOU" if entry.player_number <= 1 else "P%d" % entry.player_number, &"CaptionLabel", 15, Color(0.16, 0.85, 1.0))
	_label(info, entry.driver_name, &"SectionHeading", 26 if place == 0 else 22, Color.WHITE)
	var kart_name: String = entry.kart_display_name if not entry.kart_display_name.is_empty() else entry.kart_name
	_label(info, kart_name.to_upper(), &"CaptionLabel", 13, Color(0.62, 0.7, 0.86))
	_label(info, format_time.call(entry.total_time_seconds), &"HudNumber", 24, PLACE_COLORS[place])
	var block: PanelContainer = PanelContainer.new()
	block.name = "Block"
	block.custom_minimum_size = Vector2(COLUMN_WIDTH, BLOCK_HEIGHTS[place])
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = PLACE_COLORS[place].darkened(0.25)
	style.border_color = PLACE_COLORS[place].lightened(0.3)
	style.border_width_top = 5
	style.corner_radius_top_left = 14
	style.corner_radius_top_right = 3
	style.corner_detail = 1
	style.shadow_color = Color(PLACE_COLORS[place], 0.25)
	style.shadow_size = 12
	block.add_theme_stylebox_override(&"panel", style)
	column.add_child(block)
	var rank: Label = _label(block, str(place + 1), &"HudNumber", 64 if place == 0 else 52, Color.WHITE)
	rank.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return column


static func _label(parent: Control, text: String, variation: StringName, font_size: int, color: Color) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", color)
	parent.add_child(label)
	return label
