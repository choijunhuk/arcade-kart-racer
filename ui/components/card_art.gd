class_name CardArt
extends RefCounted

## Shared look for selection cards (driver / kart select): a livery-tinted
## art swatch with the preview image, and the card name label styling.

const SWATCH_TOP_ALPHA: float = 0.95
const SWATCH_DARKEN: float = 0.55


## A rounded panel filled with `tint` (darkened) holding `texture` centred.
static func swatch(texture: Texture2D, tint: Color, height: float) -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.name = "Swatch"
	panel.custom_minimum_size.y = height
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(tint.darkened(SWATCH_DARKEN), SWATCH_TOP_ALPHA)
	style.border_color = tint
	style.border_width_bottom = 3
	style.set_corner_radius_all(10)
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_detail = 1
	style.set_content_margin_all(8.0)
	panel.add_theme_stylebox_override(&"panel", style)
	var art: TextureRect = TextureRect.new()
	art.name = "Art"
	art.texture = texture
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(art)
	return panel


## Card title: display face, centred, ignoring the mouse like the rest.
static func style_name(label: Label) -> void:
	label.theme_type_variation = &"SectionHeading"
	label.add_theme_color_override(&"font_color", Color.WHITE)
	label.add_theme_font_size_override(&"font_size", 24)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
