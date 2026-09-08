class_name TrackSelectMenu
extends MenuScreen

const TRACK_DIRECTORY: String = "res://data/tracks"
const DIFFICULTY_SELECT_PATH: String = "res://ui/menus/difficulty_select.tscn"
const NO_RECORD_TEXT: String = "--:--.---"

@onready var _track_list: VBoxContainer = $Panel/VBox/TrackList
@onready var _back_button: Button = $Panel/VBox/BackButton

var _buttons: Array[Control] = []


func _ready() -> void:
	super._ready()
	_build_track_list()
	_back_button.pressed.connect(go_back)
	if not _buttons.is_empty():
		var focus_controls: Array[Control] = _buttons.duplicate()
		focus_controls.append(_back_button)
		wire_vertical_focus(focus_controls)
		focus_initial(_buttons[0])


func _build_track_list() -> void:
	for resource: Resource in ResourceScanner.scan_tres(TRACK_DIRECTORY):
		if not resource is TrackData:
			continue
		var track: TrackData = resource as TrackData
		var button: Button = Button.new()
		button.custom_minimum_size = Vector2(720.0, 150.0)
		var best_lap_ms: int = SaveManager.get_best_lap_ms(track.id)
		button.text = "%s\n%d LAPS  •  BEST %s" % [
			track.display_name,
			track.laps_default,
			_format_milliseconds(best_lap_ms),
		]
		button.pressed.connect(_select_track.bind(track))
		_track_list.add_child(button)
		_buttons.append(button)


func _select_track(track: TrackData) -> void:
	GameState.selected_track_id = track.id
	go_to(DIFFICULTY_SELECT_PATH)


func _format_milliseconds(milliseconds: int) -> String:
	if milliseconds < 0:
		return NO_RECORD_TEXT
	var minutes: int = milliseconds / 60_000
	var seconds: int = (milliseconds / 1_000) % 60
	var remainder: int = milliseconds % 1_000
	return "%02d:%02d.%03d" % [minutes, seconds, remainder]
