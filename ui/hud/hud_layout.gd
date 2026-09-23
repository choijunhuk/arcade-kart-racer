class_name HudLayout
extends RefCounted

## Viewport-local HUD geometry (full-screen and compact split-screen). Pure
## data for `RaceHud.layout_for_viewport()` plus the text/child placement that
## follows a region change. Split out of RaceHud to keep it under 400 lines.

const COMPACT_MAX_WIDTH: float = 900.0
const COMPACT_MAX_HEIGHT: float = 520.0


static func is_compact(viewport_size: Vector2) -> bool:
	return viewport_size.x <= COMPACT_MAX_WIDTH or viewport_size.y <= COMPACT_MAX_HEIGHT


## Major region rects; they never overlap and always fit the viewport.
static func regions(viewport_size: Vector2) -> Dictionary:
	if is_compact(viewport_size):
		return {
			"position": Rect2(10.0, 8.0, 200.0, 104.0),
			"minimap": Rect2(10.0, viewport_size.y - 112.0, 132.0, 102.0),
			"drift": Rect2(viewport_size.x * 0.5 - 110.0, viewport_size.y - 44.0, 220.0, 36.0),
			"item": Rect2(viewport_size.x - 118.0, 10.0, 108.0, 118.0),
			"speedometer": Rect2(),
		}
	return {
		"position": Rect2(24.0, 16.0, 320.0, 200.0),
		"minimap": Rect2(24.0, viewport_size.y - 244.0, 280.0, 220.0),
		"drift": Rect2(viewport_size.x * 0.5 - 200.0, viewport_size.y - 78.0, 400.0, 56.0),
		"item": Rect2(viewport_size.x - 204.0, 236.0, 180.0, 200.0),
		"speedometer": Rect2(viewport_size.x - 244.0, viewport_size.y - 204.0, 220.0, 180.0),
	}


## Rects (and font sizes) for every free-floating HUD label, keyed by node name.
static func text_rects(viewport_size: Vector2, compact: bool) -> Dictionary:
	var center: Vector2 = viewport_size * 0.5
	if compact:
		return {
			"PositionLabel": [Rect2(14.0, 0.0, 64.0, 72.0), 66],
			"OrdinalLabel": [Rect2(84.0, 8.0, 60.0, 30.0), 26],
			"PositionCountLabel": [Rect2(88.0, 38.0, 60.0, 22.0), 15],
			"LapLabel": [Rect2(16.0, 66.0, 150.0, 22.0), 17],
			"TimerLabel": [Rect2(16.0, 86.0, 150.0, 24.0), 18],
			"SplitLabel": [Rect2(), 12],
			"CountdownLabel": [Rect2(center - Vector2(110.0, 80.0), Vector2(220.0, 160.0)), 108],
			"WrongWayLabel": [Rect2(center + Vector2(-150.0, 40.0), Vector2(300.0, 40.0)), 26],
			"MessageLabel": [Rect2(0.0, 118.0, viewport_size.x, 40.0), 28],
			"ThreatWarning": [Rect2(center.x - 170.0, 136.0, 340.0, 30.0), 18],
		}
	return {
		"PositionLabel": [Rect2(30.0, -6.0, 120.0, 132.0), 124],
		"OrdinalLabel": [Rect2(158.0, 12.0, 90.0, 50.0), 48],
		"PositionCountLabel": [Rect2(160.0, 64.0, 90.0, 30.0), 24],
		"LapLabel": [Rect2(34.0, 118.0, 280.0, 34.0), 28],
		"TimerLabel": [Rect2(34.0, 150.0, 280.0, 36.0), 30],
		"SplitLabel": [Rect2(36.0, 186.0, 300.0, 24.0), 15],
		"CountdownLabel": [Rect2(center - Vector2(220.0, 150.0), Vector2(440.0, 300.0)), 220],
		"WrongWayLabel": [Rect2(center + Vector2(-300.0, 110.0), Vector2(600.0, 70.0)), 52],
		"MessageLabel": [Rect2(0.0, 150.0, viewport_size.x, 70.0), 56],
		"ThreatWarning": [Rect2(center.x - 350.0, 24.0, 700.0, 54.0), 30],
	}


## Places every free-floating HUD label for the given viewport.
static func apply_text(hud: CanvasLayer, viewport_size: Vector2, compact: bool) -> void:
	var rects: Dictionary = text_rects(viewport_size, compact)
	for node_name: String in rects:
		var label: Label = hud.get_node_or_null(NodePath(node_name)) as Label
		if label == null:
			continue
		var entry: Array = rects[node_name]
		set_rect(label, entry[0] as Rect2)
		label.add_theme_font_size_override("font_size", int(entry[1]))
		label.pivot_offset = label.size * 0.5
	(hud.get_node("SplitLabel") as Label).visible = not compact


static func set_rect(control: Control, rect: Rect2) -> void:
	control.set_anchors_preset(Control.PRESET_TOP_LEFT)
	control.position = rect.position
	control.size = rect.size
