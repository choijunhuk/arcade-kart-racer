class_name DifficultySelectMenu
extends MenuScreen

const DRIVER_DIRECTORY: String = "res://data/drivers"
const KART_DIRECTORY: String = "res://data/karts"
const TRACK_DIRECTORY: String = "res://data/tracks"
const DIFFICULTY_DIRECTORY: String = "res://data/ai"
const RACE_SCENE_PATH: String = "res://race/race.tscn"
const SPEED_CLASS_ORDER: Array[RaceConfig.SpeedClass] = [
	RaceConfig.SpeedClass.CRUISE, RaceConfig.SpeedClass.STANDARD, RaceConfig.SpeedClass.TURBO,
]

@onready var _difficulty_list: VBoxContainer = $Panel/VBox/DifficultyList
@onready var _back_button: Button = $Panel/VBox/BackButton
@onready var _items_toggle: CheckButton = $Panel/VBox/ItemsToggle
@onready var _speed_class_option: OptionButton = $Panel/VBox/SpeedClassOption
@onready var _mirror_toggle: CheckButton = $Panel/VBox/MirrorToggle

var _buttons: Array[Control] = []


func _ready() -> void:
	super._ready()
	var time_trial: bool = GameState.selected_race_mode == RaceConfig.RaceMode.TIME_TRIAL
	_items_toggle.button_pressed = GameState.selected_items_enabled and not time_trial
	_items_toggle.disabled = time_trial
	_items_toggle.text = "ITEMS OFF • TIME TRIAL" if time_trial else "ITEMS ENABLED"
	_setup_speed_class_option(time_trial)
	_mirror_toggle.button_pressed = bool(SettingsManager.get_setting(&"gameplay", &"mirror", false))
	if GameState.selected_race_mode == RaceConfig.RaceMode.GRAND_PRIX:
		back_scene_path = "res://ui/menus/kart_select.tscn"
		$Panel/VBox/Title.text = "HORIZON CUP • 4 RACES"
	_build_difficulty_list()
	_back_button.pressed.connect(go_back)
	if not _buttons.is_empty():
		var focus_controls: Array[Control] = _buttons.duplicate()
		focus_controls.append(_speed_class_option)
		focus_controls.append(_mirror_toggle)
		if not time_trial:
			focus_controls.append(_items_toggle)
		focus_controls.append(_back_button)
		wire_vertical_focus(focus_controls)
		focus_initial(_buttons[0])


## Populates the class picker and restores/forces the remembered choice
## (spec §18e); time trial always races STANDARD for fair record comparison.
func _setup_speed_class_option(time_trial: bool) -> void:
	for speed_class: RaceConfig.SpeedClass in SPEED_CLASS_ORDER:
		_speed_class_option.add_item(SpeedClassStats.display_name(speed_class))
	var stored: int = int(SettingsManager.get_setting(&"gameplay", &"speed_class", RaceConfig.SpeedClass.STANDARD))
	var stored_index: int = SPEED_CLASS_ORDER.find(stored)
	_speed_class_option.select(stored_index if stored_index >= 0 else SPEED_CLASS_ORDER.find(RaceConfig.SpeedClass.STANDARD))
	if time_trial:
		_speed_class_option.select(SPEED_CLASS_ORDER.find(RaceConfig.SpeedClass.STANDARD))
	_speed_class_option.disabled = time_trial


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
	var chosen_class: RaceConfig.SpeedClass = SPEED_CLASS_ORDER[_speed_class_option.selected]
	GameState.pending_race_config = RaceConfigBuilder.build(driver, kart, track, difficulty)
	GameState.pending_race_config.race_mode = GameState.selected_race_mode
	GameState.pending_race_config.speed_class = chosen_class
	GameState.selected_speed_class = chosen_class
	GameState.selected_items_enabled = _items_toggle.button_pressed
	GameState.pending_race_config.items_enabled = GameState.selected_items_enabled
	GameState.pending_race_config.mirror = _mirror_toggle.button_pressed
	RaceConfigBuilder.normalize(GameState.pending_race_config)
	if not _speed_class_option.disabled:
		SettingsManager.update_setting(&"gameplay", &"speed_class", chosen_class)
	SettingsManager.update_setting(&"gameplay", &"mirror", _mirror_toggle.button_pressed)
	if GameState.selected_race_mode == RaceConfig.RaceMode.GRAND_PRIX:
		var tracks: Array[TrackData] = []
		for resource: Resource in ResourceScanner.scan_tres(TRACK_DIRECTORY):
			if resource is TrackData:
				tracks.append(resource as TrackData)
		GameState.grand_prix_state = GrandPrix.new()
		GameState.grand_prix_state.setup(GameState.pending_race_config, tracks)
		GameState.pending_race_config = GameState.grand_prix_state.current_config()
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
