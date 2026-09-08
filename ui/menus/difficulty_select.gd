class_name DifficultySelectMenu
extends MenuScreen

const DRIVER_DIRECTORY: String = "res://data/drivers"
const KART_DIRECTORY: String = "res://data/karts"
const TRACK_DIRECTORY: String = "res://data/tracks"
const DIFFICULTY_DIRECTORY: String = "res://data/ai"
const RACE_SCENE_PATH: String = "res://race/race.tscn"

@onready var _difficulty_list: VBoxContainer = $Panel/VBox/DifficultyList
@onready var _back_button: Button = $Panel/VBox/BackButton

var _buttons: Array[Control] = []


func _ready() -> void:
	super._ready()
	_build_difficulty_list()
	_back_button.pressed.connect(go_back)
	if not _buttons.is_empty():
		var focus_controls: Array[Control] = _buttons.duplicate()
		focus_controls.append(_back_button)
		wire_vertical_focus(focus_controls)
		focus_initial(_buttons[0])


func _build_difficulty_list() -> void:
	for resource: Resource in ResourceScanner.scan_tres(DIFFICULTY_DIRECTORY):
		if not resource is AIDifficultyProfile:
			continue
		var difficulty: AIDifficultyProfile = resource as AIDifficultyProfile
		var button: Button = Button.new()
		button.text = difficulty.display_name
		button.pressed.connect(_start_race.bind(difficulty))
		_difficulty_list.add_child(button)
		_buttons.append(button)


func _start_race(difficulty: AIDifficultyProfile) -> void:
	var driver: DriverData = _find_resource(DRIVER_DIRECTORY, GameState.selected_driver_id) as DriverData
	var kart: KartData = _find_resource(KART_DIRECTORY, GameState.selected_kart_id) as KartData
	var track: TrackData = _find_resource(TRACK_DIRECTORY, GameState.selected_track_id) as TrackData
	if driver == null or kart == null or track == null:
		push_error("Race selections could not be resolved from data directories")
		return
	GameState.pending_race_config = RaceConfigBuilder.build(driver, kart, track, difficulty)
	SaveManager.save_last_selection(driver.id, kart.id, track.id)
	GameState.current_mode = GameState.Mode.RACE
	go_to(RACE_SCENE_PATH)


func _find_resource(directory: String, resource_id: StringName) -> Resource:
	var resources: Array[Resource] = ResourceScanner.scan_tres(directory)
	for resource: Resource in resources:
		if StringName(str(resource.get("id"))) == resource_id:
			return resource
	if resources.is_empty():
		return null
	push_warning(
		"Resource id '%s' was not found in %s; using the first available resource."
		% [String(resource_id), directory],
	)
	return resources[0]
