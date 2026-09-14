extends GutTest

## Persistence tests for the tutorial's SettingsManager-backed state (spec
## §1): skip/completion persists as `tutorial_done`, and hints one-shot/
## disable state round-trips through the same settings file save_manager.gd
## is deliberately not touched by (a SENSITIVE_PATHS file).

const SETTINGS_PATH: String = "user://phase18c_tutorial_settings_test.cfg"


func before_each() -> void:
	_remove_test_file()


func after_each() -> void:
	_remove_test_file()


func test_defaults_have_tutorial_not_done_and_hints_enabled_with_no_seen_hints() -> void:
	var manager: SettingsManagerService = SettingsManagerService.new(SETTINGS_PATH, false)
	autofree(manager)

	var settings: Dictionary = manager.load_settings()

	assert_false(bool(settings["tutorial"]["tutorial_done"]))
	assert_true(bool(settings["tutorial"]["hints_enabled"]))
	assert_eq((settings["tutorial"]["hints_seen"] as Dictionary).size(), 0)


func test_skipping_the_tutorial_persists_tutorial_done_across_a_reload() -> void:
	var writer: SettingsManagerService = SettingsManagerService.new(SETTINGS_PATH, false)
	autofree(writer)
	writer.load_settings()

	assert_eq(writer.update_setting(&"tutorial", &"tutorial_done", true), OK)
	var reader: SettingsManagerService = SettingsManagerService.new(SETTINGS_PATH, false)
	autofree(reader)

	var loaded: Dictionary = reader.load_settings()

	assert_true(bool(loaded["tutorial"]["tutorial_done"]))


func test_hints_seen_dictionary_round_trips_and_stays_one_shot() -> void:
	var writer: SettingsManagerService = SettingsManagerService.new(SETTINGS_PATH, false)
	autofree(writer)
	writer.load_settings()
	var state: FirstRaceHintsState = FirstRaceHintsState.new(true, {})
	assert_true(state.consume(FirstRaceHintsState.Hint.DRIFT))
	assert_eq(writer.update_setting(&"tutorial", &"hints_seen", state.seen_snapshot()), OK)

	var reader: SettingsManagerService = SettingsManagerService.new(SETTINGS_PATH, false)
	autofree(reader)
	var loaded: Dictionary = reader.load_settings()
	var restored: FirstRaceHintsState = FirstRaceHintsState.new(
		bool(loaded["tutorial"]["hints_enabled"]), loaded["tutorial"]["hints_seen"],
	)

	assert_true(restored.has_seen(FirstRaceHintsState.Hint.DRIFT))
	assert_false(restored.consume(FirstRaceHintsState.Hint.DRIFT), "a hint restored from settings must not re-fire")
	assert_true(restored.consume(FirstRaceHintsState.Hint.ITEM), "an unseen hint must still be able to fire")


func test_disabling_hints_persists_and_suppresses_all_hints_on_reload() -> void:
	var writer: SettingsManagerService = SettingsManagerService.new(SETTINGS_PATH, false)
	autofree(writer)
	writer.load_settings()
	assert_eq(writer.update_setting(&"tutorial", &"hints_enabled", false), OK)

	var reader: SettingsManagerService = SettingsManagerService.new(SETTINGS_PATH, false)
	autofree(reader)
	var loaded: Dictionary = reader.load_settings()
	var restored: FirstRaceHintsState = FirstRaceHintsState.new(
		bool(loaded["tutorial"]["hints_enabled"]), loaded["tutorial"]["hints_seen"],
	)

	assert_false(restored.consume(FirstRaceHintsState.Hint.DRIFT))
	assert_false(restored.consume(FirstRaceHintsState.Hint.ITEM))
	assert_false(restored.consume(FirstRaceHintsState.Hint.RAMP))


func _remove_test_file() -> void:
	if FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(SETTINGS_PATH)
