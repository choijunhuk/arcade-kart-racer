class_name KartPreview
extends SubViewportContainer

## Cheap live 3D showcase for one kart: an isolated SubViewport world with a
## single decorated kart visuals node that spins in place (Phase 17b item 5:
## kart select hero preview and the main menu background silhouette share
## this component). Not for grids of karts at once -- one live viewport per
## instance is the intended footprint.

const CAMERA_DISTANCE: float = 3.6
const CAMERA_HEIGHT: float = 1.4
const CAMERA_TARGET_HEIGHT: float = 0.35
const CAMERA_FOV_DEGREES: float = 32.0
const KEY_LIGHT_ENERGY: float = 1.15
const KEY_LIGHT_ROTATION_DEGREES: Vector3 = Vector3(-42.0, -35.0, 0.0)
const AMBIENT_ENERGY: float = 1.0
const AMBIENT_COLOR: Color = Color(0.55, 0.62, 0.72)
const SILHOUETTE_AMBIENT_ENERGY: float = 0.35
const SILHOUETTE_AMBIENT_COLOR: Color = Color(0.2, 0.24, 0.3)
const DEFAULT_ROTATION_SPEED: float = 0.6

## Rotation speed in radians/second; menu background instances slow this down.
@export var rotation_speed: float = DEFAULT_ROTATION_SPEED
## Flattens lighting and dims the container for a background/decorative use.
@export var silhouette: bool = false

@onready var _viewport: SubViewport = $SubViewport
@onready var _environment: WorldEnvironment = $SubViewport/WorldEnvironment
@onready var _key_light: DirectionalLight3D = $SubViewport/KeyLight
@onready var _camera: Camera3D = $SubViewport/Camera3D

var _visuals: Node3D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_key_light.rotation_degrees = KEY_LIGHT_ROTATION_DEGREES
	_key_light.light_energy = KEY_LIGHT_ENERGY
	_camera.fov = CAMERA_FOV_DEGREES
	_camera.position = Vector3(0.0, CAMERA_HEIGHT, CAMERA_DISTANCE)
	_camera.look_at(Vector3(0.0, CAMERA_TARGET_HEIGHT, 0.0), Vector3.UP)
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = SILHOUETTE_AMBIENT_COLOR if silhouette else AMBIENT_COLOR
	environment.ambient_light_energy = SILHOUETTE_AMBIENT_ENERGY if silhouette else AMBIENT_ENERGY
	_environment.environment = environment
	_viewport.transparent_bg = true
	modulate.a = 0.6 if silhouette else 1.0


func _process(delta: float) -> void:
	if _visuals != null:
		_visuals.rotation.y += rotation_speed * delta


## Rebuilds the previewed kart from scratch (drivers/karts are swapped
## wholesale rather than diffed, matching KartMeshBuilder's own test helper).
func show_kart(data: KartData, night_theme: bool = false, driver: DriverData = null) -> void:
	if data == null:
		return
	if _visuals != null:
		_visuals.queue_free()
	_visuals = build_visual_skeleton()
	_viewport.add_child(_visuals)
	KartMeshBuilder.decorate(_visuals, data, night_theme)
	if driver != null:
		KartMeshBuilder.apply_paint_pattern(_visuals.get_node("Body") as MeshInstance3D, driver)


## Bare Visuals skeleton (Body/Driver/wheel nodes) matching kart/kart.tscn,
## ready for KartMeshBuilder.decorate(); shared with MenuBackdrop.
static func build_visual_skeleton() -> Node3D:
	var visuals: Node3D = Node3D.new()
	visuals.name = "Visuals"
	var body: MeshInstance3D = MeshInstance3D.new()
	body.name = "Body"
	visuals.add_child(body)
	var driver: MeshInstance3D = MeshInstance3D.new()
	driver.name = "Driver"
	visuals.add_child(driver)
	# KartMeshBuilder.decorate() places the driver and wheel pivots per kart.
	for wheel_name: StringName in KartMeshBuilder.WHEEL_NAMES:
		var wheel: Node3D = Node3D.new()
		wheel.name = String(wheel_name)
		visuals.add_child(wheel)
	return visuals
