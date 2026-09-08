class_name PauseMenu
extends CanvasLayer

## Final focus-first pause overlay with embedded persistent settings.

@onready var _continue_button: Button = $Panel/VBox/ContinueButton
@onready var _restart_button: Button = $Panel/VBox/RestartButton
@onready var _settings_button: Button = $Panel/VBox/SettingsButton
@onready var _menu_button: Button = $Panel/VBox/MenuButton
@onready var _panel: PanelContainer = $Panel
@onready var _settings_menu: SettingsMenu = $SettingsMenu

var _manager: RaceManager


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	UiAudio.attach(_panel)
	_continue_button.pressed.connect(_on_continue_pressed)
	_restart_button.pressed.connect(_on_restart_pressed)
	_settings_button.pressed.connect(_on_settings_pressed)
	_menu_button.pressed.connect(_on_menu_pressed)
	_wire_focus()
	_settings_menu.visible = false
	visible = false


## Owns the pause toggle so it keeps working while the SceneTree is paused;
## RaceManager and its gameplay children stay PAUSABLE (spec §6.1 rule 2).
func _unhandled_input(event: InputEvent) -> void:
	if _manager == null or not event.is_action_pressed(&"pause"):
		return
	if _manager.get_state() == RaceState.PAUSED:
		_manager.resume_race()
	else:
		_manager.pause_race()
	get_viewport().set_input_as_handled()


## Attaches the owning race manager so pause can be toggled before the
## overlay is first shown.
func bind(manager: RaceManager) -> void:
	_manager = manager


## Displays the overlay and enters keyboard/gamepad focus at Continue.
func show_menu(manager: RaceManager) -> void:
	_manager = manager
	visible = true
	_panel.visible = true
	_settings_menu.visible = false
	_continue_button.call_deferred("grab_focus")


## Hides the pause overlay without changing race state.
func hide_menu() -> void:
	visible = false
	_settings_menu.visible = false


func _on_continue_pressed() -> void:
	if _manager != null:
		_manager.resume_race()


func _on_restart_pressed() -> void:
	if _manager != null:
		visible = false
		_manager.restart()


func _on_settings_pressed() -> void:
	_panel.visible = false
	_settings_menu.open_embedded(_on_settings_closed)


func _on_settings_closed() -> void:
	_panel.visible = true
	_continue_button.call_deferred("grab_focus")


func _wire_focus() -> void:
	var buttons: Array[Button] = [_continue_button, _restart_button, _settings_button, _menu_button]
	for index: int in range(buttons.size()):
		var previous: Button = buttons[(index - 1 + buttons.size()) % buttons.size()]
		var next: Button = buttons[(index + 1) % buttons.size()]
		buttons[index].focus_neighbor_top = buttons[index].get_path_to(previous)
		buttons[index].focus_neighbor_bottom = buttons[index].get_path_to(next)


func _on_menu_pressed() -> void:
	if _manager != null:
		_manager.back_to_menu()
