class_name PlayerInputProvider
extends InputProvider

const DEVICE_KEYBOARD: int = -1
const DEVICE_ANY: int = DEVICE_KEYBOARD
const INPUT_MIN: float = 0.0
const INPUT_MAX: float = 1.0
const BUTTON_THRESHOLD: float = 0.5
const PHYSICS_TICKS_PER_SECOND: float = 60.0
const STEER_SMOOTHING_PER_SECOND: float = 8.0
const STEER_STEP: float = STEER_SMOOTHING_PER_SECOND / PHYSICS_TICKS_PER_SECOND
const MIN_STEERING_SENSITIVITY: float = 0.5
const MAX_STEERING_SENSITIVITY: float = 2.0

var device_id: int = DEVICE_ANY

var _strength_override: Callable = Callable()
var _smoothed_steer: float = 0.0
var _previous_drift: bool = false
var _previous_item: bool = false
var _tick: int = 0


func _init(player_device_id: int = DEVICE_ANY) -> void:
	device_id = player_device_id


## Installs a deterministic `(action, device_id) -> float` source for tests or replays.
func set_strength_override(strength_source: Callable) -> void:
	_strength_override = strength_source


## Clears the injected source and resumes reading Godot's Input singleton.
func clear_strength_override() -> void:
	_strength_override = Callable()


## Builds one smoothed, edge-aware input snapshot for the next physics tick.
func get_frame() -> InputFrame:
	_tick += 1
	var frame: InputFrame = InputFrame.new()
	frame.throttle = _get_strength(InputActions.ACCELERATE)
	frame.brake = _get_strength(InputActions.BRAKE)
	var steer_target: float = _get_strength(InputActions.STEER_RIGHT) - _get_strength(InputActions.STEER_LEFT)
	var sensitivity: float = clampf(
		float(SettingsManager.get_setting(&"controls", &"steering_sensitivity", 1.0)),
		MIN_STEERING_SENSITIVITY,
		MAX_STEERING_SENSITIVITY,
	)
	_smoothed_steer = move_toward(_smoothed_steer, steer_target, STEER_STEP * sensitivity)
	frame.steer = _smoothed_steer
	frame.drift = _get_strength(InputActions.DRIFT) > BUTTON_THRESHOLD
	frame.drift_pressed = frame.drift and not _previous_drift
	var item_held: bool = _get_strength(InputActions.USE_ITEM) > BUTTON_THRESHOLD
	frame.item = item_held and not _previous_item
	frame.look_back = _get_strength(InputActions.LOOK_BACK) > BUTTON_THRESHOLD
	frame.tick = _tick
	_previous_drift = frame.drift
	_previous_item = item_held
	return frame


func _get_strength(action: StringName) -> float:
	if _strength_override.is_valid():
		return clampf(float(_strength_override.call(action, device_id)), INPUT_MIN, INPUT_MAX)
	if device_id == DEVICE_KEYBOARD:
		return _get_keyboard_strength(action)
	return _get_joypad_strength(action)


func _get_keyboard_strength(action: StringName) -> float:
	for event: InputEvent in InputMap.action_get_events(action):
		if not event is InputEventKey:
			continue
		var key_event: InputEventKey = event as InputEventKey
		if key_event.physical_keycode > 0 and Input.is_physical_key_pressed(key_event.physical_keycode):
			return INPUT_MAX
		if key_event.keycode > 0 and Input.is_key_pressed(key_event.keycode):
			return INPUT_MAX
	return INPUT_MIN


func _get_joypad_strength(action: StringName) -> float:
	var strongest: float = 0.0
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventJoypadButton:
			var button_event: InputEventJoypadButton = event as InputEventJoypadButton
			if Input.is_joy_button_pressed(device_id, button_event.button_index):
				strongest = INPUT_MAX
		elif event is InputEventJoypadMotion:
			var motion_event: InputEventJoypadMotion = event as InputEventJoypadMotion
			var axis_value: float = Input.get_joy_axis(device_id, motion_event.axis)
			if signf(axis_value) == signf(motion_event.axis_value):
				strongest = maxf(strongest, absf(axis_value))
	return strongest
