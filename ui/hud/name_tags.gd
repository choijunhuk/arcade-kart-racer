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

var _player_kart: KartController
var _position_tracker: PositionTracker
var _karts: Array[KartController] = []
var _enabled: bool = true
var _font: Font


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
	var tags: Array[Dictionary] = []
	for kart: KartController in _karts:
		if kart == _player_kart or not is_instance_valid(kart):
			continue
		var anchor: Vector3 = _anchor(kart)
		var distance: float = camera.global_position.distance_to(anchor)
		var alpha: float = fade_for_distance(distance)
		if alpha <= 0.02 or camera.is_position_behind(anchor):
			continue
		var rank: int = _position_tracker.get_position(kart)
		tags.append({
			"point": to_local * camera.unproject_position(anchor), "alpha": alpha, "distance": distance,
			"rank": rank, "rival": rival_for(player_rank, rank), "name": _driver_name(kart),
		})
	tags.sort_custom(_priority_first)
	var placed: Array[Dictionary] = []
	for tag: Dictionary in tags:
		_measure(tag, font_scale)
		if not declutter_accepts(tag["box"] as Rect2, placed):
			continue
		placed.append(tag)
	placed.reverse()
	for tag: Dictionary in placed:
		_draw_tag(tag)


## Rivals first, then nearest first: they claim screen space before others.
static func _priority_first(a: Dictionary, b: Dictionary) -> bool:
	var a_rival: bool = (a["rival"] as Rival) != Rival.NONE
	var b_rival: bool = (b["rival"] as Rival) != Rival.NONE
	if a_rival != b_rival:
		return a_rival
	return float(a["distance"]) < float(b["distance"])


## A tag is drawn only when its box does not overlap an already placed one.
static func declutter_accepts(box: Rect2, placed: Array[Dictionary]) -> bool:
	for other: Dictionary in placed:
		if (other["box"] as Rect2).grow(2.0).intersects(box):
			return false
	return true


func _measure(tag: Dictionary, font_scale: float) -> void:
	var rival: Rival = tag["rival"] as Rival
	var size_boost: float = 1.15 if rival != Rival.NONE else 1.0
	var font_size: int = maxi(MIN_FONT_SIZE, roundi(BASE_FONT_SIZE * font_scale * size_boost * lerpf(0.75, 1.0, float(tag["alpha"]))))
	var rank_width: float = _font.get_string_size(str(int(tag["rank"])), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var name_width: float = _font.get_string_size(String(tag["name"]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var box_size: Vector2 = Vector2(rank_width + font_size * 0.45 + name_width, font_size) + PADDING * 2.0
	tag["font_size"] = font_size
	tag["rank_width"] = rank_width
	tag["box"] = Rect2(Vector2(tag["point"]) - Vector2(box_size.x * 0.5, box_size.y + font_size * 0.45), box_size)


func _draw_tag(tag: Dictionary) -> void:
	var rival: Rival = tag["rival"] as Rival
	var alpha: float = float(tag["alpha"])
	var font_size: int = int(tag["font_size"])
	var rank_text: String = str(int(tag["rank"]))
	var name_text: String = String(tag["name"]).to_upper()
	var rank_width: float = float(tag["rank_width"])
	var gap: float = font_size * 0.45
	var box: Rect2 = tag["box"] as Rect2
	var accent: Color = AHEAD_COLOR if rival == Rival.AHEAD else BEHIND_COLOR
	draw_rect(box, Color(BACKGROUND, BACKGROUND.a * alpha))
	if rival != Rival.NONE:
		draw_rect(box, Color(accent, alpha), false, 2.0)
		var tip: Vector2 = Vector2(box.get_center().x, box.end.y + font_size * 0.45)
		var half: float = font_size * 0.35
		draw_colored_polygon(PackedVector2Array([
			Vector2(tip.x - half, box.end.y), Vector2(tip.x + half, box.end.y), tip,
		]), Color(accent, alpha))
	var baseline: float = box.position.y + PADDING.y + font_size * 0.82
	var rank_color: Color = HudReadout.position_color(int(tag["rank"]))
	_draw_text(Vector2(box.position.x + PADDING.x, baseline), rank_text, font_size, Color(rank_color, alpha))
	var name_color: Color = accent if rival != Rival.NONE else Color.WHITE
	_draw_text(Vector2(box.position.x + PADDING.x + rank_width + gap, baseline), name_text, font_size, Color(name_color, alpha))


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
