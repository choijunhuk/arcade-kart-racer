class_name TrackSelectMenu
extends MenuScreen

const TRACK_DIRECTORY: String = "res://data/tracks"
const DIFFICULTY_SELECT_PATH: String = "res://ui/menus/difficulty_select.tscn"
const NO_RECORD_TEXT: String = "--:--.---"
const TRACK_BUTTON_SIZE: Vector2 = Vector2(860.0, 92.0)
const THUMBNAIL_WIDTH: int = 150
const MILLISECONDS_PER_MINUTE: int = 60_000
const MILLISECONDS_PER_SECOND: int = 1_000
const SECONDS_PER_MINUTE: int = 60

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
		focus_initial(first_focusable(_buttons))


func _build_track_list() -> void:
	var save_data: Dictionary = SaveManager.load_data()
	for resource: Resource in ResourceScanner.scan_tres(TRACK_DIRECTORY):
		if not resource is TrackData:
			continue
		var track: TrackData = resource as TrackData
		var button: Button = Button.new()
		button.custom_minimum_size = TRACK_BUTTON_SIZE
		button.theme_type_variation = &"CardButton"
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.icon = load("res://assets/previews/%s.png" % track.id) as Texture2D
		button.expand_icon = true
		button.add_theme_constant_override(&"icon_max_width", THUMBNAIL_WIDTH)
		button.add_theme_constant_override(&"h_separation", 22)
		var best_lap_ms: int = SaveManager.get_best_lap_ms(track.id)
		button.text = "%s\n%d LAPS  •  BEST %s" % [
			track.display_name,
			track.laps_default,
			_format_milliseconds(best_lap_ms),
		]
		if lock_if_locked(button, "track", String(track.id), save_data):
			button.text = "%s  •  LOCKED\n%s" % [track.display_name, UnlockRules.locked_hint("track", String(track.id))]
		button.pressed.connect(_select_track.bind(track))
		button.focus_entered.connect(_preview_track.bind(track))
		button.mouse_entered.connect(_preview_track.bind(track))
		_track_list.add_child(button)
		_buttons.append(button)


func _select_track(track: TrackData) -> void:
	GameState.selected_track_id = track.id
	go_to(DIFFICULTY_SELECT_PATH)


func _format_milliseconds(milliseconds: int) -> String:
	if milliseconds < 0:
		return NO_RECORD_TEXT
	var minutes: int = milliseconds / MILLISECONDS_PER_MINUTE
	var seconds: int = (milliseconds / MILLISECONDS_PER_SECOND) % SECONDS_PER_MINUTE
	var remainder: int = milliseconds % MILLISECONDS_PER_SECOND
	return "%02d:%02d.%03d" % [minutes, seconds, remainder]


func _preview_track(track: TrackData) -> void:
	($Panel/VBox/Preview as TextureRect).texture = load("res://assets/previews/%s.png" % track.id) as Texture2D
