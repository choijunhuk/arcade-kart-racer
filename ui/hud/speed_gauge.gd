class_name SpeedGauge
extends Control

## Arc speedometer: a 240-degree dial with tick marks and a fill arc that
## shifts cyan -> orange -> red with speed. The numeric readout is the
## `SpeedLabel` child (RaceHud writes its text); this node only draws the dial.

const START_DEGREES: float = 150.0
const SWEEP_DEGREES: float = 240.0
const MAJOR_TICKS: int = 8
const ARC_POINTS: int = 48
const SMOOTHING: float = 12.0
const LOW_COLOR: Color = Color(0.16, 0.85, 1.0)
const MID_COLOR: Color = Color(1.0, 0.55, 0.1)
const HIGH_COLOR: Color = Color(1.0, 0.18, 0.28)
const FACE_COLOR: Color = Color(0.02, 0.028, 0.06, 0.62)
const TRACK_COLOR: Color = Color(1.0, 1.0, 1.0, 0.12)
const TICK_COLOR: Color = Color(1.0, 1.0, 1.0, 0.55)
const CAPTION_COLOR: Color = Color(0.62, 0.7, 0.86, 1.0)

## Target 0..1 speed ratio; the drawn fill eases toward it.
var ratio: float = 0.0
var _shown: float = 0.0


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_place_readout()


## Centres the numeric `SpeedLabel` child on the dial hub, sized to the dial.
func _place_readout() -> void:
	var label: Label = get_node_or_null(^"SpeedLabel") as Label
	if label == null:
		return
	var radius: float = minf(size.x * 0.5, size.y * 0.56) - 8.0
	label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	label.position = Vector2(0.0, radius + 8.0 - radius * 0.5)
	label.size = Vector2(size.x, radius)
	label.add_theme_font_size_override("font_size", maxi(14, roundi(radius * 0.62)))
	queue_redraw()


func _process(delta: float) -> void:
	var eased: float = lerpf(_shown, clampf(ratio, 0.0, 1.0), 1.0 - exp(-SMOOTHING * delta))
	if absf(eased - _shown) > 0.0005:
		_shown = eased
		queue_redraw()


func _draw() -> void:
	var radius: float = minf(size.x * 0.5, size.y * 0.56) - 8.0
	if radius <= 4.0:
		return
	var center: Vector2 = Vector2(size.x * 0.5, radius + 8.0)
	var width: float = maxf(6.0, radius * 0.13)
	draw_circle(center, radius + width * 0.4, FACE_COLOR)
	var start: float = deg_to_rad(START_DEGREES)
	var sweep: float = deg_to_rad(SWEEP_DEGREES)
	draw_arc(center, radius - width * 0.5, start, start + sweep, ARC_POINTS, TRACK_COLOR, width, true)
	if _shown > 0.005:
		draw_arc(center, radius - width * 0.5, start, start + sweep * _shown, ARC_POINTS, fill_color(_shown), width, true)
	for index: int in range(MAJOR_TICKS + 1):
		var angle: float = start + sweep * float(index) / float(MAJOR_TICKS)
		var direction: Vector2 = Vector2.from_angle(angle)
		var inner: float = radius - width - 4.0
		draw_line(center + direction * inner, center + direction * (inner - width * 0.7), TICK_COLOR, 2.0, true)
	var needle: Vector2 = Vector2.from_angle(start + sweep * _shown)
	draw_line(center + needle * (radius - width * 1.9), center + needle * (radius + 2.0), Color.WHITE, 3.0, true)
	var font: Font = get_theme_font(&"font", &"CaptionLabel")
	var caption_size: int = maxi(10, roundi(radius * 0.17))
	var caption_width: float = font.get_string_size("KM/H", HORIZONTAL_ALIGNMENT_LEFT, -1.0, caption_size).x
	draw_string(font, center + Vector2(-caption_width * 0.5, radius * 0.62), "KM/H", HORIZONTAL_ALIGNMENT_LEFT, -1.0, caption_size, CAPTION_COLOR)


## Fill colour for a 0..1 speed ratio.
static func fill_color(value: float) -> Color:
	if value <= 0.55:
		return LOW_COLOR
	if value <= 0.85:
		return LOW_COLOR.lerp(MID_COLOR, (value - 0.55) / 0.3)
	return MID_COLOR.lerp(HIGH_COLOR, clampf((value - 0.85) / 0.15, 0.0, 1.0))
