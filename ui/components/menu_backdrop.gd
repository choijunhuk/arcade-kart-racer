class_name MenuBackdrop
extends SubViewportContainer

## Live 3D attract-mode backdrop for the main menu: a real content track in
## its own World3D with a pack of decorated (visual-only, physics-free) karts
## lapping its racing line, filmed by a smooth trackside chase camera that
## cuts between cinematic angles. Skipped entirely on the headless display
## server (GUT/menu tests) so menus stay cheap to instantiate there.

const TRACK_DATA_PATHS: Array[String] = [
	"res://data/tracks/track_01.tres",
	"res://data/tracks/track_03.tres",
	"res://data/tracks/track_04.tres",
	"res://data/tracks/track_02.tres",
]
const KART_DIRECTORY: String = "res://data/karts"
const DRIVER_DIRECTORY: String = "res://data/drivers"
const PACK_SIZE: int = 6
const PACK_SPACING_METRES: float = 7.5
const LANE_OFFSETS: Array[float] = [-2.2, 1.8, -0.6, 2.4, -1.9, 0.7]
const BASE_SPEED: float = 24.0
const SPEED_JITTER: float = 1.6
const RIDE_HEIGHT: float = 0.42
const SHOT_SECONDS: float = 6.5
const CAMERA_SMOOTHING: float = 3.0
## Camera rigs relative to the lead kart: [back, side, up, look-ahead].
const SHOTS: Array[Vector4] = [
	Vector4(-9.0, -2.5, 2.1, 10.0),
	Vector4(15.0, 4.0, 1.5, -8.0),
	Vector4(-3.0, -8.5, 1.2, 3.0),
	Vector4(-22.0, 3.0, 8.5, 10.0),
]
## Aim this far to the camera's left so the pack sits right of the menu column.
const SCREEN_SHIFT_METRES: float = 3.2

## Which of TRACK_DATA_PATHS to film (wraps); -1 picks one per launch.
@export var track_index: int = 0

@onready var _viewport: SubViewport = $SubViewport
@onready var _camera: Camera3D = $SubViewport/Camera3D

var _line: RacingLine
var _karts: Array[Node3D] = []
var _offsets: PackedFloat32Array = PackedFloat32Array()
var _speeds: PackedFloat32Array = PackedFloat32Array()
var _shot_elapsed: float = 0.0
var _shot_index: int = 0
var _snap_camera: bool = true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return
	_build_world()


func _build_world() -> void:
	var index: int = randi() % TRACK_DATA_PATHS.size() if track_index < 0 else track_index % TRACK_DATA_PATHS.size()
	var track_data: TrackData = load(TRACK_DATA_PATHS[index]) as TrackData
	if track_data == null or track_data.scene == null:
		return
	var track: TrackRoot = track_data.scene.instantiate() as TrackRoot
	_viewport.add_child(track)
	_line = track.get_racing_line()
	if _line == null or _line.length() <= 0.0:
		return
	var kart_data: Array[Resource] = ResourceScanner.scan_tres(KART_DIRECTORY)
	var drivers: Array[Resource] = ResourceScanner.scan_tres(DRIVER_DIRECTORY)
	for slot: int in range(PACK_SIZE):
		var visuals: Node3D = KartPreview.build_visual_skeleton()
		_viewport.add_child(visuals)
		var driver: DriverData = drivers[slot % drivers.size()] as DriverData if not drivers.is_empty() else null
		if not kart_data.is_empty():
			KartMeshBuilder.decorate(visuals, kart_data[slot % kart_data.size()] as KartData, track_data.night_theme)
		if driver != null:
			KartMeshBuilder.apply_paint_pattern(visuals.get_node("Body") as MeshInstance3D, driver)
		_karts.append(visuals)
		_offsets.append(float(PACK_SIZE - slot) * PACK_SPACING_METRES)
		_speeds.append(BASE_SPEED + randf_range(-SPEED_JITTER, SPEED_JITTER))


func _process(delta: float) -> void:
	if _line == null or _karts.is_empty():
		return
	var length: float = _line.length()
	var lead: int = 0
	for index: int in range(_karts.size()):
		_offsets[index] = fposmod(_offsets[index] + _speeds[index] * delta, length)
		_place_kart(_karts[index], _offsets[index], LANE_OFFSETS[index % LANE_OFFSETS.size()])
		if _gap_ahead(_offsets[index], _offsets[lead], length) > 0.0:
			lead = index
	_update_camera(delta, _offsets[lead], length)


## Signed along-track distance of `offset` ahead of `reference` on a loop.
func _gap_ahead(offset: float, reference: float, length: float) -> float:
	var gap: float = fposmod(offset - reference, length)
	return gap if gap < length * 0.5 else gap - length


func _place_kart(kart: Node3D, offset: float, lane: float) -> void:
	var tangent: Vector3 = _line.tangent_at(offset)
	var spot: Vector3 = _line.sample(offset) + _line.right_at(offset) * lane + Vector3.UP * RIDE_HEIGHT
	kart.global_transform = Transform3D(Basis.looking_at(tangent, Vector3.UP), spot)


func _update_camera(delta: float, lead_offset: float, length: float) -> void:
	_shot_elapsed += delta
	if _shot_elapsed >= SHOT_SECONDS:
		_shot_elapsed = 0.0
		_shot_index = (_shot_index + 1) % SHOTS.size()
		_snap_camera = true
	var rig: Vector4 = SHOTS[_shot_index]
	var anchor_offset: float = fposmod(lead_offset + rig.x, length)
	var desired: Vector3 = _line.sample(anchor_offset) + _line.right_at(anchor_offset) * rig.y + Vector3.UP * rig.z
	var target: Vector3 = _line.sample(fposmod(lead_offset + rig.w, length)) + Vector3.UP * 1.0
	target -= _camera.global_transform.basis.x * SCREEN_SHIFT_METRES
	var weight: float = 1.0 if _snap_camera else 1.0 - exp(-CAMERA_SMOOTHING * delta)
	_snap_camera = false
	_camera.global_position = _camera.global_position.lerp(desired, weight)
	if not _camera.global_position.is_equal_approx(target):
		_camera.look_at(target, Vector3.UP)
