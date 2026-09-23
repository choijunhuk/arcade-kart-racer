class_name RaceNameTags
extends Control

## Opponent name tags (19-D item 3): rank + driver name projected above every
## other kart through this viewport's own camera, fading with distance, so
## each split-screen HUD tags its own view. The racer directly ahead and
## directly behind the bound player get a rival accent. Read-only; hidden by
## the `gameplay.name_tags` setting. Tags that would overlap a nearer (or
## rival) tag are dropped so a distant pack never turns into a text pile.

const NEAR_DISTANCE: float = 16.0
const FAR_DISTANCE: float = 55.0
const TAG_HEIGHT: float = 0.7
const REFERENCE_HEIGHT: float = 720.0
const BASE_FONT_SIZE: float = 17.0
const MIN_FONT_SIZE: int = 11
const PADDING: Vector2 = Vector2(8.0, 3.0)
const BACKGROUND: Color = Color(0.035, 0.043, 0.09, 0.72)
const AHEAD_COLOR: Color = Color(1.0, 0.48, 0.1)
const BEHIND_COLOR: Color = Color(0.3, 0.85, 1.0)
const OUTLINE: Color = Color(0.02, 0.03, 0.07, 0.95)

enum Rival { NONE, AHEAD, BEHIND }


## Per-kart tag scratch, allocated once per bind and reused every _draw.
class TagInfo extends RefCounted:
	var kart: KartController
	var name_text: String = ""
	var point: Vector2
	var alpha: float = 0.0
	var distance: float = 0.0
	var rank: int = 0
	var rival: Rival = Rival.NONE
	var font_size: int = 0
	var rank_width: float = 0.0
	var box: Rect2


var _player_kart: KartController
var _position_tracker: PositionTracker
var _karts: Array[KartController] = []
var _enabled: bool = true
var _font: Font
var _pool: Array[TagInfo] = []
var _visible_tags: Array[TagInfo] = []
var _placed_tags: Array[TagInfo] = []
var _placed_boxes: Array[Rect2] = []
var _sort_by_priority: Callable = _priority_first
var _pointer: PackedVector2Array = PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var _pointer_colors: PackedColorArray = PackedColorArray([Color.WHITE])
var _no_uvs: PackedVector2Array = PackedVector2Array()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_font = get_theme_font(&"font", &"HudText")
	_refresh_setting(&"gameplay")
	SettingsManager.settings_changed.connect(_refresh_setting)


func _exit_tree() -> void:
	if SettingsManager.settings_changed.is_connected(_refresh_setting):
		SettingsManager.settings_changed.disconnect(_refresh_setting)


func bind(player_kart: KartController, position_tracker: PositionTracker, karts: Array[KartController]) -> void:
	_player_kart = player_kart
	_position_tracker = position_tracker
	_karts = karts.duplicate()
	_pool.clear()
	for kart: KartController in _karts:
		if kart == player_kart or not is_instance_valid(kart):
			continue
		var tag: TagInfo = TagInfo.new()
		tag.kart = kart
		tag.name_text = _driver_name(kart).to_upper()
		_pool.append(tag)
	queue_redraw()


func is_enabled() -> bool:
	return _enabled


## 0..1 opacity for a tag `distance` metres from the camera.
static func fade_for_distance(distance: float) -> float:
	return 1.0 - smoothstep(NEAR_DISTANCE, FAR_DISTANCE, distance)


## Rival relation of a kart ranked `other_rank` to a player ranked `player_rank`.
static func rival_for(player_rank: int, other_rank: int) -> Rival:
	if player_rank <= 0 or other_rank <= 0:
		return Rival.NONE
	if other_rank == player_rank - 1:
		return Rival.AHEAD
	if other_rank == player_rank + 1:
		return Rival.BEHIND
	return Rival.NONE


func _process(_delta: float) -> void:
	if visible and _player_kart != null:
		queue_redraw()


func _draw() -> void:
	if not _enabled or _player_kart == null or _position_tracker == null or _font == null:
		return
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return
	var player_rank: int = _position_tracker.get_position(_player_kart)
	var to_local: Transform2D = get_global_transform_with_canvas().affine_inverse()
	var font_scale: float = clampf(get_viewport_rect().size.y / REFERENCE_HEIGHT, 0.6, 1.3)
	_visible_tags.clear()
	for tag: TagInfo in _pool:
		if not is_instance_valid(tag.kart):
			continue
		var anchor: Vector3 = _anchor(tag.kart)
		tag.distance = camera.global_position.distance_to(anchor)
		tag.alpha = fade_for_distance(tag.distance)
		if tag.alpha <= 0.02 or camera.is_position_behind(anchor):
			continue
		tag.point = to_local * camera.unproject_position(anchor)
		tag.rank = _position_tracker.get_position(tag.kart)
		tag.rival = rival_for(player_rank, tag.rank)
		_visible_tags.append(tag)
	_visible_tags.sort_custom(_sort_by_priority)
	_placed_tags.clear()
	_placed_boxes.clear()
	for tag: TagInfo in _visible_tags:
		_measure(tag, font_scale)
		if declutter_accepts(tag.box, _placed_boxes):
			_placed_tags.append(tag)
			_placed_boxes.append(tag.box)
	for index: int in range(_placed_tags.size() - 1, -1, -1):
		_draw_tag(_placed_tags[index])


## Rivals first, then nearest first: they claim screen space before others.
static func _priority_first(a: TagInfo, b: TagInfo) -> bool:
	var a_rival: bool = a.rival != Rival.NONE
	var b_rival: bool = b.rival != Rival.NONE
	if a_rival != b_rival:
		return a_rival
	return a.distance < b.distance


## A tag is drawn only when its box does not overlap an already placed one.
static func declutter_accepts(box: Rect2, placed: Array[Rect2]) -> bool:
	for other: Rect2 in placed:
		if other.grow(2.0).intersects(box):
			return false
	return true


func _measure(tag: TagInfo, font_scale: float) -> void:
	var size_boost: float = 1.15 if tag.rival != Rival.NONE else 1.0
	tag.font_size = maxi(MIN_FONT_SIZE, roundi(BASE_FONT_SIZE * font_scale * size_boost * lerpf(0.75, 1.0, tag.alpha)))
	tag.rank_width = _font.get_string_size(str(tag.rank), HORIZONTAL_ALIGNMENT_LEFT, -1, tag.font_size).x
	var name_width: float = _font.get_string_size(tag.name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, tag.font_size).x
	var box_size: Vector2 = Vector2(tag.rank_width + tag.font_size * 0.45 + name_width, tag.font_size) + PADDING * 2.0
	tag.box = Rect2(tag.point - Vector2(box_size.x * 0.5, box_size.y + tag.font_size * 0.45), box_size)


func _draw_tag(tag: TagInfo) -> void:
	var alpha: float = tag.alpha
	var font_size: int = tag.font_size
	var box: Rect2 = tag.box
	var accent: Color = AHEAD_COLOR if tag.rival == Rival.AHEAD else BEHIND_COLOR
	draw_rect(box, Color(BACKGROUND, BACKGROUND.a * alpha))
	if tag.rival != Rival.NONE:
		draw_rect(box, Color(accent, alpha), false, 2.0)
		var tip: Vector2 = Vector2(box.get_center().x, box.end.y + font_size * 0.45)
		var half: float = font_size * 0.35
		_pointer[0] = Vector2(tip.x - half, box.end.y)
		_pointer[1] = Vector2(tip.x + half, box.end.y)
		_pointer[2] = tip
		_pointer_colors[0] = Color(accent, alpha)
		# draw_primitive: no triangulation, so a degenerate (tiny/offscreen) pointer cannot error.
		draw_primitive(_pointer, _pointer_colors, _no_uvs)
	var baseline: float = box.position.y + PADDING.y + font_size * 0.82
	var rank_color: Color = HudReadout.position_color(tag.rank)
	_draw_text(Vector2(box.position.x + PADDING.x, baseline), str(tag.rank), font_size, Color(rank_color, alpha))
	var name_color: Color = accent if tag.rival != Rival.NONE else Color.WHITE
	var name_x: float = box.position.x + PADDING.x + tag.rank_width + font_size * 0.45
	_draw_text(Vector2(name_x, baseline), tag.name_text, font_size, Color(name_color, alpha))


func _draw_text(at: Vector2, text: String, font_size: int, color: Color) -> void:
	draw_string_outline(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, Color(OUTLINE, color.a))
	draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


## Tags follow the rendered body (network replicas render delayed visuals).
func _anchor(kart: KartController) -> Vector3:
	var visuals: Node3D = kart.get_node_or_null(^"Visuals") as Node3D
	var base: Vector3 = visuals.global_position if visuals != null else kart.global_position
	return base + Vector3.UP * TAG_HEIGHT


func _driver_name(kart: KartController) -> String:
	var driver: DriverData = kart.get_driver_data()
	if driver == null or driver.display_name.is_empty():
		return String(kart.name)
	return driver.display_name.get_slice(" ", 0)


func _refresh_setting(section: StringName) -> void:
	if section == &"gameplay":
		_enabled = bool(SettingsManager.get_setting(&"gameplay", &"name_tags", true))
		queue_redraw()
