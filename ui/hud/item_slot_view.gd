class_name HudItemSlot
extends Control

## Stylised item slot (the HUD's `ItemPanel`): a ringed disc frame that is
## visibly empty when nothing is held, a slot-machine roulette that flicks
## through every item icon while the reveal runs, and a pop when it lands.
## Observes the kart's ItemSlot read-only; RaceHud feeds it every frame.

const ITEM_DIRECTORY: String = "res://data/items"
const ROULETTE_FLICK_SECONDS: float = 0.065
const ROULETTE_SPIN_SPEED: float = 7.0
const LAND_POP_SCALE: float = 1.35
const LAND_POP_SECONDS: float = 0.22
const LABEL_HEIGHT_RATIO: float = 0.2
const RING_HELD: Color = Color(1.0, 0.82, 0.12)
const RING_EMPTY: Color = Color(0.55, 0.64, 0.8, 0.55)
const RING_ROULETTE: Color = Color(1.0, 0.46, 0.08)
const DISC_HELD: Color = Color(0.93, 0.96, 1.0, 0.94)
const DISC_EMPTY: Color = Color(0.02, 0.03, 0.07, 0.5)
const SHADOW: Color = Color(0.0, 0.0, 0.0, 0.35)
const SEGMENTS: int = 10

static var _icon_pool: Array[Texture2D] = []

@onready var _icon: TextureRect = $Icon
@onready var _item_name: Label = $ItemName
@onready var _roulette_label: Label = $RouletteLabel
@onready var _cooldown_bar: ProgressBar = $CooldownBar

var _state: int = 0 # 0 empty, 1 roulette, 2 held
var _flick_elapsed: float = 0.0
var _flick_index: int = 0
var _spin: float = 0.0
var _pop_tween: Tween
var _flick_tween: Tween


## Places the frame, icon, name and cooldown bar for the current rect.
func layout(compact: bool) -> void:
	var label_height: float = maxf(16.0, size.y * LABEL_HEIGHT_RATIO)
	var disc: float = minf(size.x, size.y - label_height) - 8.0
	var disc_origin: Vector2 = Vector2((size.x - disc) * 0.5, 4.0)
	var icon_size: float = disc * 0.62
	HudLayout.set_rect(_icon, Rect2(disc_origin + Vector2.ONE * (disc - icon_size) * 0.5, Vector2.ONE * icon_size))
	_icon.pivot_offset = _icon.size * 0.5
	HudLayout.set_rect(_item_name, Rect2(0.0, disc_origin.y + disc + 2.0, size.x, label_height))
	HudLayout.set_rect(_roulette_label, Rect2())
	HudLayout.set_rect(_cooldown_bar, Rect2(size.x * 0.18, disc_origin.y + disc - 6.0, size.x * 0.64, 7.0 if compact else 9.0))
	_item_name.add_theme_font_size_override("font_size", 12 if compact else 16)
	queue_redraw()


## Mirrors the held item / roulette / cooldown state of one ItemSlot.
func observe(slot: ItemSlot, cooldown_ratio: float, delta: float) -> void:
	var held: ItemData = slot.get_item_data()
	var next_state: int = 1 if slot.roulette_active else (2 if held != null else 0)
	if next_state == 1:
		_advance_roulette(delta, slot.get_roulette_result())
	elif next_state == 2:
		_icon.texture = held.icon
		_item_name.text = held.display_name.to_upper()
		if _state == 1:
			_pop_icon()
	else:
		_icon.texture = null
		_item_name.text = ""
	_roulette_label.text = ""
	_cooldown_bar.value = cooldown_ratio * 100.0
	_cooldown_bar.visible = cooldown_ratio > 0.0
	if next_state != _state:
		_state = next_state
		queue_redraw()


func _process(delta: float) -> void:
	if _state == 1:
		_spin = fmod(_spin + delta * ROULETTE_SPIN_SPEED, TAU)
		queue_redraw()


func _advance_roulette(delta: float, result: ItemData) -> void:
	_item_name.text = ""
	_flick_elapsed += delta
	if _state != 1 or _flick_elapsed >= ROULETTE_FLICK_SECONDS:
		_flick_elapsed = 0.0
		var pool: Array[Texture2D] = _icons()
		if pool.is_empty():
			_icon.texture = result.icon if result != null else null
			return
		_flick_index = (_flick_index + 1) % pool.size()
		_icon.texture = pool[_flick_index]
		if _flick_tween != null:
			_flick_tween.kill()
		_icon.scale = Vector2(1.0, 0.82)
		_flick_tween = create_tween()
		_flick_tween.tween_property(_icon, "scale", Vector2.ONE, ROULETTE_FLICK_SECONDS * 0.9)


func _pop_icon() -> void:
	if _flick_tween != null:
		_flick_tween.kill()
	if _pop_tween != null:
		_pop_tween.kill()
	_icon.scale = Vector2.ONE * LAND_POP_SCALE
	_pop_tween = create_tween()
	_pop_tween.tween_property(_icon, "scale", Vector2.ONE, LAND_POP_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _draw() -> void:
	var label_height: float = maxf(16.0, size.y * LABEL_HEIGHT_RATIO)
	var disc: float = minf(size.x, size.y - label_height) - 8.0
	if disc <= 8.0:
		return
	var radius: float = disc * 0.5
	var center: Vector2 = Vector2(size.x * 0.5, 4.0 + radius)
	var ring: float = maxf(4.0, radius * 0.1)
	draw_circle(center + Vector2(3.0, 5.0), radius + 2.0, SHADOW)
	draw_circle(center, radius, DISC_HELD if _state == 2 else DISC_EMPTY)
	if _state == 1:
		draw_circle(center, radius - ring, Color(DISC_HELD, 0.85))
		for index: int in range(SEGMENTS):
			var from: float = _spin + TAU * float(index) / float(SEGMENTS)
			var color: Color = RING_ROULETTE if index % 2 == 0 else RING_HELD
			draw_arc(center, radius - ring * 0.5, from, from + TAU / float(SEGMENTS) * 0.8, 8, color, ring, true)
		return
	draw_arc(center, radius - ring * 0.5, 0.0, TAU, 48, RING_HELD if _state == 2 else RING_EMPTY, ring, true)
	if _state == 0:
		draw_arc(center, radius * 0.55, 0.0, TAU, 32, Color(RING_EMPTY, 0.25), 2.0, true)


static func _icons() -> Array[Texture2D]:
	if _icon_pool.is_empty():
		for resource: Resource in ResourceScanner.scan_tres(ITEM_DIRECTORY):
			var item: ItemData = resource as ItemData
			if item != null and item.icon != null:
				_icon_pool.append(item.icon)
	return _icon_pool
