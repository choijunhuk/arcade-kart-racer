class_name LocalLobby
extends MenuScreen

## Device-owned four-panel lobby with independent driver/kart cursors.

class PanelView extends RefCounted:
	var panel: PanelContainer
	var title: Label
	var device: Label
	var driver: Label
	var kart: Label
	var status: Label


const DRIVER_DIRECTORY: String = "res://data/drivers"
const KART_DIRECTORY: String = "res://data/karts"
const RACE_SCENE_PATH: String = "res://race/race.tscn"
const DEFAULT_TRACK: TrackData = preload("res://data/tracks/track_01.tres")
const DEFAULT_DIFFICULTY: AIDifficultyProfile = preload("res://data/ai/normal.tres")
const DEFAULT_KART_COUNT: int = 8
const PANEL_SIZE: Vector2 = Vector2(560.0, 300.0)
const SELECT_DRIVER: int = 0
const SELECT_KART: int = 1

@onready var _grid: GridContainer = $Panel/VBox/Players

var _drivers: Array[DriverData] = []
var _karts: Array[KartData] = []
var _state: LocalLobbyState
var _panels: Array[PanelView] = []
var _selection_rows: Dictionary[int, int] = {}


func _ready() -> void:
	super._ready()
	_load_content()
	_state = LocalLobbyState.new(_drivers[0].id, _karts[0].id)
	for player_index: int in range(LocalLobbyState.MAX_PLAYERS):
		var panel: PanelView = _create_panel(player_index)
		_panels.append(panel)
		_grid.add_child(panel.panel)
	_refresh_panels()


func _unhandled_input(event: InputEvent) -> void:
	var device_id: int = _event_device_id(event)
	var player_index: int = _state.player_index_for_device(device_id)
	if player_index < 0:
		if event.is_action_pressed(&"ui_accept"):
			join_device(device_id)
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed(&"ui_cancel") and _state.players().is_empty():
			go_back()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"ui_cancel"):
		if _state.is_ready(device_id):
			set_player_ready(device_id, false)
		else:
			_state.leave(device_id)
			_selection_rows.erase(device_id)
			_refresh_panels()
	elif event.is_action_pressed(&"ui_accept"):
		set_player_ready(device_id, not _state.is_ready(device_id))
	elif not _state.is_ready(device_id) and event.is_action_pressed(&"ui_up"):
		_selection_rows[device_id] = SELECT_DRIVER
		_refresh_panels()
	elif not _state.is_ready(device_id) and event.is_action_pressed(&"ui_down"):
		_selection_rows[device_id] = SELECT_KART
		_refresh_panels()
	elif not _state.is_ready(device_id) and event.is_action_pressed(&"ui_left"):
		_cycle_selection(device_id, -1)
	elif not _state.is_ready(device_id) and event.is_action_pressed(&"ui_right"):
		_cycle_selection(device_id, 1)
	else:
		return
	get_viewport().set_input_as_handled()


## Joins a keyboard or joypad and refreshes its independent panel.
func join_device(device_id: int) -> bool:
	var joined: bool = _state.join(device_id)
	if joined:
		_selection_rows[device_id] = SELECT_DRIVER
		_refresh_panels()
	return joined


## Sets one device ready and starts immediately once every joined player is ready.
func set_player_ready(device_id: int, ready: bool) -> bool:
	if not _state.set_ready(device_id, ready):
		return false
	_refresh_panels()
	if _state.can_start():
		_start_race()
	return true


func _load_content() -> void:
	for resource: Resource in ResourceScanner.scan_tres(DRIVER_DIRECTORY):
		if resource is DriverData:
			_drivers.append(resource as DriverData)
	for resource: Resource in ResourceScanner.scan_tres(KART_DIRECTORY):
		if resource is KartData:
			_karts.append(resource as KartData)
	if _drivers.is_empty() or _karts.is_empty():
		push_error("Local lobby requires at least one driver and kart")


func _create_panel(player_index: int) -> PanelView:
	var view: PanelView = PanelView.new()
	view.panel = PanelContainer.new()
	view.panel.name = "Player%dPanel" % (player_index + 1)
	view.panel.custom_minimum_size = PANEL_SIZE
	var rows: VBoxContainer = VBoxContainer.new()
	rows.add_theme_constant_override("separation", 12)
	view.panel.add_child(rows)
	view.title = _label(rows, "P%d" % (player_index + 1), 32)
	view.device = _label(rows, "", 18)
	view.driver = _label(rows, "", 24)
	view.kart = _label(rows, "", 24)
	view.status = _label(rows, "PRESS A / ENTER TO JOIN", 20)
	return view


func _label(parent: Control, text: String, font_size: int) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _refresh_panels() -> void:
	var slots: Array[PlayerSlot] = _state.players()
	for index: int in range(_panels.size()):
		var view: PanelView = _panels[index]
		var joined: bool = index < slots.size()
		view.device.visible = joined
		view.driver.visible = joined
		view.kart.visible = joined
		if not joined:
			view.status.text = "PRESS A / ENTER TO JOIN"
			continue
		var slot: PlayerSlot = slots[index]
		var selected_row: int = int(_selection_rows.get(slot.device_id, SELECT_DRIVER))
		view.device.text = "KEYBOARD" if slot.device_id == PlayerSlot.KEYBOARD_DEVICE_ID else "GAMEPAD %d" % (slot.device_id + 1)
		view.driver.text = "%s DRIVER  %s" % ["▶" if selected_row == SELECT_DRIVER else " ", _driver(slot.driver_id).display_name]
		view.kart.text = "%s KART    %s" % ["▶" if selected_row == SELECT_KART else " ", _kart(slot.kart_id).display_name]
		view.status.text = "READY — B TO EDIT" if _state.is_ready(slot.device_id) else "A / ENTER: READY"


func _cycle_selection(device_id: int, direction: int) -> void:
	var slots: Array[PlayerSlot] = _state.players()
	var slot: PlayerSlot = slots[_state.player_index_for_device(device_id)]
	if int(_selection_rows.get(device_id, SELECT_DRIVER)) == SELECT_DRIVER:
		var driver_index: int = _index_of_driver(slot.driver_id)
		slot.driver_id = _drivers[posmod(driver_index + direction, _drivers.size())].id
	else:
		var kart_index: int = _index_of_kart(slot.kart_id)
		slot.kart_id = _karts[posmod(kart_index + direction, _karts.size())].id
	_state.set_selection(device_id, slot.driver_id, slot.kart_id)
	_refresh_panels()


func _start_race() -> void:
	var slots: Array[PlayerSlot] = _state.players()
	var config: RaceConfig = RaceConfigBuilder.build_local(slots, DEFAULT_TRACK, DEFAULT_DIFFICULTY, DEFAULT_KART_COUNT)
	GameState.pending_race_config = config
	GameState.selected_race_mode = RaceConfig.RaceMode.LOCAL_MULTIPLAYER
	GameState.selected_driver_id = slots[0].driver_id
	GameState.selected_kart_id = slots[0].kart_id
	GameState.selected_track_id = DEFAULT_TRACK.id
	GameState.current_mode = GameState.Mode.RACE
	SaveManager.save_last_selection(slots[0].driver_id, slots[0].kart_id, DEFAULT_TRACK.id)
	go_to(RACE_SCENE_PATH)


func _driver(id: StringName) -> DriverData:
	return _drivers[_index_of_driver(id)]


func _kart(id: StringName) -> KartData:
	return _karts[_index_of_kart(id)]


func _index_of_driver(id: StringName) -> int:
	for index: int in range(_drivers.size()):
		if _drivers[index].id == id:
			return index
	return 0


func _index_of_kart(id: StringName) -> int:
	for index: int in range(_karts.size()):
		if _karts[index].id == id:
			return index
	return 0


func _event_device_id(event: InputEvent) -> int:
	return PlayerSlot.KEYBOARD_DEVICE_ID if event is InputEventKey else event.device
