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
var _back: Button
var _upnp_status: Label
var _upnp: NetUpnp
var _relay_client: NetRelayClient
var _drivers: Array[Resource] = []
var _karts: Array[Resource] = []
var _tracks: Array[Resource] = []
var _difficulties: Array[Resource] = []
var _laps: SpinBox
var _ai_count_box: SpinBox
var _track: OptionButton
var _difficulty: OptionButton
var _panels: Array[LocalLobby.PanelView] = []
## True from a JOIN attempt until the server's handshake actually admits us
## (a roster row appears): the ENet socket opens instantly, but "Connected"
## before the password/version check finishes is misleading — a peer that
## gets rejected a moment later would have seen a UI claiming success.
var _awaiting_handshake: bool = false

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
	_host = OnlineLobbyWidgets.button(controls, "HOST", _host_game)
	_join = OnlineLobbyWidgets.button(controls, "JOIN", _join_game)
	_drivers = ResourceScanner.scan_tres(LocalLobby.DRIVER_DIRECTORY)
	_karts = ResourceScanner.scan_tres(LocalLobby.KART_DIRECTORY)
	_driver = OnlineLobbyWidgets.options(controls, _drivers)
	_kart = OnlineLobbyWidgets.options(controls, _karts)
	_ready_button = OnlineLobbyWidgets.button(controls, "READY", _toggle_ready)
	_start = OnlineLobbyWidgets.button(controls, "START", _start_race)
	_back = OnlineLobbyWidgets.button(controls, "BACK", go_back)
	_driver.item_selected.connect(_selection_changed)
	_kart.item_selected.connect(_selection_changed)
	_build_relay_row()
	_build_status_row()
	_build_race_options_row()
	_wire_focus()
	for index: int in range(NetTuning.MAX_PLAYERS):
		var panel: LocalLobby.PanelView = LocalLobby.create_panel(index)
		panel.panel.custom_minimum_size.y = 220.0
		_grid.add_child(panel.panel)
		_panels.append(panel)
	_refresh()
	focus_initial(_host)
	if is_instance_valid(GameState.net_session):
		_rebind_session(GameState.net_session)

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
	_copy_button = OnlineLobbyWidgets.button(row, "COPY CODE", _copy_host_code)
	_copy_button.disabled = true
	_upnp_status = Label.new()
	row.add_child(_upnp_status)

## Host-only race options (spec item 1): laps, AI bot count, track and difficulty.
## Editable before/while hosting; clients see the host's broadcast values read-only.
func _build_race_options_row() -> void:
	var row: HBoxContainer = HBoxContainer.new()
	_rows.add_child(row)
	_rows.move_child(row, 5)
	OnlineLobbyWidgets.row_label(row, "LAPS")
	_laps = SpinBox.new()
	_laps.min_value = 1
	_laps.max_value = 9
	_laps.value = 1
	_laps.value_changed.connect(_on_race_options_changed)
	row.add_child(_laps)
	OnlineLobbyWidgets.row_label(row, "BOTS")
	_ai_count_box = SpinBox.new()
	_ai_count_box.min_value = 0
	_ai_count_box.max_value = RaceSnapshot.MAX_KARTS - 1
	_ai_count_box.value = 6
	_ai_count_box.value_changed.connect(_on_race_options_changed)
	row.add_child(_ai_count_box)
	OnlineLobbyWidgets.row_label(row, "TRACK")
	_tracks = ResourceScanner.scan_tres(NetContentCatalog.TRACK_DIRECTORY)
	_track = OnlineLobbyWidgets.options(row, _tracks)
	_track.item_selected.connect(_on_race_options_changed)
	OnlineLobbyWidgets.row_label(row, "DIFFICULTY")
	_difficulties = ResourceScanner.scan_tres(NetContentCatalog.AI_DIRECTORY)
	_difficulty = OnlineLobbyWidgets.options(row, _difficulties)
	_difficulty.item_selected.connect(_on_race_options_changed)

## Explicit gamepad focus: up/down walks every row in reading order (wrapping),
## left/right wraps within a row, so no control is a dead end (Phase 18k item 19).
func _wire_focus() -> void:
	OnlineLobbyWidgets.wire_rows_focus(self, [
		[_ip, _port, _password, _host, _join, _driver, _kart, _ready_button, _start, _back],
		[_relay_target, _room_code], [_copy_button], [_laps, _ai_count_box, _track, _difficulty],
	])

## Host-only: pushes the current controls onto the (now server) session and rebroadcasts the lobby; a no-op on a client or before a session exists.
func _on_race_options_changed(_value: Variant = null) -> void:
	if _session == null or not multiplayer.is_server():
		return
	_session.set_race_options(
		int(_laps.value), int(_ai_count_box.value),
		String(_tracks[_track.selected].get("id")), String(_difficulties[_difficulty.selected].get("id")),
	)

## Closes the connection; any UPnP mapping releases itself once the session
## actually closes (see `_start_upnp`), which `_session.close()` triggers.
func go_back() -> void:
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
	_session.admitted.connect(_on_admitted)

## Re-enters an already-open session, e.g. `ResultsScreen`'s "BACK TO LOBBY"
## (spec item 3): reuses the still-alive NetSession instead of creating a
## new one, so the roster/settings the server already broadcast still apply.
## This is also the first point at which the lobby scene is genuinely active
## again after `GameState.change_scene()`'s fade, so it — not
## `NetSession.restart_to_lobby()` — is what reopens the ENet listener to new
## connections (closes the lobby-reopen connection window; see
## NetSession.reopen_connections()).
func _rebind_session(session: NetSession) -> void:
	_session = session
	if not _session.lobby_changed.is_connected(_refresh):
		_session.lobby_changed.connect(_refresh)
	if not _session.admitted.is_connected(_on_admitted):
		_session.admitted.connect(_on_admitted)
	_session.reopen_connections()
	_awaiting_handshake = false
	_status.text = "Connected — choose driver/kart, then READY. Host starts."
	_refresh()

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
	if error != OK:
		return
	_on_race_options_changed()
	if relay_target.is_empty():
		_start_upnp(port)
	else:
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
		_handle_open(_session.join("127.0.0.1", loopback_port, _password.text), true)
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
	_handle_open(_session.join(target, port, _password.text), true)

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
	# Owned by the persistent GameState, not this lobby: START frees the lobby
	# through the race scene change while discovery can still be running
	# (measured ~11 s with no IGD), and freeing NetUpnp with the lobby joined
	# that worker on the main thread, starving ENet until the joined peer
	# timed the host out. Its lifetime is tied to the session rather than to
	# this lobby screen: `tree_exiting` fires whenever `NetSession.close()`
	# runs, from BACK here, LEAVE RACE, END SESSION, or app teardown, so the
	# router mapping is released exactly once, however the session ends,
	# instead of only from `go_back()` (finding: UPnP mapping outlives the
	# session, leaking one worker/mapping per HOST press). Release stays
	# fire-and-forget — see `NetUpnp.release_and_free()`'s own doc comment.
	GameState.add_child(_upnp)
	_upnp.mapping_finished.connect(_on_upnp_finished.bind(port))
	_bind_upnp_release(_upnp)
	_upnp.map_port(port)

## Split out of `_start_upnp` so tests can exercise the release-on-close
## wiring without running real UPnP network discovery.
func _bind_upnp_release(upnp: NetUpnp) -> void:
	if not _session.tree_exiting.is_connected(upnp.release_and_free):
		_session.tree_exiting.connect(upnp.release_and_free)

func _on_upnp_finished(result: Dictionary, port: int) -> void:
	if String(result.get("status", "")) == "mapped":
		var code: String = NetJoinCode.encode(String(result.get("external_ip", "")), port)
		_host_code_label.text = "HOST CODE: %s" % code
		_upnp_status.text = "UPnP mapped — share the code above."
		_copy_button.disabled = code.is_empty()
	else:
		_upnp_status.text = NetUpnp.status_message(result, port)

func _copy_host_code() -> void:
	var code: String = _host_code_label.text.replace("HOST CODE: ", "")
	if not code.is_empty() and DisplayServer.get_name() != "headless":
		DisplayServer.clipboard_set(code)

## `verifying` marks a JOIN attempt: the socket is open but the server has
## not yet accepted our handshake, so the status must not claim "Connected"
## until a roster row for us actually appears (see `_awaiting_handshake`).
func _handle_open(error: Error, verifying: bool = false) -> void:
	if error != OK:
		_session.close()
		_session = null
		_status.text = "Connection failed: %s" % error_string(error)
	elif verifying:
		_awaiting_handshake = true
		_status.text = "Connecting — verifying handshake…"
	else:
		_status.text = "Connected — choose driver/kart, then READY. Host starts."
	_refresh()

## Server-side admission confirmation (net_session.gd `_admitted`): a peer
## joining mid-race gets no roster row until the next lobby, so `_refresh`'s
## `local_slot() >= 0` check alone would leave this stuck on "verifying
## handshake" for the whole race.
func _on_admitted(waiting: bool) -> void:
	_awaiting_handshake = false
	if waiting:
		_status.text = "Admitted — waiting for the current race to finish."
	else:
		_status.text = "Connected — choose driver/kart, then READY. Host starts."

func _refresh() -> void:
	var connected: bool = is_instance_valid(_session)
	if _awaiting_handshake and connected and _session.local_slot() >= 0:
		_awaiting_handshake = false
		_status.text = "Connected — choose driver/kart, then READY. Host starts."
	_host.disabled = connected
	_join.disabled = connected
	# Review finding 7: while `started`, `_selection` is dropped server-side — READY and the dropdowns that also send it must disable together.
	var mid_race: bool = connected and _session.started
	var selection_disabled: bool = not connected or _session.local_slot() < 0 or mid_race
	_ready_button.disabled = selection_disabled
	_driver.disabled = selection_disabled
	_kart.disabled = selection_disabled
	if mid_race:
		_status.text = "Waiting for the host to reopen the lobby."
	_start.disabled = not connected or not multiplayer.is_server()
	_refresh_race_options(connected)
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
			view.driver.text = "DRIVER  " + OnlineLobbyWidgets.display_name(_drivers, row["driver"])
			view.kart.text = "KART  " + OnlineLobbyWidgets.display_name(_karts, row["kart"])
			view.status.text = "READY" if bool(row["ready"]) else "CHOOSING"

## Reflects the session's current laps/bots/track/difficulty into the
## controls and gates editing to the host (spec item 1: clients see the
## host's choice but cannot change it).
func _refresh_race_options(connected: bool) -> void:
	var editable: bool = not connected or multiplayer.is_server()
	if connected:
		# Dropdowns first, and *_no_signal for the spin boxes (review finding
		# 5): `Range.value =` emits `value_changed` synchronously, so setting
		# it before the dropdowns caught `_on_race_options_changed` mid-resync
		# — e.g. the host's rebind after BACK TO LOBBY — while the dropdowns
		# still read index 0, broadcasting track_01 + easy + the stale bot
		# count over the host's real choice.
		OnlineLobbyWidgets.select_option(_track, _tracks, _session.track_id, String(LocalLobby.DEFAULT_TRACK.id))
		OnlineLobbyWidgets.select_option(_difficulty, _difficulties, _session.difficulty_id, String(LocalLobby.DEFAULT_DIFFICULTY.id))
		_laps.set_value_no_signal(_session.laps)
		_ai_count_box.set_value_no_signal(_session.ai_count)
	_laps.editable = editable
	_ai_count_box.editable = editable
	_track.disabled = not editable
	_difficulty.disabled = not editable

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
