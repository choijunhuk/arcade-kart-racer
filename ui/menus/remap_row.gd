class_name RemapRow
extends HBoxContainer

signal remap_requested(action: StringName, event: InputEvent)

const AXIS_CAPTURE_THRESHOLD: float = 0.5
const LISTENING_TEXT: String = "PRESS KEY / BUTTON / AXIS"
const UNBOUND_TEXT: String = "UNBOUND"

var action: StringName = &""
var _listening: bool = false


func _ready() -> void:
	($BindButton as Button).pressed.connect(_start_listening)
	set_process_input(false)


func _input(event: InputEvent) -> void:
	if not _listening:
		return
	var captured: InputEvent = _normalized_capture(event)
	if captured == null:
		return
	_listening = false
	set_process_input(false)
	($BindButton as Button).text = captured.as_text()
	remap_requested.emit(action, captured)
	get_viewport().set_input_as_handled()


## Assigns the action label and displays its current first binding.
func configure(action_name: StringName, display_name: String) -> void:
	action = action_name
	($ActionLabel as Label).text = display_name
	refresh_binding()


## Refreshes the displayed binding after a conflict swap.
func refresh_binding() -> void:
	var events: Array[InputEvent] = InputMap.action_get_events(action)
	($BindButton as Button).text = events[0].as_text() if not events.is_empty() else UNBOUND_TEXT


## Returns whether this row currently owns raw input capture.
func is_listening() -> bool:
	return _listening


func _start_listening() -> void:
	_listening = true
	($BindButton as Button).text = LISTENING_TEXT
	set_process_input(true)


func _normalized_capture(event: InputEvent) -> InputEvent:
	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		return key_event if key_event.pressed and not key_event.echo else null
	if event is InputEventJoypadButton:
		var button_event: InputEventJoypadButton = event as InputEventJoypadButton
		return button_event if button_event.pressed else null
	if event is InputEventJoypadMotion:
		var motion_event: InputEventJoypadMotion = event as InputEventJoypadMotion
		if absf(motion_event.axis_value) < AXIS_CAPTURE_THRESHOLD:
			return null
		var normalized: InputEventJoypadMotion = InputEventJoypadMotion.new()
		normalized.device = motion_event.device
		normalized.axis = motion_event.axis
		normalized.axis_value = signf(motion_event.axis_value)
		return normalized
	return null
