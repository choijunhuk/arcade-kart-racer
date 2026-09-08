class_name SettingsMenu
extends MenuScreen

const MAIN_MENU_PATH: String = "res://ui/menus/main_menu.tscn"
const REMAP_ROW_SCENE: PackedScene = preload("res://ui/menus/remap_row.tscn")
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
]
const SECTION_NAMES: PackedStringArray = ["AUDIO", "VIDEO", "CONTROLS", "ACCESSIBILITY", "GAMEPLAY"]
const ACTION_LABELS: Dictionary = {
	"accelerate": "Accelerate",
	"brake": "Brake",
	"steer_left": "Steer Left",
	"steer_right": "Steer Right",
	"drift": "Drift",
	"use_item": "Use Item",
	"look_back": "Look Back",
	"pause": "Pause",
	"ui_accept": "Menu Accept",
	"ui_cancel": "Menu Back",
	"ui_left": "Menu Left",
	"ui_right": "Menu Right",
	"ui_up": "Menu Up",
	"ui_down": "Menu Down",
}

@onready var _section_picker: OptionButton = $Panel/VBox/SectionPicker
@onready var _tabs: TabContainer = $Panel/VBox/Tabs
@onready var _remap_rows_root: VBoxContainer = $Panel/VBox/Tabs/Controls/Scroll/Rows/RemapRows
@onready var _back_button: Button = $Panel/VBox/BackButton

var _remap_rows: Array[RemapRow] = []
var _embedded: bool = false
var _closed_callback: Callable
var _syncing: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	super._ready()
	_populate_options()
	_build_remap_rows()
	_connect_controls()
	_sync_values()
	_wire_current_section_focus()
	if visible:
		focus_initial(_section_picker)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") and not _is_remapping():
		UiAudio.play_back()
		_close()
		get_viewport().set_input_as_handled()


## Opens this shared screen inside PauseMenu without unpausing the race tree.
func open_embedded(closed_callback: Callable) -> void:
	_embedded = true
	_closed_callback = closed_callback
	visible = true
	_sync_values()
	focus_initial(_section_picker)


func _populate_options() -> void:
	for section_name: String in SECTION_NAMES:
		_section_picker.add_item(section_name)
	var resolution_option: OptionButton = $Panel/VBox/Tabs/Video/ResolutionOption
	for resolution: Vector2i in RESOLUTIONS:
		resolution_option.add_item("%d × %d" % [resolution.x, resolution.y])
		resolution_option.set_item_metadata(resolution_option.item_count - 1, resolution)
	var particle_option: OptionButton = $Panel/VBox/Tabs/Video/ParticleQualityOption
	for quality_name: String in ["LOW", "MEDIUM", "HIGH"]:
		particle_option.add_item(quality_name)


func _build_remap_rows() -> void:
	for action: StringName in SettingsManagerService.REMAPPABLE_ACTIONS:
		var row: RemapRow = REMAP_ROW_SCENE.instantiate() as RemapRow
		_remap_rows_root.add_child(row)
		row.configure(action, str(ACTION_LABELS.get(String(action), String(action))))
		row.remap_requested.connect(_on_remap_requested)
		_remap_rows.append(row)


func _connect_controls() -> void:
	_section_picker.item_selected.connect(_on_section_selected)
	_back_button.pressed.connect(_close)
	_connect_toggle($Panel/VBox/Tabs/Audio/FinalLapPitchToggle, &"audio", &"final_lap_pitch")
	_connect_slider($Panel/VBox/Tabs/Audio/MasterSlider, &"audio", &"master")
	_connect_slider($Panel/VBox/Tabs/Audio/MusicSlider, &"audio", &"music")
	_connect_slider($Panel/VBox/Tabs/Audio/SfxSlider, &"audio", &"sfx")
	_connect_slider($Panel/VBox/Tabs/Audio/EngineSlider, &"audio", &"engine")
	_connect_slider($Panel/VBox/Tabs/Video/RenderScaleSlider, &"video", &"render_scale")
	_connect_slider($Panel/VBox/Tabs/Video/ShakeSlider, &"gameplay", &"shake_strength")
	_connect_slider($Panel/VBox/Tabs/Video/FovSlider, &"gameplay", &"fov_effect_strength")
	_connect_slider($Panel/VBox/Tabs/Controls/Scroll/Rows/DeadzoneSlider, &"controls", &"deadzone")
	_connect_slider($Panel/VBox/Tabs/Controls/Scroll/Rows/SensitivitySlider, &"controls", &"steering_sensitivity")
	_connect_toggle($Panel/VBox/Tabs/Video/FullscreenToggle, &"video", &"fullscreen")
	_connect_toggle($Panel/VBox/Tabs/Video/VsyncToggle, &"video", &"vsync")
	_connect_toggle($Panel/VBox/Tabs/Controls/Scroll/Rows/VibrationToggle, &"controls", &"vibration")
	# TODO(phase-13): Route enabled vibration to event-owned controller haptics.
	_connect_toggle($Panel/VBox/Tabs/Accessibility/SpeedLinesToggle, &"accessibility", &"speed_lines")
	_connect_toggle($Panel/VBox/Tabs/Accessibility/TierIconsToggle, &"accessibility", &"drift_tier_icons")
	_connect_toggle($Panel/VBox/Tabs/Gameplay/SpeedometerToggle, &"gameplay", &"speedometer")
	($Panel/VBox/Tabs/Video/ResolutionOption as OptionButton).item_selected.connect(_on_resolution_selected)
	($Panel/VBox/Tabs/Video/ParticleQualityOption as OptionButton).item_selected.connect(_on_particle_quality_selected)


func _connect_slider(slider: HSlider, section: StringName, key: StringName) -> void:
	slider.value_changed.connect(_on_float_changed.bind(section, key))


func _connect_toggle(toggle: CheckButton, section: StringName, key: StringName) -> void:
	toggle.toggled.connect(_on_bool_changed.bind(section, key))


func _sync_values() -> void:
	_syncing = true
	_set_toggle($Panel/VBox/Tabs/Audio/FinalLapPitchToggle, &"audio", &"final_lap_pitch", true)
	_set_slider($Panel/VBox/Tabs/Audio/MasterSlider, &"audio", &"master", 1.0)
	_set_slider($Panel/VBox/Tabs/Audio/MusicSlider, &"audio", &"music", 1.0)
	_set_slider($Panel/VBox/Tabs/Audio/SfxSlider, &"audio", &"sfx", 1.0)
	_set_slider($Panel/VBox/Tabs/Audio/EngineSlider, &"audio", &"engine", 1.0)
	_set_slider($Panel/VBox/Tabs/Video/RenderScaleSlider, &"video", &"render_scale", 1.0)
	_set_slider($Panel/VBox/Tabs/Video/ShakeSlider, &"gameplay", &"shake_strength", 100.0)
	_set_slider($Panel/VBox/Tabs/Video/FovSlider, &"gameplay", &"fov_effect_strength", 100.0)
	_set_slider($Panel/VBox/Tabs/Controls/Scroll/Rows/DeadzoneSlider, &"controls", &"deadzone", 0.2)
	_set_slider($Panel/VBox/Tabs/Controls/Scroll/Rows/SensitivitySlider, &"controls", &"steering_sensitivity", 1.0)
	_set_toggle($Panel/VBox/Tabs/Video/FullscreenToggle, &"video", &"fullscreen", false)
	_set_toggle($Panel/VBox/Tabs/Video/VsyncToggle, &"video", &"vsync", true)
	_set_toggle($Panel/VBox/Tabs/Controls/Scroll/Rows/VibrationToggle, &"controls", &"vibration", true)
	_set_toggle($Panel/VBox/Tabs/Accessibility/SpeedLinesToggle, &"accessibility", &"speed_lines", true)
	_set_toggle($Panel/VBox/Tabs/Accessibility/TierIconsToggle, &"accessibility", &"drift_tier_icons", true)
	_set_toggle($Panel/VBox/Tabs/Gameplay/SpeedometerToggle, &"gameplay", &"speedometer", true)
	var resolution_value: Variant = SettingsManager.get_setting(&"video", &"resolution", Vector2i(1600, 900))
	var resolution: Vector2i = resolution_value if resolution_value is Vector2i else Vector2i(1600, 900)
	_select_resolution(resolution)
	($Panel/VBox/Tabs/Video/ParticleQualityOption as OptionButton).select(int(SettingsManager.get_setting(&"video", &"particle_quality", 2)))
	for row: RemapRow in _remap_rows:
		row.refresh_binding()
	_syncing = false


func _set_slider(slider: HSlider, section: StringName, key: StringName, fallback: float) -> void:
	slider.set_value_no_signal(float(SettingsManager.get_setting(section, key, fallback)))


func _set_toggle(toggle: CheckButton, section: StringName, key: StringName, fallback: bool) -> void:
	toggle.set_pressed_no_signal(bool(SettingsManager.get_setting(section, key, fallback)))


func _select_resolution(resolution: Vector2i) -> void:
	var option: OptionButton = $Panel/VBox/Tabs/Video/ResolutionOption
	for index: int in range(option.item_count):
		if option.get_item_metadata(index) == resolution:
			option.select(index)
			return


func _on_section_selected(index: int) -> void:
	_tabs.current_tab = index
	_wire_current_section_focus.call_deferred()


func _on_float_changed(value: float, section: StringName, key: StringName) -> void:
	if not _syncing:
		SettingsManager.update_setting(section, key, value)


func _on_bool_changed(value: bool, section: StringName, key: StringName) -> void:
	if not _syncing:
		SettingsManager.update_setting(section, key, value)


func _on_resolution_selected(index: int) -> void:
	if not _syncing:
		var option: OptionButton = $Panel/VBox/Tabs/Video/ResolutionOption
		SettingsManager.update_setting(&"video", &"resolution", option.get_item_metadata(index))


func _on_particle_quality_selected(index: int) -> void:
	if not _syncing:
		SettingsManager.update_setting(&"video", &"particle_quality", index)


func _on_remap_requested(action: StringName, event: InputEvent) -> void:
	SettingsManager.remap_action(action, event)
	for row: RemapRow in _remap_rows:
		row.refresh_binding()


func _is_remapping() -> bool:
	for row: RemapRow in _remap_rows:
		if row.is_listening():
			return true
	return false


func _wire_current_section_focus() -> void:
	var controls: Array[Control] = [_section_picker]
	_collect_focusable(_tabs.get_child(_tabs.current_tab), controls)
	controls.append(_back_button)
	wire_vertical_focus(controls)


func _collect_focusable(node: Node, controls: Array[Control]) -> void:
	for child: Node in node.get_children():
		if child is Control:
			var control: Control = child as Control
			if control.focus_mode != Control.FOCUS_NONE and control.is_visible_in_tree():
				controls.append(control)
		_collect_focusable(child, controls)


func _close() -> void:
	if _embedded:
		visible = false
		_embedded = false
		if _closed_callback.is_valid():
			_closed_callback.call()
		return
	go_to(MAIN_MENU_PATH)
