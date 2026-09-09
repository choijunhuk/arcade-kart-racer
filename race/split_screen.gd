class_name SplitScreen
extends Control

## Renders one shared World3D through independent player cameras and HUD canvases.

class PlayerView extends RefCounted:
	var container: SubViewportContainer
	var viewport: SubViewport
	var camera: RaceCamera
	var hud: RaceHud
	var speed_lines: SpeedLines


const CAMERA_SCENE: PackedScene = preload("res://camera/race_camera.tscn")
const HUD_SCENE: PackedScene = preload("res://ui/hud/hud.tscn")
const SPEED_LINES_SCENE: PackedScene = preload("res://effects/speed_lines.tscn")
const MAX_LOCAL_PLAYERS: int = 4
const TWO_PLAYER_RENDER_SCALE: float = 0.85
const QUAD_RENDER_SCALE: float = 0.70

var _views: Array[PlayerView] = []
var _normalized_rects: Array[Rect2] = []


func _ready() -> void:
	set_process_input(false)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_resize_views)
	SettingsManager.settings_changed.connect(_on_settings_changed)


## Rebuilds player viewports around one shared world and independent presentation.
func configure(
	shared_world: World3D, players: Array[KartController],
	lap_tracker: LapTracker, position_tracker: PositionTracker,
	kart_count: int, total_laps: int, item_manager: ItemManager,
	racing_line: RacingLine, karts: Array[KartController],
) -> void:
	clear_views()
	if players.is_empty():
		visible = false
		return
	visible = true
	_normalized_rects = layout_rects(players.size())
	var minimap_all: bool = bool(SettingsManager.get_setting(&"accessibility", &"multiplayer_minimap_all", false))
	for index: int in range(players.size()):
		var view: PlayerView = _create_view(shared_world, index)
		view.camera.set_target(players[index])
		view.hud.bind(
			players[index], lap_tracker, position_tracker, kart_count, total_laps,
			item_manager, racing_line, karts,
		)
		view.hud.set_minimap_visible(index == 0 or minimap_all)
		view.speed_lines.set_target(players[index])
		_views.append(view)
	_on_settings_changed(&"video")
	_resize_views()


## Frees every viewport so race restart cannot retain cameras or EventBus listeners.
func clear_views() -> void:
	for view: PlayerView in _views:
		if is_instance_valid(view.container):
			view.container.free()
	_views.clear()
	_normalized_rects.clear()


## Returns independent cameras in player order for LOD aggregation.
func get_cameras() -> Array[Camera3D]:
	var cameras: Array[Camera3D] = []
	for view: PlayerView in _views:
		cameras.append(view.camera)
	return cameras


## Returns independent HUDs in player order for integration verification.
func get_huds() -> Array[RaceHud]:
	var huds: Array[RaceHud] = []
	for view: PlayerView in _views:
		huds.append(view.hud)
	return huds


## Returns the number of live player render targets.
func get_viewport_count() -> int:
	return _views.size()


## Returns normalized output rectangles for one to four local players.
static func layout_rects(player_count: int) -> Array[Rect2]:
	match clampi(player_count, 1, MAX_LOCAL_PLAYERS):
		1:
			return [Rect2(0.0, 0.0, 1.0, 1.0)]
		2:
			return [Rect2(0.0, 0.0, 1.0, 0.5), Rect2(0.0, 0.5, 1.0, 0.5)]
		3:
			return [
				Rect2(0.0, 0.0, 0.5, 0.5), Rect2(0.5, 0.0, 0.5, 0.5),
				Rect2(0.0, 0.5, 0.5, 0.5),
			]
		_:
			return [
				Rect2(0.0, 0.0, 0.5, 0.5), Rect2(0.5, 0.0, 0.5, 0.5),
				Rect2(0.0, 0.5, 0.5, 0.5), Rect2(0.5, 0.5, 0.5, 0.5),
			]


## Applies a bounded extra render scale as the number of views increases.
static func render_scale_for_players(player_count: int, user_scale: float) -> float:
	var multiplayer_scale: float = 1.0
	if player_count == 2:
		multiplayer_scale = TWO_PLAYER_RENDER_SCALE
	elif player_count >= 3:
		multiplayer_scale = QUAD_RENDER_SCALE
	return clampf(user_scale, SettingsManagerService.MIN_RENDER_SCALE, SettingsManagerService.MAX_RENDER_SCALE) * multiplayer_scale


func _create_view(shared_world: World3D, index: int) -> PlayerView:
	var view: PlayerView = PlayerView.new()
	view.container = SubViewportContainer.new()
	view.container.name = "Player%dView" % (index + 1)
	view.container.stretch = true
	view.container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(view.container)
	view.viewport = SubViewport.new()
	view.viewport.name = "Viewport"
	view.viewport.world_3d = shared_world
	view.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.container.add_child(view.viewport)
	view.camera = CAMERA_SCENE.instantiate() as RaceCamera
	view.camera.name = "RaceCamera"
	view.camera.current = true
	view.viewport.add_child(view.camera)
	view.speed_lines = SPEED_LINES_SCENE.instantiate() as SpeedLines
	view.viewport.add_child(view.speed_lines)
	view.hud = HUD_SCENE.instantiate() as RaceHud
	view.viewport.add_child(view.hud)
	return view


func _resize_views() -> void:
	var output: Vector2 = size
	if output.x <= 0.0 or output.y <= 0.0:
		output = get_viewport_rect().size
	for index: int in range(_views.size()):
		var rect: Rect2 = _normalized_rects[index]
		var view: PlayerView = _views[index]
		view.container.position = rect.position * output
		view.container.size = rect.size * output


func _on_settings_changed(section: StringName) -> void:
	if section != &"video":
		return
	var root: Window = get_tree().root
	for view: PlayerView in _views:
		view.viewport.scaling_3d_scale = render_scale_for_players(_views.size(), root.scaling_3d_scale)
		view.viewport.msaa_3d = root.msaa_3d
