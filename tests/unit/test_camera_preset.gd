extends GutTest

## Phase 17b Part B — camera_preset resolver and settings persistence.

const SETTINGS_PATH: String = "user://phase17b_camera_preset_test.cfg"


func before_each() -> void:
	_remove_test_file()


func after_each() -> void:
	_remove_test_file()


func test_resolve_id_falls_back_to_arcade_for_unknown_ids() -> void:
	assert_eq(CameraPreset.resolve_id(CameraPreset.CINEMATIC_ID), CameraPreset.CINEMATIC_ID)
	assert_eq(CameraPreset.resolve_id("nonsense"), CameraPreset.ARCADE_ID)
	assert_eq(CameraPreset.resolve_id(""), CameraPreset.ARCADE_ID)


func test_load_for_id_maps_unknown_ids_to_the_arcade_resource() -> void:
	var unknown: CameraPreset = CameraPreset.load_for_id("nonsense")
	var arcade: CameraPreset = CameraPreset.load_for_id(CameraPreset.ARCADE_ID)
	assert_almost_eq(unknown.follow_stiffness, arcade.follow_stiffness, 0.001)
	assert_almost_eq(unknown.camera_height, arcade.camera_height, 0.001)


func test_arcade_is_tighter_and_stronger_than_cinematic() -> void:
	var arcade: CameraPreset = CameraPreset.load_for_id(CameraPreset.ARCADE_ID)
	var cinematic: CameraPreset = CameraPreset.load_for_id(CameraPreset.CINEMATIC_ID)
	assert_gt(arcade.follow_stiffness, cinematic.follow_stiffness, "arcade spring should be tighter")
	assert_gt(arcade.camera_height, cinematic.camera_height, "cinematic camera should sit lower")
	assert_gt(arcade.speed_fov_add, cinematic.speed_fov_add, "arcade FOV-by-speed should be stronger")
	assert_gt(arcade.boost_fov_add, cinematic.boost_fov_add, "arcade boost FOV should be stronger")
	assert_gt(arcade.drift_side_offset, cinematic.drift_side_offset, "arcade drift offset should be larger")


func test_settings_round_trip_persists_camera_preset() -> void:
	var writer: SettingsManagerService = SettingsManagerService.new(SETTINGS_PATH, false)
	autofree(writer)
	var changed: Dictionary = writer.default_settings()
	changed["gameplay"]["camera_preset"] = CameraPreset.CINEMATIC_ID
	assert_eq(writer.save_settings(changed), OK)
	var reader: SettingsManagerService = SettingsManagerService.new(SETTINGS_PATH, false)
	autofree(reader)

	var loaded: Dictionary = reader.load_settings()

	assert_eq(loaded["gameplay"]["camera_preset"], CameraPreset.CINEMATIC_ID)


func test_missing_camera_preset_defaults_to_arcade() -> void:
	var manager: SettingsManagerService = SettingsManagerService.new(SETTINGS_PATH, false)
	autofree(manager)

	var settings: Dictionary = manager.load_settings()

	assert_eq(settings["gameplay"]["camera_preset"], CameraPreset.ARCADE_ID)


func _remove_test_file() -> void:
	if FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))
