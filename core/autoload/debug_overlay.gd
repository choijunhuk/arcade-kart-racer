class_name DebugOverlayService
extends CanvasLayer

const F3_KEY: Key = KEY_F3
const SLIDER_WIDTH: float = 180.0
const SLIDER_STEP_COUNT: float = 100.0

@onready var _stats_label: Label = %StatsLabel
@onready var _slider_container: VBoxContainer = %SliderContainer

var _physics_tick: int = 0
var _watches: Dictionary[StringName, Callable] = {}
var _sliders: Dictionary[StringName, Dictionary] = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Spec §6.2: debug overlay is disabled in release builds.
	if not OS.is_debug_build():
		visible = false
		set_process(false)
		set_physics_process(false)
		set_process_unhandled_input(false)


func _physics_process(_delta: float) -> void:
	_physics_tick += 1


func _process(_delta: float) -> void:
	_update_stats()
	_update_sliders()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.physical_keycode == F3_KEY and key_event.pressed and not key_event.echo:
			visible = not visible
			get_viewport().set_input_as_handled()


## Registers or replaces a callable value displayed by the overlay.
func watch(name: StringName, value_getter: Callable) -> void:
	if not value_getter.is_valid():
		push_error("Debug watch requires a valid callable: %s" % String(name))
		return
	_watches[name] = value_getter


## Removes a watched debug value when it is no longer relevant.
func unwatch(name: StringName) -> void:
	_watches.erase(name)


## Removes a runtime tuning slider and its row so a freed scene's getter and
## setter callables are never called again on the next frame.
func remove_slider(name: StringName) -> void:
	if not _sliders.has(name):
		return
	var control: HSlider = _sliders[name]["control"] as HSlider
	if is_instance_valid(control) and is_instance_valid(control.get_parent()):
		control.get_parent().queue_free()
	_sliders.erase(name)


## Adds a runtime tuning slider backed by getter and setter callables.
func add_slider(
	name: StringName,
	minimum: float,
	maximum: float,
	value_getter: Callable,
	value_setter: Callable,
) -> HSlider:
	if not value_getter.is_valid() or not value_setter.is_valid() or maximum <= minimum:
		push_error("Invalid debug slider contract: %s" % String(name))
		return null
	if _sliders.has(name):
		return _sliders[name]["control"] as HSlider
	var slider: HSlider = _create_slider_row(name, minimum, maximum)
	slider.value_changed.connect(_on_slider_changed.bind(name))
	_sliders[name] = {"control": slider, "getter": value_getter, "setter": value_setter}
	return slider


func _create_slider_row(name: StringName, minimum: float, maximum: float) -> HSlider:
	var row: HBoxContainer = HBoxContainer.new()
	var label: Label = Label.new()
	label.text = String(name)
	var slider: HSlider = HSlider.new()
	slider.name = String(name)
	slider.custom_minimum_size.x = SLIDER_WIDTH
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = (maximum - minimum) / SLIDER_STEP_COUNT
	row.add_child(label)
	row.add_child(slider)
	_slider_container.add_child(row)
	return slider


func _update_stats() -> void:
	var lines: PackedStringArray = PackedStringArray([
		"FPS: %d" % int(Engine.get_frames_per_second()),
		"Physics tick: %d" % _physics_tick,
	])
	for watch_name: StringName in _watches:
		var getter: Callable = _watches[watch_name]
		lines.append("%s: %s" % [String(watch_name), str(getter.call())])
	_stats_label.text = "\n".join(lines)


func _update_sliders() -> void:
	for slider_name: StringName in _sliders:
		var entry: Dictionary = _sliders[slider_name]
		var slider: HSlider = entry["control"] as HSlider
		var getter: Callable = entry["getter"]
		slider.set_value_no_signal(float(getter.call()))


func _on_slider_changed(value: float, slider_name: StringName) -> void:
	var entry: Dictionary = _sliders[slider_name]
	var setter: Callable = entry["setter"]
	setter.call(value)
