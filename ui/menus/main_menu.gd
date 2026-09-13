class_name MainMenu
extends MenuScreen

const MODE_SELECT_PATH: String = "res://ui/menus/mode_select.tscn"
const SETTINGS_PATH: String = "res://ui/menus/settings_menu.tscn"
const KART_DIRECTORY: String = "res://data/karts"

@onready var _play_button: Button = $Panel/VBox/PlayButton
@onready var _time_trial_button: Button = $Panel/VBox/TimeTrialButton
@onready var _online_button: Button = $Panel/VBox/OnlineButton
@onready var _settings_button: Button = $Panel/VBox/SettingsButton
@onready var _quit_button: Button = $Panel/VBox/QuitButton
@onready var _orbit_kart: KartPreview = $OrbitKart


func _ready() -> void:
	super._ready()
	GameState.reset_session()
	GameState.current_mode = GameState.Mode.MENU
	_show_orbit_kart()
	_play_button.pressed.connect(go_to.bind(MODE_SELECT_PATH))
	_time_trial_button.pressed.connect(_start_time_trial)
	_settings_button.pressed.connect(go_to.bind(SETTINGS_PATH))
	_online_button.pressed.connect(go_to.bind("res://ui/menus/online_lobby.tscn"))
	($Panel/VBox/NetworkMessage as Label).text = GameState.network_message
	GameState.network_message = ""
	_quit_button.pressed.connect(_quit_game)
	wire_vertical_focus([_play_button, _time_trial_button, _online_button, _settings_button, _quit_button])
	focus_initial(_play_button)


func _quit_game() -> void:
	get_tree().quit()


## Showcases the first cataloged kart, slowly orbiting behind the panel.
func _show_orbit_kart() -> void:
	var karts: Array[Resource] = ResourceScanner.scan_tres(KART_DIRECTORY)
	if karts.is_empty():
		return
	_orbit_kart.show_kart(karts[0] as KartData)


func _start_time_trial() -> void:
	GameState.selected_race_mode = RaceConfig.RaceMode.TIME_TRIAL
	go_to("res://ui/menus/driver_select.tscn")
