class_name HudLayout
extends RefCounted

const COMPACT_MAX_SIZE: Vector2 = Vector2(900.0, 520.0)


## Pure HUD geometry used by both split-screen runtime layout and unit tests.
static func calculate(viewport_size: Vector2) -> Dictionary:
	var compact: bool = viewport_size.x <= COMPACT_MAX_SIZE.x or viewport_size.y <= COMPACT_MAX_SIZE.y
	if compact:
		return {
			"compact": true,
			"regions": {
				"position": Rect2(14.0, 12.0, 132.0, 86.0),
				"minimap": Rect2(14.0, viewport_size.y - 118.0, 132.0, 104.0),
				"drift": Rect2(viewport_size.x * 0.5 - 120.0, viewport_size.y - 58.0, 240.0, 44.0),
				"speedometer": Rect2(viewport_size.x * 0.5 + 126.0, viewport_size.y - 58.0, 104.0, 44.0),
				"item": Rect2(viewport_size.x - 154.0, 14.0, 140.0, 108.0),
				"shield": Rect2(viewport_size.x - 160.0, 8.0, 152.0, 120.0),
			},
		}
	return {
		"compact": false,
		"regions": {
			"position": Rect2(24.0, 20.0, 190.0, 122.0),
			"minimap": Rect2(24.0, viewport_size.y - 224.0, 260.0, 200.0),
			"drift": Rect2(viewport_size.x * 0.5 - 210.0, viewport_size.y - 98.0, 420.0, 72.0),
			"speedometer": Rect2(viewport_size.x * 0.5 + 228.0, viewport_size.y - 98.0, 170.0, 72.0),
			"item": Rect2(viewport_size.x - 244.0, 238.0, 220.0, 160.0),
			"shield": Rect2(viewport_size.x - 258.0, 224.0, 248.0, 188.0),
		},
	}


## Applies the calculated policy without owning any gameplay state.
static func apply(hud: RaceHud, viewport_size: Vector2) -> void:
	var layout: Dictionary = calculate(viewport_size)
	var regions: Dictionary = layout["regions"]
	_place(hud.get_node("PositionPanel") as Control, regions["position"])
	_place(hud.get_node("Minimap") as Control, regions["minimap"])
	_place(hud.get_node("DriftMeter") as Control, regions["drift"])
	_place(hud.get_node("Speedometer") as Control, regions["speedometer"])
	_place(hud.get_node("ItemPanel") as Control, regions["item"])
	_place(hud.get_node("ShieldTimer") as Control, regions["shield"])
	if bool(layout["compact"]):
		_apply_compact_content(hud)
	else:
		_apply_full_content(hud)
	(hud.get_node("Minimap") as RaceMinimap).refresh_layout()


static func _apply_compact_content(hud: RaceHud) -> void:
	_set_font(hud, "PositionLabel", 40)
	_set_font(hud, "PositionCountLabel", 20)
	_set_font(hud, "LapLabel", 16)
	_set_font(hud, "CountdownLabel", 72)
	_set_font(hud, "WrongWayLabel", 26)
	_set_font(hud, "MessageLabel", 24)
	_set_font(hud, "ThreatWarning", 18)
	_set_font(hud, "Speedometer/SpeedLabel", 18)
	_set_font(hud, "ItemPanel/ItemName", 16)
	_set_font(hud, "ItemPanel/RouletteLabel", 12)
	_place(hud.get_node("PositionLabel") as Control, Rect2(24.0, 18.0, 62.0, 48.0))
	_place(hud.get_node("PositionCountLabel") as Control, Rect2(84.0, 34.0, 54.0, 30.0))
	_place(hud.get_node("LapLabel") as Control, Rect2(24.0, 64.0, 114.0, 24.0))
	_place(hud.get_node("ItemPanel/Icon") as Control, Rect2(48.0, 6.0, 44.0, 44.0))
	_place(hud.get_node("ItemPanel/ItemName") as Control, Rect2(0.0, 52.0, 140.0, 20.0))
	_place(hud.get_node("ItemPanel/RouletteLabel") as Control, Rect2(0.0, 70.0, 140.0, 16.0))
	_place(hud.get_node("ItemPanel/CooldownBar") as Control, Rect2(10.0, 90.0, 120.0, 10.0))
	(hud.get_node("Minimap") as Control).custom_minimum_size = Vector2(132.0, 104.0)
	(hud.get_node("DriftMeter") as Control).custom_minimum_size = Vector2(240.0, 44.0)
	(hud.get_node("DriftMeter/Panel/ChargeBar") as Control).custom_minimum_size = Vector2(220.0, 24.0)


static func _apply_full_content(hud: RaceHud) -> void:
	_set_font(hud, "PositionLabel", 64)
	_set_font(hud, "PositionCountLabel", 28)
	_set_font(hud, "LapLabel", 22)
	_set_font(hud, "CountdownLabel", 112)
	_set_font(hud, "WrongWayLabel", 42)
	_set_font(hud, "MessageLabel", 38)
	_set_font(hud, "ThreatWarning", 30)
	_set_font(hud, "Speedometer/SpeedLabel", 24)
	(hud.get_node("ItemPanel/ItemName") as Label).remove_theme_font_size_override("font_size")
	_set_font(hud, "ItemPanel/RouletteLabel", 16)
	_place(hud.get_node("PositionLabel") as Control, Rect2(42.0, 26.0, 82.0, 78.0))
	_place(hud.get_node("PositionCountLabel") as Control, Rect2(124.0, 56.0, 70.0, 44.0))
	_place(hud.get_node("LapLabel") as Control, Rect2(42.0, 104.0, 152.0, 32.0))
	_place(hud.get_node("ItemPanel/Icon") as Control, Rect2(74.0, 10.0, 72.0, 72.0))
	_place(hud.get_node("ItemPanel/ItemName") as Control, Rect2(0.0, 86.0, 220.0, 28.0))
	_place(hud.get_node("ItemPanel/RouletteLabel") as Control, Rect2(0.0, 110.0, 220.0, 24.0))
	_place(hud.get_node("ItemPanel/CooldownBar") as Control, Rect2(16.0, 136.0, 188.0, 15.0))
	(hud.get_node("Minimap") as Control).custom_minimum_size = Vector2(260.0, 200.0)
	(hud.get_node("DriftMeter") as Control).custom_minimum_size = Vector2(420.0, 72.0)
	(hud.get_node("DriftMeter/Panel/ChargeBar") as Control).custom_minimum_size = Vector2(400.0, 42.0)


static func _place(control: Control, rect: Rect2) -> void:
	control.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	control.position = rect.position
	control.size = rect.size


static func _set_font(hud: RaceHud, path: NodePath, size: int) -> void:
	(hud.get_node(path) as Label).add_theme_font_size_override("font_size", size)
