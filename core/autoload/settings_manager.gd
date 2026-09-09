class_name SettingsManagerService
extends Node

signal settings_changed(section: StringName)

const DEFAULT_SETTINGS_PATH: String = "user://settings.cfg"
const MIN_VOLUME: float = 0.0
const MAX_VOLUME: float = 1.0
const STRENGTH_PERCENT_MAX: float = 100.0
const AUDIO_BUS_KEYS: Dictionary = {
	"master": "Master",
	"music": "Music",
	"sfx": "SFX",
	"engine": "Engine",
}
const REMAPPABLE_ACTIONS: Array[StringName] = [
	InputActions.ACCELERATE,
	InputActions.BRAKE,
	InputActions.STEER_LEFT,
	InputActions.STEER_RIGHT,
	InputActions.DRIFT,
	InputActions.USE_ITEM,
	InputActions.LOOK_BACK,
	InputActions.PAUSE,
	&"ui_accept",
	&"ui_cancel",
	&"ui_left",
	&"ui_right",
	&"ui_up",
	&"ui_down",
]
const MIN_RENDER_SCALE: float = 0.5
const MAX_RENDER_SCALE: float = 1.0

var settings_path: String = DEFAULT_SETTINGS_PATH
var apply_on_load: bool = true

var _settings: Dictionary = {}


func _init(custom_settings_path: String = DEFAULT_SETTINGS_PATH, should_apply_on_load: bool = true) -> void:
	settings_path = custom_settings_path
	apply_on_load = should_apply_on_load


func _ready() -> void:
	load_settings()


## Returns a fresh complete settings dictionary grouped by ConfigFile section.
func default_settings() -> Dictionary:
	return {
		"audio": {"master": 1.0, "music": 1.0, "sfx": 1.0, "engine": 1.0, "final_lap_pitch": true},
		"video": {
			"resolution": Vector2i(1600, 900),
			"fullscreen": false,
			"vsync": true,
			"render_scale": 1.0,
			"particle_quality": 2,
		},
		"controls": {
			"deadzone": 0.2,
			"steering_sensitivity": 1.0,
			"vibration": true,
			"remaps": {},
		},
		"accessibility": {
			"speed_lines": true,
			"drift_tier_icons": true,
			"multiplayer_minimap_all": false,
		},
		"gameplay": {
			"camera_shake": 1.0,
			"fov_effect": 1.0,
			"shake_strength": 100.0,
			"fov_effect_strength": 100.0,
			"speedometer": true,
		},
	}


## Returns camera shake strength normalized from its stored 0-100 percent value.
func get_shake_strength() -> float:
	return clampf(
		float(get_setting(&"gameplay", &"shake_strength", STRENGTH_PERCENT_MAX)) / STRENGTH_PERCENT_MAX,
		0.0, 1.0,
	)


## Returns FOV effect strength normalized from its stored 0-100 percent value.
func get_fov_effect_strength() -> float:
	return clampf(
		float(get_setting(&"gameplay", &"fov_effect_strength", STRENGTH_PERCENT_MAX)) / STRENGTH_PERCENT_MAX,
		0.0, 1.0,
	)


## Loads all sections, filling absent values from defaults and optionally applying them.
func load_settings() -> Dictionary:
	var config: ConfigFile = ConfigFile.new()
	var load_error: Error = config.load(settings_path)
	var defaults: Dictionary = default_settings()
	_settings = defaults.duplicate(true)
	if load_error == OK:
		for section_key: Variant in defaults:
			var section: String = str(section_key)
			var section_defaults: Dictionary = defaults[section]
			for setting_key: Variant in section_defaults:
				var key: String = str(setting_key)
				_settings[section][key] = _validated_value(config.get_value(section, key, section_defaults[key]), section_defaults[key])
	elif load_error != ERR_FILE_NOT_FOUND:
		push_warning("Settings file could not be loaded; defaults will be used.")
	if apply_on_load:
		apply_all()
	return _settings.duplicate(true)


## Persists complete settings, applies them, and announces each changed section.
func save_settings(values: Dictionary) -> Error:
	_settings = _merge_with_defaults(values)
	var save_error: Error = _persist_current_settings()
	if save_error != OK:
		return save_error
	if apply_on_load:
		apply_all()
	for section_key: Variant in _settings:
		settings_changed.emit(StringName(str(section_key)))
	return OK


## Returns a stored value or the supplied fallback when no value exists.
func get_setting(section: StringName, key: StringName, fallback: Variant = null) -> Variant:
	var section_values: Dictionary = _settings.get(String(section), {})
	return section_values.get(String(key), fallback)


## Changes one value, applies its section, and emits a change notification.
func set_setting(section: StringName, key: StringName, value: Variant) -> void:
	var section_text: String = String(section)
	if not _settings.has(section_text):
		_settings[section_text] = {}
	_settings[section_text][String(key)] = value
	if apply_on_load:
		apply_section(section)
	settings_changed.emit(section)


## Changes, applies, announces, and persists one setting atomically enough for UI use.
func update_setting(section: StringName, key: StringName, value: Variant) -> Error:
	if _settings.is_empty():
		load_settings()
	set_setting(section, key, value)
	return _persist_current_settings()


## Rebinds one action and swaps any conflicting action's prior binding.
func remap_action(action: StringName, event: InputEvent) -> Error:
	if not InputMap.has_action(action):
		return ERR_DOES_NOT_EXIST
	var encoded: Dictionary = serialize_input_event(event)
	if encoded.is_empty():
		return ERR_INVALID_PARAMETER
	if _settings.is_empty():
		load_settings()
	var controls: Dictionary = _settings.get("controls", {}) as Dictionary
	controls["remaps"] = RemapLogic.swap_conflict(_capture_remaps(), action, encoded)
	_settings["controls"] = controls
	if apply_on_load:
		_apply_controls()
	settings_changed.emit(&"controls")
	return _persist_current_settings()


## Applies every supported setting section to the active Godot runtime.
func apply_all() -> void:
	for section_key: Variant in _settings:
		apply_section(StringName(str(section_key)))


## Applies one setting section; presentation-only values remain available to consumers.
func apply_section(section: StringName) -> void:
	match section:
		&"audio":
			_apply_audio()
		&"video":
			_apply_video()
		&"controls":
			_apply_controls()
		&"accessibility", &"gameplay":
			pass
		_:
			push_warning("Unknown settings section: %s" % String(section))


## Serializes supported key and joypad events into ConfigFile-safe dictionaries.
func serialize_input_event(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		return {
			"type": "key",
			"device": key_event.device,
			"keycode": key_event.keycode,
			"physical_keycode": key_event.physical_keycode,
		}
	if event is InputEventJoypadButton:
		var button_event: InputEventJoypadButton = event as InputEventJoypadButton
		return {"type": "joy_button", "device": button_event.device, "button_index": button_event.button_index}
	if event is InputEventJoypadMotion:
		var motion_event: InputEventJoypadMotion = event as InputEventJoypadMotion
		return {
			"type": "joy_motion",
			"device": motion_event.device,
			"axis": motion_event.axis,
			"axis_value": motion_event.axis_value,
		}
	push_warning("Unsupported input event type: %s" % event.get_class())
	return {}


## Rebuilds a supported InputEvent from serialized remap data.
func deserialize_input_event(data: Dictionary) -> InputEvent:
	var event_type: String = str(data.get("type", ""))
	match event_type:
		"key":
			var key_event: InputEventKey = InputEventKey.new()
			key_event.device = int(data.get("device", -1))
			key_event.keycode = int(data.get("keycode", 0))
			key_event.physical_keycode = int(data.get("physical_keycode", 0))
			return key_event
		"joy_button":
			var button_event: InputEventJoypadButton = InputEventJoypadButton.new()
			button_event.device = int(data.get("device", -1))
			button_event.button_index = int(data.get("button_index", 0))
			return button_event
		"joy_motion":
			var motion_event: InputEventJoypadMotion = InputEventJoypadMotion.new()
			motion_event.device = int(data.get("device", -1))
			motion_event.axis = int(data.get("axis", 0))
			motion_event.axis_value = float(data.get("axis_value", 0.0))
			return motion_event
	push_warning("Unsupported serialized input event type: %s" % event_type)
	return InputEventAction.new()


func _merge_with_defaults(values: Dictionary) -> Dictionary:
	var merged: Dictionary = default_settings()
	for section_key: Variant in values:
		var section: String = str(section_key)
		if not values[section] is Dictionary:
			continue
		if not merged.has(section):
			merged[section] = {}
		var section_values: Dictionary = values[section]
		for setting_key: Variant in section_values:
			merged[section][setting_key] = section_values[setting_key]
	return merged


func _validated_value(value: Variant, fallback: Variant) -> Variant:
	if fallback is float:
		if (value is float or value is int) and is_finite(float(value)):
			return float(value)
		return fallback
	return value if typeof(value) == typeof(fallback) else fallback


func _persist_current_settings() -> Error:
	var config: ConfigFile = ConfigFile.new()
	for section_key: Variant in _settings:
		var section: String = str(section_key)
		var section_values: Dictionary = _settings[section]
		for setting_key: Variant in section_values:
			var key: String = str(setting_key)
			config.set_value(section, key, section_values[key])
	return config.save(settings_path)


func _capture_remaps() -> Dictionary:
	var remaps: Dictionary = {}
	for action: StringName in REMAPPABLE_ACTIONS:
		if not InputMap.has_action(action):
			continue
		var encoded_events: Array[Dictionary] = []
		for event: InputEvent in InputMap.action_get_events(action):
			var encoded: Dictionary = serialize_input_event(event)
			if not encoded.is_empty():
				encoded_events.append(encoded)
		remaps[String(action)] = encoded_events
	return remaps


func _apply_audio() -> void:
	var audio: Dictionary = _settings.get("audio", {})
	AudioManager.ensure_audio_buses()
	for setting_key: Variant in AUDIO_BUS_KEYS:
		var linear: float = clampf(float(audio.get(setting_key, 1.0)), MIN_VOLUME, MAX_VOLUME)
		AudioManager.set_bus_volume(StringName(AUDIO_BUS_KEYS[setting_key]), linear)


func _apply_video() -> void:
	var video: Dictionary = _settings.get("video", {})
	if is_inside_tree():
		get_tree().root.scaling_3d_scale = clampf(
			minf(float(video.get("render_scale", 1.0)), float(QualityTier.settings(int(video.get("particle_quality", 2)))["render_scale"])), MIN_RENDER_SCALE, MAX_RENDER_SCALE,
		)
		get_tree().root.msaa_3d = int(QualityTier.settings(int(video.get("particle_quality", 2)))["msaa"]) as Viewport.MSAA
		QualityTier.apply_scene(get_tree().root, int(video.get("particle_quality", 2)))
	if DisplayServer.get_name() == "headless":
		return
	var fullscreen: bool = bool(video.get("fullscreen", false))
	var mode: DisplayServer.WindowMode = DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	DisplayServer.window_set_mode(mode)
	var resolution_value: Variant = video.get("resolution", Vector2i(1600, 900))
	var resolution: Vector2i = resolution_value if resolution_value is Vector2i else Vector2i(1600, 900)
	if not fullscreen:
		DisplayServer.window_set_size(resolution)
	var vsync_mode: DisplayServer.VSyncMode = DisplayServer.VSYNC_ENABLED if bool(video.get("vsync", true)) else DisplayServer.VSYNC_DISABLED
	DisplayServer.window_set_vsync_mode(vsync_mode)


func _apply_controls() -> void:
	var controls: Dictionary = _settings.get("controls", {})
	var deadzone: float = clampf(float(controls.get("deadzone", 0.2)), 0.0, 1.0)
	for action: StringName in [
		InputActions.ACCELERATE,
		InputActions.BRAKE,
		InputActions.STEER_LEFT,
		InputActions.STEER_RIGHT,
		InputActions.DRIFT,
		InputActions.USE_ITEM,
		InputActions.LOOK_BACK,
	]:
		if InputMap.has_action(action):
			InputMap.action_set_deadzone(action, deadzone)
	var remaps: Dictionary = controls.get("remaps", {})
	for action_key: Variant in remaps:
		var action: StringName = StringName(str(action_key))
		if not InputMap.has_action(action):
			continue
		if not remaps[action_key] is Array:
			push_warning("Invalid remap for %s; existing bindings will be kept." % action)
			continue
		var encoded_events: Array = remaps[action_key]
		var decoded_events: Array[InputEvent] = []
		var valid: bool = true
		for encoded: Variant in encoded_events:
			if not encoded is Dictionary or not _valid_remap(encoded as Dictionary):
				valid = false
				break
			decoded_events.append(deserialize_input_event(encoded as Dictionary))
		if not valid:
			push_warning("Invalid remap for %s; existing bindings will be kept." % action)
			continue
		# Conflict swaps can move the only custom binding away. Restore project
		# defaults rather than keeping the stale binding or leaving the action empty.
		if encoded_events.is_empty():
			var defaults: Dictionary = ProjectSettings.get_setting("input/%s" % action, {})
			decoded_events.assign(defaults.get("events", []))
		InputMap.action_erase_events(action)
		for event: InputEvent in decoded_events:
			InputMap.action_add_event(action, event)


func _valid_remap(data: Dictionary) -> bool:
	if not ["key", "joy_button", "joy_motion"].has(data.get("type")):
		return false
	for key: String in ["device", "keycode", "physical_keycode", "button_index", "axis", "axis_value"]:
		if data.has(key) and not (data[key] is int or data[key] is float):
			return false
		if data.has(key) and not is_finite(float(data[key])):
			return false
	match data["type"]:
		"key":
			return int(data.get("keycode", 0)) > 0 or int(data.get("physical_keycode", 0)) > 0
		"joy_button":
			return int(data.get("button_index", -1)) >= 0
		"joy_motion":
			var axis_value: float = float(data.get("axis_value", 0.0))
			return int(data.get("axis", -1)) >= 0 and absf(axis_value) > 0.0 and absf(axis_value) <= 1.0
	return false
