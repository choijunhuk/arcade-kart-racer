extends GutTest

const SETTINGS_PATH: String = "user://phase0_settings_manager_test.cfg"


func before_each() -> void:
	_remove_test_file()


func after_each() -> void:
	_remove_test_file()


func test_missing_file_loads_complete_defaults() -> void:
	var manager: SettingsManagerService = SettingsManagerService.new(SETTINGS_PATH, false)
	autofree(manager)

	var settings: Dictionary = manager.load_settings()

	assert_eq(settings["audio"]["master"], 1.0)
	assert_true(settings["video"].has("fullscreen"))
	assert_true(settings["controls"].has("deadzone"))
	assert_true(settings["accessibility"].has("speed_lines"))
	assert_true(settings["gameplay"].has("camera_shake"))


func test_settings_round_trip_preserves_changed_values_and_defaults() -> void:
	var writer: SettingsManagerService = SettingsManagerService.new(SETTINGS_PATH, false)
	autofree(writer)
	var changed: Dictionary = writer.default_settings()
	changed["audio"]["master"] = 0.35
	changed["gameplay"]["speedometer"] = false
	assert_eq(writer.save_settings(changed), OK)
	var reader: SettingsManagerService = SettingsManagerService.new(SETTINGS_PATH, false)
	autofree(reader)

	var loaded: Dictionary = reader.load_settings()

	assert_almost_eq(loaded["audio"]["master"], 0.35, 0.001)
	assert_false(loaded["gameplay"]["speedometer"])
	assert_eq(loaded["controls"]["deadzone"], 0.2)


func test_joypad_motion_remap_round_trip_preserves_device_axis_and_direction() -> void:
	var manager: SettingsManagerService = SettingsManagerService.new(SETTINGS_PATH, false)
	autofree(manager)
	var source: InputEventJoypadMotion = InputEventJoypadMotion.new()
	source.device = 2
	source.axis = JOY_AXIS_LEFT_X
	source.axis_value = -1.0

	var encoded: Dictionary = manager.serialize_input_event(source)
	var decoded: InputEvent = manager.deserialize_input_event(encoded)

	assert_true(decoded is InputEventJoypadMotion)
	var decoded_motion: InputEventJoypadMotion = decoded as InputEventJoypadMotion
	assert_eq(decoded_motion.device, 2)
	assert_eq(decoded_motion.axis, JOY_AXIS_LEFT_X)
	assert_eq(decoded_motion.axis_value, -1.0)


func _remove_test_file() -> void:
	if FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))
