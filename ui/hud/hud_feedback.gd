class_name HudFeedback
extends Control

## Short-lived race feedback on one player's HUD (19-D item 4): +N/-N rank
## change popups beside the position readout, a lap card with the lap time and
## its split against the best earlier lap (green faster / red slower), a
## "HIT BY <ITEM>" toast naming what hit you, and a stronger wrong-way cue
## (turn-around hint + pulsing red screen edges). EventBus reads only.

const GAIN_COLOR: Color = Color(0.3, 1.0, 0.45)
const LOSS_COLOR: Color = Color(1.0, 0.3, 0.25)
const NEUTRAL_COLOR: Color = Color(0.93, 0.96, 1.0)
const WARNING_COLOR: Color = Color(0.85, 0.08, 0.16)
const RANK_POPUP_SECONDS: float = 1.1
const LAP_CARD_SECONDS: float = 2.6
const HIT_TOAST_SECONDS: float = 1.8
const EDGE_PULSE_SPEED: float = 7.0

var _player_kart: KartController
var _item_manager: ItemManager
var _rank_label: Label
var _lap_label: Label
var _hit_label: Label
var _turn_label: Label
var _rank_tween: Tween
var _lap_tween: Tween
var _hit_tween: Tween
var _pending_rank_delta: int = 0
var _best_lap: float = -1.0
var _previous_stamp: float = 0.0
var _wrong_way: bool = false
var _pulse: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_rank_label = _make_label(&"HudNumber")
	_lap_label = _make_label(&"HudNumber")
	_hit_label = _make_label(&"HudText")
	_turn_label = _make_label(&"HudText")
	_turn_label.text = "TURN AROUND"
	for label: Label in [_lap_label, _hit_label, _turn_label]:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	EventBus.position_changed.connect(_on_position_changed)
	EventBus.lap_completed.connect(_on_lap_completed)
	EventBus.item_hit.connect(_on_item_hit)
	EventBus.wrong_way.connect(_on_wrong_way)
	resized.connect(_layout)
	_layout()


func _exit_tree() -> void:
	for pair: Array in [
		[EventBus.position_changed, _on_position_changed], [EventBus.lap_completed, _on_lap_completed],
		[EventBus.item_hit, _on_item_hit], [EventBus.wrong_way, _on_wrong_way],
	]:
		if (pair[0] as Signal).is_connected(pair[1] as Callable):
			(pair[0] as Signal).disconnect(pair[1] as Callable)


func bind(player_kart: KartController, item_manager: ItemManager) -> void:
	_player_kart = player_kart
	_item_manager = item_manager
	_best_lap = -1.0
	_previous_stamp = 0.0
	_pending_rank_delta = 0
	_wrong_way = false
	for label: Label in [_rank_label, _lap_label, _hit_label, _turn_label]:
		label.visible = false
	queue_redraw()


## "+2" / "-1" text for a rank change (positive = places gained).
static func rank_delta_text(places_gained: int) -> String:
	return "+%d" % places_gained if places_gained > 0 else "%d" % places_gained


## Signed split of `lap_seconds` against the best earlier lap (negative =
## faster); NAN when there is no earlier lap to compare with.
static func lap_split(lap_seconds: float, best_before: float) -> float:
	return lap_seconds - best_before if best_before > 0.0 else NAN


static func split_color(split: float) -> Color:
	if is_nan(split):
		return NEUTRAL_COLOR
	return GAIN_COLOR if split <= 0.0 else LOSS_COLOR


func _process(delta: float) -> void:
	if _wrong_way:
		_pulse += delta * EDGE_PULSE_SPEED
		queue_redraw()


func _draw() -> void:
	if not _wrong_way:
		return
	var alpha: float = 0.18 + 0.14 * sin(_pulse)
	var edge: float = maxf(10.0, size.y * 0.035)
	for rect: Rect2 in [
		Rect2(0.0, 0.0, size.x, edge), Rect2(0.0, size.y - edge, size.x, edge),
		Rect2(0.0, 0.0, edge, size.y), Rect2(size.x - edge, 0.0, edge, size.y),
	]:
		draw_rect(rect, Color(WARNING_COLOR, alpha))


func _on_position_changed(kart: Node, old_position: int, new_position: int) -> void:
	if kart != _player_kart or _player_kart == null:
		return
	_pending_rank_delta = (_pending_rank_delta if _rank_label.visible else 0) + old_position - new_position
	if _pending_rank_delta == 0:
		_rank_label.visible = false
		return
	_rank_label.text = rank_delta_text(_pending_rank_delta)
	_rank_label.add_theme_color_override("font_color", GAIN_COLOR if _pending_rank_delta > 0 else LOSS_COLOR)
	_rank_label.visible = true
	_layout()
	var rest: Vector2 = _rank_label.position
	_rank_label.position = rest + Vector2(0.0, _rank_label.size.y * 0.4)
	_rank_label.modulate.a = 1.0
	_rank_tween = _restart(_rank_tween)
	_rank_tween.tween_property(_rank_label, "position", rest, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_rank_tween.tween_interval(RANK_POPUP_SECONDS - 0.4)
	_rank_tween.tween_property(_rank_label, "modulate:a", 0.0, 0.22)
	_rank_tween.tween_callback(func() -> void: _rank_label.visible = false)


func _on_lap_completed(kart: Node, lap: int, race_seconds: float) -> void:
	if kart != _player_kart or _player_kart == null:
		return
	var lap_seconds: float = maxf(0.0, race_seconds - _previous_stamp)
	_previous_stamp = race_seconds
	var split: float = lap_split(lap_seconds, _best_lap)
	if _best_lap < 0.0 or lap_seconds < _best_lap:
		_best_lap = lap_seconds
	var split_text: String = "" if is_nan(split) else "   %+.3f" % split
	_lap_label.text = "LAP %d  %s%s" % [lap, HudReadout.format_time(lap_seconds), split_text]
	_lap_label.add_theme_color_override("font_color", split_color(split))
	_show_timed(_lap_label, LAP_CARD_SECONDS, "_lap_tween")


func _on_item_hit(source_kart: Node, target_kart: Node, item_id: StringName) -> void:
	if target_kart != _player_kart or _player_kart == null:
		return
	var item: ItemData = _item_manager.get_item_data(item_id) if _item_manager != null else null
	var item_name: String = item.display_name if item != null else String(item_id).replace("_", " ")
	var attacker: String = ""
	if source_kart is KartController and (source_kart as KartController).get_driver_data() != null:
		attacker = "  ·  %s" % (source_kart as KartController).get_driver_data().display_name.get_slice(" ", 0).to_upper()
	_hit_label.text = "HIT BY %s%s" % [item_name.to_upper(), attacker]
	_show_timed(_hit_label, HIT_TOAST_SECONDS, "_hit_tween")


func _on_wrong_way(kart: Node, active: bool) -> void:
	if kart != _player_kart or _player_kart == null:
		return
	_layout()
	_wrong_way = active
	_turn_label.visible = active
	_pulse = 0.0
	queue_redraw()


func _show_timed(label: Label, seconds: float, tween_field: StringName) -> void:
	label.visible = true
	label.modulate.a = 0.0
	label.scale = Vector2(1.25, 1.25)
	_layout()
	var tween: Tween = _restart(get(tween_field) as Tween)
	set(tween_field, tween)
	tween.set_parallel(true)
	tween.tween_property(label, "modulate:a", 1.0, 0.15)
	tween.tween_property(label, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.chain().tween_interval(seconds)
	tween.chain().tween_property(label, "modulate:a", 0.0, 0.3)
	tween.chain().tween_callback(func() -> void: label.visible = false)


func _restart(tween: Tween) -> Tween:
	if tween != null:
		tween.kill()
	return create_tween()


func _layout() -> void:
	if _rank_label == null:
		return
	var compact: bool = HudLayout.is_compact(size)
	var center_x: float = size.x * 0.5
	_place(_rank_label, Rect2(Vector2(150.0, 36.0) if compact else Vector2(254.0, 62.0), Vector2(90.0, 40.0)), 28 if compact else 44)
	_place(_lap_label, Rect2(center_x - 260.0, size.y * (0.37 if compact else 0.27), 520.0, 40.0), 20 if compact else 32)
	_place(_hit_label, Rect2(center_x - 260.0, size.y * (0.46 if compact else 0.36), 520.0, 30.0), 15 if compact else 22)
	# Directly under the HUD's own (style-padded) WRONG WAY label.
	var wrong_way: Control = get_parent().get_node_or_null(^"WrongWayLabel") as Control if get_parent() != null else null
	var below: float = wrong_way.get_rect().end.y if wrong_way != null else size.y * 0.5 + (80.0 if compact else 180.0)
	_place(_turn_label, Rect2(center_x - 200.0, below + 4.0, 400.0, 30.0), 16 if compact else 24)


func _place(label: Label, rect: Rect2, font_size: int) -> void:
	HudLayout.set_rect(label, rect)
	label.add_theme_font_size_override("font_size", font_size)
	label.pivot_offset = label.size * 0.5


func _make_label(variation: StringName) -> Label:
	var label: Label = Label.new()
	label.theme_type_variation = variation
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.visible = false
	add_child(label)
	return label
