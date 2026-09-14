class_name OnlineUiDriver
extends Node

## Real-UI acceptance harness (.omc/online_ui_brief.md): drives the actual
## game scenes exactly as a human would — main menu -> ONLINE button ->
## online lobby -> HOST/JOIN -> driver/kart selection -> READY -> (host)
## START -> race -> results — by finding real Control nodes and emitting
## their `pressed`/`item_selected` signals. No --net-host/--net-join
## bypass: that CLI path skips the lobby UI entirely, which is exactly what
## let a previous regression through headless testing while real play broke.
##
## usage:
##   godot --headless --path . res://scenes/test/online_ui_driver.tscn -- \
##     --role host|join --ip 127.0.0.1 --port 24990 --code-file /tmp/code.txt \
##     [--scenario wrong-password|host-leaves]
##
## Host writes "ip:port" to --code-file once hosting succeeds (UPnP cannot
## mint a real routable code on loopback/LAN test hardware; ip:port is the
## brief's documented fallback and is itself a supported join-field format).
## Join waits for that file, pastes its contents into the join field, and
## presses JOIN — real join-field parsing, not a synthetic connect.
##
## Prints `ONLINE_UI step=<name> ok|fail detail=...` per step and a final
## `ONLINE_UI_RESULT {"role":..,"reached_results":bool,"karts":n,"errors":[..]}`.

const MAIN_SCENE_PATH: String = "res://scenes/main.tscn"
const OVERALL_TIMEOUT_SECONDS: float = 200.0
const LOBBY_TIMEOUT_SECONDS: float = 15.0
const JOIN_ROSTER_TIMEOUT_SECONDS: float = 90.0
const RACE_TIMEOUT_SECONDS: float = 90.0
const CODE_FILE_TIMEOUT_SECONDS: float = 120.0
const REJECTION_TIMEOUT_SECONDS: float = 30.0
const WRONG_PASSWORD_HOST: String = "harness-host-secret"
const WRONG_PASSWORD_JOIN: String = "harness-wrong-guess"

var _role: String = "host"
var _ip: String = "127.0.0.1"
var _port: int = NetTuning.PORT
var _code_file: String = ""
var _scenario: String = ""
var _errors: Array[String] = []
var _started_at: float = 0.0
var _finished: bool = false


func _ready() -> void:
	GameState.automation_mode = true
	_parse_args()
	_started_at = NetSession.now()
	# The engine is still finishing its own add_child of this node into
	# `get_tree().root` while `_ready()` runs; adding main.tscn to root in
	# the same call fails with "Parent node is busy setting up children".
	await get_tree().process_frame
	_drive()


func _process(_delta: float) -> void:
	if not _finished and NetSession.now() - _started_at > OVERALL_TIMEOUT_SECONDS:
		_fail("watchdog_timeout", "harness exceeded %.0fs overall budget" % OVERALL_TIMEOUT_SECONDS)


func _parse_args() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var index: int = 0
	while index < args.size():
		var key: String = args[index]
		var value: String = args[index + 1] if index + 1 < args.size() else ""
		match key:
			"--role":
				_role = value
			"--ip":
				_ip = value
			"--port":
				_port = int(value)
			"--code-file":
				_code_file = value
			"--scenario":
				_scenario = value
		index += 2


func _drive() -> void:
	if _code_file.is_empty():
		_fail("parse_args", "--code-file is required")
		return
	if _role != "host" and _role != "join":
		_fail("parse_args", "--role must be host or join, got %s" % _role)
		return

	var main_scene: Node = (load(MAIN_SCENE_PATH) as PackedScene).instantiate()
	get_tree().root.add_child(main_scene)
	get_tree().current_scene = main_scene

	var online_button: Button = main_scene.get_node_or_null("MainMenu/Panel/VBox/OnlineButton") as Button
	if online_button == null:
		_fail("find_online_button", "node not found: MainMenu/Panel/VBox/OnlineButton")
		return
	_ok("boot_main_menu")

	online_button.pressed.emit()
	_ok("press_online")

	var lobby: Node = await _wait_for_current_scene_named("OnlineLobby", LOBBY_TIMEOUT_SECONDS)
	if lobby == null:
		_fail("reach_lobby", "current_scene never became OnlineLobby within %.0fs" % LOBBY_TIMEOUT_SECONDS)
		return
	_ok("reach_lobby")

	var controls: Dictionary = OnlineUiControls.collect(lobby)
	if not String(controls.get("missing", "")).is_empty():
		_fail("find_lobby_controls", "node not found: %s" % controls["missing"])
		return
	_ok("find_lobby_controls")

	if _role == "host":
		await _run_host(controls)
	else:
		await _run_join(controls)


## ---- host role -------------------------------------------------------

func _run_host(c: Dictionary) -> void:
	if _scenario == "wrong-password":
		(c["password"] as LineEdit).text = WRONG_PASSWORD_HOST
	(c["port"] as SpinBox).value = float(_port)

	(c["host"] as Button).pressed.emit()
	await get_tree().process_frame
	var session: NetSession = GameState.net_session
	if session == null:
		_fail("press_host", "session missing after HOST press; status=%s" % _status_text(c))
		return
	_ok("press_host", _status_text(c))

	var code: String = "%s:%d" % [_ip, _port]
	var write_error: Error = _write_code_file(code)
	if write_error != OK:
		_fail("write_code_file", "could not write %s: %s" % [_code_file, error_string(write_error)])
		return
	_ok("write_code_file", code)

	if _scenario == "host-leaves":
		var joined: bool = await _await_condition(func() -> bool:
			return is_instance_valid(session) and session.players.size() >= 2, JOIN_ROSTER_TIMEOUT_SECONDS)
		if not joined:
			_fail("wait_for_join", "second player never appeared in roster within %.0fs" % JOIN_ROSTER_TIMEOUT_SECONDS)
			return
		_ok("wait_for_join")
		(c["back"] as Button).pressed.emit()
		_ok("host_leaves")
		_finish(false, 0)
		return

	if _scenario == "wrong-password":
		# Rejection happens server-side inside the handshake RPC; nothing to
		# press here — just confirm the bad peer never earned a roster row.
		await _await_condition(func() -> bool:
			return not is_instance_valid(session) or session.players.size() != 1, 10.0)
		var still_alone: bool = is_instance_valid(session) and session.players.size() == 1
		if still_alone:
			_ok("confirm_rejected_serverside")
		else:
			_fail("confirm_rejected_serverside", "roster grew past 1 despite wrong password")
			return
		_finish(false, 0)
		return

	_select_and_ready(c)
	_ok("select_driver_kart")
	(c["ready"] as Button).pressed.emit()
	_ok("press_ready")

	var all_ready: bool = await _await_condition(func() -> bool:
		return _roster_all_ready(session), JOIN_ROSTER_TIMEOUT_SECONDS)
	if not all_ready:
		_fail("wait_for_both_ready", "roster never reached 2+ players all READY within %.0fs" % JOIN_ROSTER_TIMEOUT_SECONDS)
		return
	_ok("wait_for_both_ready")

	# Real UI path exercised above; now reuse the same AIController pipeline
	# tools/run_net_test.sh relies on to actually drive the karts (spec:
	# harness fix, netcode untouched) instead of feeding synthetic input.
	session.automated = true
	session.ai_count = 0

	(c["start"] as Button).pressed.emit()
	await get_tree().process_frame
	if not session.started:
		_fail("press_start", "start_race() did not begin; status=%s" % _status_text(c))
		return
	_ok("press_start")

	var outcome: Dictionary = await _monitor_race(session)
	if bool(outcome["reached"]):
		_ok("reach_results", "karts=%d" % int(outcome["karts"]))
		# The host's own RaceManager reaching RESULTS is not the same instant
		# as the joined peer seeing it: the server-authoritative "results"
		# event is only queued this tick and actually goes out over the wire
		# a tick or more later (net/net_race.gd _server_step). Quitting the
		# host process immediately here (harness bug, net_session.gd
		# untouched) raced ahead of that broadcast and of ENet's own
		# disconnect handshake, so the joined peer saw a bare mid-race
		# "Host disconnected" instead of ever reaching its own RESULTS.
		await _wait_for_network_flush()
		_finish(true, int(outcome["karts"]))
	else:
		_fail("reach_results", "race never reached RESULTS (karts=%d)" % int(outcome["karts"]))


## ---- join role ---------------------------------------------------------

func _run_join(c: Dictionary) -> void:
	var code: String = await _wait_for_code_file(CODE_FILE_TIMEOUT_SECONDS)
	if code.is_empty():
		_fail("wait_for_code_file", "code file %s never appeared/stayed empty after %.0fs" % [_code_file, CODE_FILE_TIMEOUT_SECONDS])
		return
	_ok("wait_for_code_file", code)

	(c["ip"] as LineEdit).text = code
	(c["port"] as SpinBox).value = float(_port)
	if _scenario == "wrong-password":
		(c["password"] as LineEdit).text = WRONG_PASSWORD_JOIN

	(c["join"] as Button).pressed.emit()
	await get_tree().process_frame
	if GameState.net_session == null:
		_fail("press_join", "session missing after JOIN press; status=%s" % _status_text(c))
		return
	_ok("press_join", _status_text(c))

	if _scenario == "wrong-password":
		var message: String = await _wait_for_main_menu_message(REJECTION_TIMEOUT_SECONDS)
		if message.is_empty():
			_fail("expect_rejection", "did not bounce to main menu with a rejection message within %.0fs" % REJECTION_TIMEOUT_SECONDS)
			return
		_errors.append(message)
		_ok("expect_rejection", message)
		_finish(false, 0)
		return

	if _scenario == "host-leaves":
		var message2: String = await _wait_for_main_menu_message(JOIN_ROSTER_TIMEOUT_SECONDS)
		if message2.is_empty():
			_fail("expect_host_left", "did not bounce to main menu with a disconnect message within %.0fs" % JOIN_ROSTER_TIMEOUT_SECONDS)
			return
		_errors.append(message2)
		_ok("expect_host_left", message2)
		_finish(false, 0)
		return

	var session: NetSession = GameState.net_session
	session.automated = true

	_select_and_ready(c)
	_ok("select_driver_kart")
	(c["ready"] as Button).pressed.emit()
	_ok("press_ready")

	var outcome: Dictionary = await _monitor_race(session)
	if bool(outcome["reached"]):
		_ok("reach_results", "karts=%d" % int(outcome["karts"]))
		_finish(true, int(outcome["karts"]))
	else:
		_fail("reach_results", "race never reached RESULTS (karts=%d)" % int(outcome["karts"]))


## ---- shared helpers ----------------------------------------------------

func _roster_all_ready(session: NetSession) -> bool:
	if not is_instance_valid(session) or session.players.size() < 2:
		return false
	for row: Dictionary in session.players:
		if not bool(row["ready"]):
			return false
	return true


func _select_and_ready(c: Dictionary) -> void:
	var driver_option: OptionButton = c["driver"] as OptionButton
	var kart_option: OptionButton = c["kart"] as OptionButton
	driver_option.item_selected.emit(driver_option.selected)
	kart_option.item_selected.emit(kart_option.selected)


func _monitor_race(session: NetSession) -> Dictionary:
	var deadline: float = NetSession.now() + RACE_TIMEOUT_SECONDS
	while NetSession.now() < deadline:
		if is_instance_valid(session) and session.race != null and session.race.manager.get_state() == RaceState.RESULTS:
			return {"reached": true, "karts": session.race.manager.get_karts().size()}
		await get_tree().process_frame
	var karts: int = 0
	if is_instance_valid(session) and session.race != null:
		karts = session.race.manager.get_karts().size()
	return {"reached": false, "karts": karts}


func _wait_for_current_scene_named(name: String, timeout: float) -> Node:
	var deadline: float = NetSession.now() + timeout
	while NetSession.now() < deadline:
		var scene: Node = get_tree().current_scene
		if scene != null and scene.name == name:
			return scene
		await get_tree().process_frame
	return null


## Polls for the client bouncing back to the main menu after `_session_ended`
## (wrong password / host disconnect), returning the NetworkMessage text
## main_menu.gd displays, or "" on timeout.
func _wait_for_main_menu_message(timeout: float) -> String:
	var main_scene: Node = await _wait_for_current_scene_named("Main", timeout)
	if main_scene == null:
		return ""
	await get_tree().process_frame
	var label: Label = main_scene.get_node_or_null("MainMenu/Panel/VBox/NetworkMessage") as Label
	return label.text.strip_edges() if label != null else ""


## Real time, not frames: gives the transport's own delay queue and ENet a
## window to actually put queued reliable traffic (and a graceful disconnect)
## on the wire before this process exits out from under the connection.
const NETWORK_FLUSH_SECONDS: float = 1.0

func _wait_for_network_flush() -> void:
	await get_tree().create_timer(NETWORK_FLUSH_SECONDS).timeout


func _await_condition(condition: Callable, timeout: float) -> bool:
	var deadline: float = NetSession.now() + timeout
	while NetSession.now() < deadline:
		if condition.call():
			return true
		await get_tree().process_frame
	return false


func _wait_for_code_file(timeout: float) -> String:
	var deadline: float = NetSession.now() + timeout
	while NetSession.now() < deadline:
		if FileAccess.file_exists(_code_file):
			var file: FileAccess = FileAccess.open(_code_file, FileAccess.READ)
			if file != null:
				var content: String = file.get_as_text().strip_edges()
				file.close()
				if not content.is_empty():
					return content
		await get_tree().process_frame
	return ""


func _write_code_file(code: String) -> Error:
	var dir: String = _code_file.get_base_dir()
	if not dir.is_empty():
		DirAccess.make_dir_recursive_absolute(dir)
	var file: FileAccess = FileAccess.open(_code_file, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(code)
	file.close()
	return OK


func _status_text(c: Dictionary) -> String:
	var label: Label = c["status"] as Label
	return label.text if label != null else ""


## ---- reporting -----------------------------------------------------------

func _ok(step: String, detail: String = "") -> void:
	print("ONLINE_UI step=%s ok detail=%s" % [step, detail])


func _fail(step: String, detail: String) -> void:
	print("ONLINE_UI step=%s fail detail=%s" % [step, detail])
	var karts: int = 0
	var session: NetSession = GameState.net_session
	if is_instance_valid(session) and session.race != null:
		karts = session.race.manager.get_karts().size()
	_report(false, karts)
	_finished = true
	get_tree().quit(1)


func _finish(reached_results: bool, karts: int) -> void:
	_report(reached_results, karts)
	_finished = true
	get_tree().quit(0)


func _report(reached_results: bool, karts: int) -> void:
	var result: Dictionary = {"role": _role, "reached_results": reached_results, "karts": karts, "errors": _errors}
	print("ONLINE_UI_RESULT " + JSON.stringify(result))
