class_name OnlineLobby
extends MenuScreen

## Online lobby: LAN or internet host/join, UPnP auto port-forward with a
## shareable host code, an optional session password, an optional relay
## proxy for double-NAT hosts, and shared player panels/ready/selection.
@onready var _rows: VBoxContainer = $Panel/VBox
@onready var _grid: GridContainer = $Panel/VBox/Players
@onready var _status: Label = $Panel/VBox/Footer
var _session: NetSession
var _ip: LineEdit
var _port: SpinBox
var _password: LineEdit
var _host: Button
var _join: Button
var _ready_button: Button
var _start: Button
var _driver: OptionButton
var _kart: OptionButton
var _relay_target: LineEdit
var _room_code: LineEdit
var _host_code_label: Label
var _copy_button: Button
var _upnp_status: Label
var _upnp: NetUpnp
var _relay_client: NetRelayClient
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
	_ip.placeholder_text = "Host IP or join code"
	_ip.custom_minimum_size.x = 220.0
	controls.add_child(_ip)
	_port = SpinBox.new()
	_port.min_value = 1024
	_port.max_value = 65533
	_port.value = NetTuning.PORT
	controls.add_child(_port)
	_password = LineEdit.new()
	_password.placeholder_text = "Password (optional)"
	_password.secret = true
	_password.custom_minimum_size.x = 160.0
	controls.add_child(_password)
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
	_build_relay_row()
	_build_status_row()
	for index: int in range(NetTuning.MAX_PLAYERS):
		var panel: LocalLobby.PanelView = LocalLobby.create_panel(index)
		panel.panel.custom_minimum_size.y = 220.0
		_grid.add_child(panel.panel)
		_panels.append(panel)
	_refresh()
	focus_initial(_host)

func _build_relay_row() -> void:
	var row: HBoxContainer = HBoxContainer.new()
	_rows.add_child(row)
	_rows.move_child(row, 3)
	_relay_target = LineEdit.new()
	_relay_target.placeholder_text = "Use relay ip:port (double-NAT, optional)"
	_relay_target.custom_minimum_size.x = 260.0
	row.add_child(_relay_target)
	_room_code = LineEdit.new()
	_room_code.placeholder_text = "Relay room code"
	_room_code.custom_minimum_size.x = 160.0
	row.add_child(_room_code)

func _build_status_row() -> void:
	var row: HBoxContainer = HBoxContainer.new()
	_rows.add_child(row)
	_rows.move_child(row, 4)
	_host_code_label = Label.new()
	row.add_child(_host_code_label)
	_copy_button = _button(row, "COPY CODE", _copy_host_code)
	_copy_button.disabled = true
	_upnp_status = Label.new()
	row.add_child(_upnp_status)

## Closes the connection and releases any UPnP mapping/relay proxy before leaving.
func go_back() -> void:
	if _upnp != null:
		_upnp.release_and_free()
		_upnp = null
	if _relay_client != null:
		_relay_client.stop()
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
	_session.set_password(_password.text)
	var port: int = int(_port.value)
	var relay_target: String = _relay_target.text.strip_edges()
	if not relay_target.is_empty() and not _start_relay_client(port + 1, port, relay_target, _room_code.text.strip_edges()):
		_session.close()
		_session = null
		return
	var error: Error = _session.host(port)
	_handle_open(error)
	if error == OK and relay_target.is_empty():
		_start_upnp(port)
	elif error == OK:
		_upnp_status.text = "Relay active — share the room code with your guest."

func _join_game() -> void:
	_create_session()
	var target: String = _ip.text.strip_edges()
	var port: int = int(_port.value)
	var relay_target: String = _relay_target.text.strip_edges()
	if not relay_target.is_empty():
		var loopback_port: int = port + 1
		if not _start_relay_client(loopback_port, 0, relay_target, _room_code.text.strip_edges()):
			_session.close()
			_session = null
			return
		_handle_open(_session.join("127.0.0.1", loopback_port, _password.text))
		return
	if NetJoinCode.looks_like_code(target):
		var decoded: Dictionary = NetJoinCode.decode(target)
		if decoded.is_empty():
			_session.close()
			_session = null
			_status.text = "Invalid join code."
			_refresh()
			return
		target = String(decoded["ip"])
		port = int(decoded["port"])
	elif target.find(":") >= 0:
		var parts: PackedStringArray = target.split(":")
		target = parts[0]
		if parts.size() > 1 and parts[1].is_valid_int():
			port = int(parts[1])
	_handle_open(_session.join(target, port, _password.text))

func _start_relay_client(loopback_port: int, dial_target_port: int, relay_target: String, room_code: String) -> bool:
	var parts: PackedStringArray = relay_target.split(":")
	if parts.size() != 2 or not parts[1].is_valid_int() or room_code.is_empty():
		_status.text = "Relay needs ip:port and a room code."
		return false
	_relay_client = NetRelayClient.new()
	add_child(_relay_client)
	var error: Error = _relay_client.start(loopback_port, dial_target_port, parts[0], int(parts[1]), room_code)
	if error != OK:
		_status.text = "Relay proxy failed to start: %s" % error_string(error)
		_relay_client.queue_free()
		_relay_client = null
		return false
	return true

func _start_upnp(port: int) -> void:
	_host_code_label.text = ""
	_copy_button.disabled = true
	_upnp_status.text = "Mapping port via UPnP…"
	_upnp = NetUpnp.new()
	add_child(_upnp)
	_upnp.mapping_finished.connect(_on_upnp_finished.bind(port))
	_upnp.map_port(port)

func _on_upnp_finished(result: Dictionary, port: int) -> void:
	if String(result.get("status", "")) == "mapped":
		var code: String = NetJoinCode.encode(String(result.get("external_ip", "")), port)
		_host_code_label.text = "HOST CODE: %s" % code
		_upnp_status.text = "UPnP mapped — share the code above."
		_copy_button.disabled = code.is_empty()
	else:
		_upnp_status.text = "UPnP unavailable — forward UDP port %d manually." % port

func _copy_host_code() -> void:
	var code: String = _host_code_label.text.replace("HOST CODE: ", "")
	if not code.is_empty() and DisplayServer.get_name() != "headless":
		DisplayServer.clipboard_set(code)

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
	var roster: Array[Dictionary] = []
	if connected:
		roster = _session.players
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
