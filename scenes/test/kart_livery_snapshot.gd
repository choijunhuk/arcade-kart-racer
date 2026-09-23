extends Node3D
## Windowed visual review (not headless): lines up one kart per driver on a
## flat lit pad and saves rear-3/4, front-3/4 and close-up PNGs, so livery,
## driver and material changes can be judged without running a race.
## usage: godot --path . --resolution 1600x900 res://scenes/test/kart_livery_snapshot.tscn -- <out_dir>

const KART_SCENE: PackedScene = preload("res://kart/kart.tscn")
const SPACING: float = 3.4
const SETTLE_FRAMES: int = 45
const VIEWS: Array[Array] = [
	[Vector3(-9.0, 3.2, 9.0), Vector3(2.0, 0.3, 0.0)],
	[Vector3(9.0, 3.0, -9.0), Vector3(-2.0, 0.3, 0.0)],
	[Vector3(-4.2, 1.6, 3.6), Vector3(-5.1, 0.4, 0.0)],
	[Vector3(-3.0, 1.5, -3.4), Vector3(-5.1, 0.4, 0.0)],
]

var _out_dir: String = "/tmp/livery"
var _frame: int = 0
var _view: int = 0
var _camera: Camera3D


func _ready() -> void:
	GameState.automation_mode = true
	var args: PackedStringArray = OS.get_cmdline_user_args()
	_out_dir = args[0] if args.size() > 0 else _out_dir
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var overlay: Node = get_node_or_null(^"/root/DebugOverlay")
	if overlay != null:
		overlay.set("visible", false)
	_build_stage()
	var drivers: Array[Resource] = ResourceScanner.scan_tres("res://data/drivers")
	for index: int in range(drivers.size()):
		var kart: KartController = KART_SCENE.instantiate() as KartController
		kart.set_driver_data(drivers[index] as DriverData)
		add_child(kart)
		kart.global_position = Vector3((float(index) - float(drivers.size() - 1) * 0.5) * SPACING, 0.7, 0.0)
	_camera = Camera3D.new()
	_camera.fov = 55.0
	add_child(_camera)
	_camera.make_current()
	_place_camera(0)


func _process(_delta: float) -> void:
	_frame += 1
	if _frame < SETTLE_FRAMES:
		return
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png("%s/livery_%02d.png" % [_out_dir, _view])
	_view += 1
	if _view >= VIEWS.size():
		get_tree().quit()
		return
	_place_camera(_view)
	_frame = SETTLE_FRAMES - 3


func _place_camera(view: int) -> void:
	_camera.global_position = VIEWS[view][0] as Vector3
	_camera.look_at(VIEWS[view][1] as Vector3, Vector3.UP)


func _build_stage() -> void:
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = Sky.new()
	environment.sky.sky_material = ProceduralSkyMaterial.new()
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	var world: WorldEnvironment = WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)
	var ground: StaticBody3D = StaticBody3D.new()
	ground.collision_layer = 1
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(80.0, 1.0, 80.0)
	shape.shape = box
	ground.add_child(shape)
	var mesh: MeshInstance3D = MeshInstance3D.new()
	var plane: BoxMesh = BoxMesh.new()
	plane.size = box.size
	mesh.mesh = plane
	var asphalt: StandardMaterial3D = StandardMaterial3D.new()
	asphalt.albedo_color = Color(0.22, 0.23, 0.25)
	asphalt.roughness = 0.9
	mesh.material_override = asphalt
	ground.add_child(mesh)
	ground.position.y = -0.5
	add_child(ground)
