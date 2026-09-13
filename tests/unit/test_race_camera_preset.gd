extends GutTest

## Phase 17b Part B — RaceCamera applies camera_preset values on demand and at runtime.

const KART_SCENE: PackedScene = preload("res://kart/kart.tscn")
const CAMERA_SCENE: PackedScene = preload("res://camera/race_camera.tscn")


func test_camera_applies_preset_spring_and_fov_values() -> void:
	var camera: RaceCamera = _spawn_camera()

	camera.apply_camera_preset(CameraPreset.CINEMATIC_ID)

	var cinematic: CameraPreset = CameraPreset.load_for_id(CameraPreset.CINEMATIC_ID)
	assert_almost_eq(camera.tuning.follow_stiffness, cinematic.follow_stiffness, 0.001)
	assert_almost_eq(camera.tuning.camera_height, cinematic.camera_height, 0.001)
	assert_almost_eq(camera.tuning.speed_fov_add, cinematic.speed_fov_add, 0.001)
	assert_almost_eq(camera.tuning.boost_fov_add, cinematic.boost_fov_add, 0.001)
	assert_almost_eq(camera.tuning.drift_side_offset, cinematic.drift_side_offset, 0.001)


func test_preset_switch_at_runtime_updates_the_camera() -> void:
	var camera: RaceCamera = _spawn_camera()

	camera.apply_camera_preset(CameraPreset.ARCADE_ID)
	var arcade_stiffness: float = camera.tuning.follow_stiffness
	var arcade_offset: float = camera.tuning.drift_side_offset

	camera.apply_camera_preset(CameraPreset.CINEMATIC_ID)

	assert_ne(camera.tuning.follow_stiffness, arcade_stiffness)
	assert_ne(camera.tuning.drift_side_offset, arcade_offset)
	var cinematic: CameraPreset = CameraPreset.load_for_id(CameraPreset.CINEMATIC_ID)
	assert_almost_eq(camera.tuning.follow_stiffness, cinematic.follow_stiffness, 0.001)
	assert_almost_eq(camera.tuning.drift_side_offset, cinematic.drift_side_offset, 0.001)


func test_unknown_preset_id_falls_back_to_arcade_values() -> void:
	var camera: RaceCamera = _spawn_camera()

	camera.apply_camera_preset("nonsense")

	var arcade: CameraPreset = CameraPreset.load_for_id(CameraPreset.ARCADE_ID)
	assert_almost_eq(camera.tuning.follow_stiffness, arcade.follow_stiffness, 0.001)


func _spawn_camera() -> RaceCamera:
	var kart: KartController = KART_SCENE.instantiate() as KartController
	add_child_autofree(kart)
	var camera: RaceCamera = CAMERA_SCENE.instantiate() as RaceCamera
	add_child_autofree(camera)
	camera.call("set_target", kart)
	return camera
