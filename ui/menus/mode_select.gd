class_name ModeSelectMenu
extends MenuScreen

const DRIVER_SELECT_PATH: String = "res://ui/menus/driver_select.tscn"

@onready var _single_race_button: Button = $Panel/VBox/SingleRaceButton
@onready var _back_button: Button = $Panel/VBox/BackButton


func _ready() -> void:
	super._ready()
	_single_race_button.pressed.connect(go_to.bind(DRIVER_SELECT_PATH))
	_back_button.pressed.connect(go_back)
	wire_vertical_focus([_single_race_button, _back_button])
	focus_initial(_single_race_button)
