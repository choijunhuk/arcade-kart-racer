class_name RaceIntroCard
extends Control

## Top-centre title card shown during the pre-countdown flyover (19-D item 2):
## track name plus a skip hint in the HUD theme. Listens to EventBus only; the
## skip itself is handled by Countdown.

const SLIDE_SECONDS: float = 0.35
const FADE_SECONDS: float = 0.25
const REFERENCE_HEIGHT: float = 720.0
const TITLE_SIZE: int = 54
const HINT_SIZE: int = 18
const HINT_COLOR: Color = Color(0.75, 0.82, 0.95)

var _panel: PanelContainer
var _title: Label
var _hint: Label
var _tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.theme_type_variation = &"HudPanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	_panel.add_child(column)
	_title = _make_label(column, &"HudNumber")
	_hint = _make_label(column, &"HudText")
	_hint.add_theme_color_override("font_color", HINT_COLOR)
	_hint.text = "PRESS ENTER / A TO SKIP"
	visible = false
	EventBus.race_intro_started.connect(_on_intro_started)
	EventBus.race_intro_finished.connect(_on_intro_finished)
	resized.connect(_layout)


func _exit_tree() -> void:
	if EventBus.race_intro_started.is_connected(_on_intro_started):
		EventBus.race_intro_started.disconnect(_on_intro_started)
		EventBus.race_intro_finished.disconnect(_on_intro_finished)


## Shows the card with `title` (the track name) for a flyover.
func show_card(title: String) -> void:
	_title.text = title.to_upper()
	visible = true
	_layout()
	if _tween != null:
		_tween.kill()
	var rest: Vector2 = _panel.position
	_panel.position = rest - Vector2(0.0, size.y * 0.08)
	modulate.a = 0.0
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_panel, "position", rest, SLIDE_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "modulate:a", 1.0, SLIDE_SECONDS)


func hide_card() -> void:
	if not visible:
		return
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 0.0, FADE_SECONDS)
	_tween.tween_callback(func() -> void: visible = false)


func _on_intro_started(_seconds: float) -> void:
	var config: RaceConfig = GameState.pending_race_config
	show_card(config.track.display_name if config != null and config.track != null else "GET READY")


func _on_intro_finished() -> void:
	hide_card()


func _layout() -> void:
	if _panel == null:
		return
	var scale_factor: float = clampf(size.y / REFERENCE_HEIGHT, 0.55, 1.4)
	_title.add_theme_font_size_override("font_size", roundi(TITLE_SIZE * scale_factor))
	_hint.add_theme_font_size_override("font_size", maxi(12, roundi(HINT_SIZE * scale_factor)))
	_panel.reset_size()
	_panel.position = Vector2((size.x - _panel.size.x) * 0.5, size.y * 0.12)


func _make_label(parent: Node, variation: StringName) -> Label:
	var label: Label = Label.new()
	label.theme_type_variation = variation
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label
