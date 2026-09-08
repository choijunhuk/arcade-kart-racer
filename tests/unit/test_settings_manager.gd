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


func test_update_setting_persists_shake_zero_across_a_service_reload() -> void:
	var writer: SettingsManagerService = SettingsManagerService.new(SETTINGS_PATH, false)
	autofree(writer)
	writer.load_settings()
	assert_true(writer.has_method("update_setting"))
	if not writer.has_method("update_setting"):
		return

	assert_eq(writer.call("update_setting", &"gameplay", &"shake_strength", 0.0), OK)
	var reader: SettingsManagerService = SettingsManagerService.new(SETTINGS_PATH, false)
	autofree(reader)
	reader.load_settings()

	assert_almost_eq(reader.get_shake_strength(), 0.0, 0.001)


func test_remap_conflict_swaps_bindings_and_persists_them() -> void:
	var original_accelerate: Array[InputEvent] = InputMap.action_get_events(InputActions.ACCELERATE)
	var original_brake: Array[InputEvent] = InputMap.action_get_events(InputActions.BRAKE)
	var accelerate_key: InputEventKey = _make_key(KEY_J)
	var brake_key: InputEventKey = _make_key(KEY_K)
	InputMap.action_erase_events(InputActions.ACCELERATE)
	InputMap.action_add_event(InputActions.ACCELERATE, accelerate_key)
	InputMap.action_erase_events(InputActions.BRAKE)
	InputMap.action_add_event(InputActions.BRAKE, brake_key)
	var manager: SettingsManagerService = SettingsManagerService.new(SETTINGS_PATH, true)
	add_child_autofree(manager)
	await wait_process_frames(1)
	assert_true(manager.has_method("remap_action"))
	if manager.has_method("remap_action"):
		assert_eq(manager.call("remap_action", InputActions.ACCELERATE, brake_key), OK)
		assert_eq((InputMap.action_get_events(InputActions.ACCELERATE)[0] as InputEventKey).physical_keycode, KEY_K)
		assert_eq((InputMap.action_get_events(InputActions.BRAKE)[0] as InputEventKey).physical_keycode, KEY_J)
		var reader: SettingsManagerService = SettingsManagerService.new(SETTINGS_PATH, false)
		autofree(reader)
		reader.load_settings()
		var remaps: Dictionary = reader.get_setting(&"controls", &"remaps", {}) as Dictionary
		assert_eq(int(remaps["accelerate"][0]["physical_keycode"]), KEY_K)
		assert_eq(int(remaps["brake"][0]["physical_keycode"]), KEY_J)
		_restore_action(InputActions.ACCELERATE, original_accelerate)
		_restore_action(InputActions.BRAKE, original_brake)
		reader.apply_section(&"controls")
		assert_eq((InputMap.action_get_events(InputActions.ACCELERATE)[0] as InputEventKey).physical_keycode, KEY_K)
		assert_eq((InputMap.action_get_events(InputActions.BRAKE)[0] as InputEventKey).physical_keycode, KEY_J)
	_restore_action(InputActions.ACCELERATE, original_accelerate)
	_restore_action(InputActions.BRAKE, original_brake)


func _remove_test_file() -> void:
	if FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))


func _make_key(physical_keycode: Key) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = physical_keycode
	return event


func _restore_action(action: StringName, events: Array[InputEvent]) -> void:
	InputMap.action_erase_events(action)
	for event: InputEvent in events:
		InputMap.action_add_event(action, event)
