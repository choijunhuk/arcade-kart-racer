class_name ModeSelectMenu
extends MenuScreen

const DRIVER_SELECT_PATH: String = "res://ui/menus/driver_select.tscn"
const LOCAL_LOBBY_PATH: String = "res://ui/menus/local_lobby.tscn"

@onready var _single_race_button: Button = $Panel/VBox/SingleRaceButton
@onready var _grand_prix_button: Button = $Panel/VBox/GrandPrixButton
@onready var _local_multiplayer_button: Button = $Panel/VBox/LocalMultiplayerButton
@onready var _back_button: Button = $Panel/VBox/BackButton


func _ready() -> void:
	super._ready()
	_single_race_button.pressed.connect(_select_mode.bind(RaceConfig.RaceMode.SINGLE_RACE))
	_grand_prix_button.pressed.connect(_select_mode.bind(RaceConfig.RaceMode.GRAND_PRIX))
	_local_multiplayer_button.pressed.connect(go_to.bind(LOCAL_LOBBY_PATH))
	_back_button.pressed.connect(go_back)
	wire_vertical_focus([_single_race_button, _grand_prix_button, _local_multiplayer_button, _back_button])
	focus_initial(_single_race_button)


func _select_mode(mode: RaceConfig.RaceMode) -> void:
	GameState.selected_race_mode = mode
	GameState.grand_prix_state = null
	go_to(DRIVER_SELECT_PATH)
