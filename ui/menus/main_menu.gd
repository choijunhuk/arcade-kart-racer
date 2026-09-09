class_name MainMenu
extends MenuScreen

const MODE_SELECT_PATH: String = "res://ui/menus/mode_select.tscn"
const SETTINGS_PATH: String = "res://ui/menus/settings_menu.tscn"

@onready var _play_button: Button = $Panel/VBox/PlayButton
@onready var _time_trial_button: Button = $Panel/VBox/TimeTrialButton
@onready var _settings_button: Button = $Panel/VBox/SettingsButton
@onready var _quit_button: Button = $Panel/VBox/QuitButton


func _ready() -> void:
	super._ready()
	GameState.reset_session()
	GameState.current_mode = GameState.Mode.MENU
	_play_button.pressed.connect(go_to.bind(MODE_SELECT_PATH))
	_time_trial_button.pressed.connect(_start_time_trial)
	_settings_button.pressed.connect(go_to.bind(SETTINGS_PATH))
	_quit_button.pressed.connect(_quit_game)
	wire_vertical_focus([_play_button, _time_trial_button, _settings_button, _quit_button])
	focus_initial(_play_button)


func _quit_game() -> void:
	get_tree().quit()


func _start_time_trial() -> void:
	GameState.selected_race_mode = RaceConfig.RaceMode.TIME_TRIAL
	go_to("res://ui/menus/driver_select.tscn")
