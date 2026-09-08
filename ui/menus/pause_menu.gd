class_name PauseMenu
extends CanvasLayer

## Temporary focus-first pause overlay; final presentation is Phase 9.

@onready var _continue_button: Button = $Panel/VBox/ContinueButton
@onready var _restart_button: Button = $Panel/VBox/RestartButton
@onready var _menu_button: Button = $Panel/VBox/MenuButton

var _manager: RaceManager


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_continue_button.pressed.connect(_on_continue_pressed)
	_restart_button.pressed.connect(_on_restart_pressed)
	_menu_button.pressed.connect(_on_menu_pressed)
	visible = false


## Displays the overlay and enters keyboard/gamepad focus at Continue.
func show_menu(manager: RaceManager) -> void:
	_manager = manager
	visible = true
	_continue_button.call_deferred("grab_focus")


## Hides the pause overlay without changing race state.
func hide_menu() -> void:
	visible = false


func _on_continue_pressed() -> void:
	if _manager != null:
		_manager.resume_race()


func _on_restart_pressed() -> void:
	if _manager != null:
		visible = false
		_manager.restart()


func _on_menu_pressed() -> void:
	if _manager != null:
		_manager.back_to_menu()

