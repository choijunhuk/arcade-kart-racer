class_name OnlineLobby
extends MenuScreen

## LAN lobby with shared player panels and server-owned ready/selection state.
@onready var _rows: VBoxContainer = $Panel/VBox
@onready var _grid: GridContainer = $Panel/VBox/Players
@onready var _status: Label = $Panel/VBox/Footer
var _session: NetSession
var _ip: LineEdit
var _port: SpinBox
var _host: Button
var _join: Button
var _ready_button: Button
var _start: Button
var _driver: OptionButton
var _kart: OptionButton
var _drivers: Array[Resource] = []
var _karts: Array[Resource] = []
var _panels: Array[LocalLobby.PanelView] = []

func _ready() -> void:
	super._ready()
	back_scene_path = "res://scenes/main.tscn"
	var controls: HBoxContainer = HBoxContainer.new()
	_rows.add_child(controls)
	_rows.move_child(controls, 2)
	_ip = LineEdit.new()
	_ip.text = "127.0.0.1"
	_ip.placeholder_text = "Host LAN IP"
	_ip.custom_minimum_size.x = 200.0
	controls.add_child(_ip)
	_port = SpinBox.new()
	_port.min_value = 1024
	_port.max_value = 65535
	_port.value = NetTuning.PORT
	controls.add_child(_port)
	_host = _button(controls, "HOST", _host_game)
	_join = _button(controls, "JOIN", _join_game)
	_drivers = ResourceScanner.scan_tres(LocalLobby.DRIVER_DIRECTORY)
	_karts = ResourceScanner.scan_tres(LocalLobby.KART_DIRECTORY)
	_driver = _options(controls, _drivers)
	_kart = _options(controls, _karts)
	_ready_button = _button(controls, "READY", _toggle_ready)
	_start = _button(controls, "START", _start_race)
	_button(controls, "BACK", go_back)
	_driver.item_selected.connect(_selection_changed)
	_kart.item_selected.connect(_selection_changed)
	for index: int in range(NetTuning.MAX_PLAYERS):
		var panel: LocalLobby.PanelView = LocalLobby.create_panel(index)
		panel.panel.custom_minimum_size.y = 220.0
		_grid.add_child(panel.panel)
		_panels.append(panel)
	_refresh()
	focus_initial(_host)

## Closes the connection before leaving so peers receive disconnect notification.
func go_back() -> void:
	if _session != null:
		_session.close()
	super.go_back()

func _create_session() -> void:
	_session = NetSession.new()
	_session.name = "NetSession"
	GameState.net_session = _session
	GameState.add_child(_session)
	_session.lobby_changed.connect(_refresh)

func _host_game() -> void:
	_create_session()
	var error: Error = _session.host(int(_port.value))
	_handle_open(error)

func _join_game() -> void:
	_create_session()
	_handle_open(_session.join(_ip.text.strip_edges(), int(_port.value)))

func _handle_open(error: Error) -> void:
	if error != OK:
		_session.close()
		_session = null
		_status.text = "Connection failed: %s" % error_string(error)
	else:
		_status.text = "Connected — choose driver/kart, then READY. Host starts."
	_refresh()

func _refresh() -> void:
	var connected: bool = is_instance_valid(_session)
	_host.disabled = connected
	_join.disabled = connected
	_ready_button.disabled = not connected or _session.local_slot() < 0
	_start.disabled = not connected or not multiplayer.is_server()
	var roster: Array[Dictionary] = _session.players if connected else [] as Array[Dictionary]
	for index: int in range(_panels.size()):
		var view: LocalLobby.PanelView = _panels[index]
		var joined: bool = index < roster.size()
		view.device.visible = joined
		view.driver.visible = joined
		view.kart.visible = joined
		view.status.text = "WAITING FOR PLAYER"
		if joined:
			var row: Dictionary = roster[index]
			view.device.text = "HOST" if int(row["peer"]) == NetSession.SERVER_ID else "PLAYER"
			view.driver.text = "DRIVER  " + _display(_drivers, row["driver"])
			view.kart.text = "KART  " + _display(_karts, row["kart"])
			view.status.text = "READY" if bool(row["ready"]) else "CHOOSING"

func _selection_changed(_index: int) -> void:
	_send_selection(false)

func _toggle_ready() -> void:
	var local: int = _session.local_slot()
	if local >= 0:
		_send_selection(not bool(_session.players[local]["ready"]))

func _send_selection(ready: bool) -> void:
	if _session != null and _session.local_slot() >= 0:
		_session.select(String(_drivers[_driver.selected].get("id")), String(_karts[_kart.selected].get("id")), ready)

func _start_race() -> void:
	if not _session.start_race():
		_status.text = "At least 2 players must be READY."

func _button(parent: Control, text: String, action: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _options(parent: Control, resources: Array[Resource]) -> OptionButton:
	var options: OptionButton = OptionButton.new()
	for resource: Resource in resources:
		options.add_item(String(resource.get("display_name")))
	parent.add_child(options)
	return options

func _display(resources: Array[Resource], id: String) -> String:
	for resource: Resource in resources:
		if String(resource.get("id")) == id:
			return String(resource.get("display_name"))
	return id
