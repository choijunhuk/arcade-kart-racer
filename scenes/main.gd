class_name MainMenuPlaceholder
extends Node

## Minimal Phase 5 entry screen. Full menus and selection are Phase 9.
## TODO(phase-9): Replace with driver/kart/track selection menus.

const RACE_SCENE_PATH: String = "res://race/race.tscn"
const DEFAULT_TRACK: TrackData = preload("res://data/tracks/track_01.tres")
const DEFAULT_KART: KartData = preload("res://data/karts/medium.tres")
const DEFAULT_LAPS: int = 3
const DEFAULT_KART_COUNT: int = 8

@onready var _start_button: Button = $Center/VBox/StartButton


func _ready() -> void:
	GameState.current_mode = GameState.Mode.MENU
	_start_button.pressed.connect(start_race)
	_start_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if is_start_event(event):
		start_race()
		get_viewport().set_input_as_handled()


## Accepts keyboard/gamepad confirm and the gamepad Start (`pause`) action.
func is_start_event(event: InputEvent) -> bool:
	return event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"pause")


## Builds the default Track 01, 3-lap, 8-kart medium configuration.
func build_default_config() -> RaceConfig:
	var config: RaceConfig = RaceConfig.new()
	config.track = DEFAULT_TRACK
	config.laps = DEFAULT_LAPS
	config.kart_count = DEFAULT_KART_COUNT
	config.player_kart = DEFAULT_KART
	config.player_slot = 0
	return config


## Stores the pending config and enters the race scene.
func start_race() -> void:
	GameState.pending_race_config = build_default_config()
	GameState.current_mode = GameState.Mode.RACE
	GameState.change_scene(RACE_SCENE_PATH)
