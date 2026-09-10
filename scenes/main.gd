class_name MainBootstrap
extends Node

func _ready() -> void:
	GameState.current_mode = GameState.Mode.MENU
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.has("--relay"):
		_start_relay.call_deferred(args)
	elif args.has("--server"):
		_start_server.call_deferred(args)
	elif args.has("--net-host") or args.has("--net-join"):
		_start_network.call_deferred(args)

## Standalone UDP forwarder process for double-NAT hosts (spec item 4).
func _start_relay(args: PackedStringArray) -> void:
	var relay: NetRelayServer = NetRelayServer.new()
	add_child(relay)
	var port: int = int(_value(args, "--port", str(NetTuning.PORT)))
	if relay.start(port) != OK:
		get_tree().quit(1)

## Dedicated, kart-less headless server: hosts, auto-starts, and loops back
## to lobby after every race without dropping connected peers (spec item 3).
func _start_server(args: PackedStringArray) -> void:
	var session: NetSession = NetSession.new()
	session.name = "NetSession"
	session.dedicated = true
	session.ai_count = clampi(int(_value(args, "--ai", "0")), 0, 10)
	session.laps = clampi(int(_value(args, "--laps", "1")), 1, 9)
	session.track_id = _value(args, "--track", "")
	var password: String = _value(args, "--password", "")
	if not password.is_empty():
		session.set_password(password)
	GameState.net_session = session
	GameState.add_child(session)
	var port: int = int(_value(args, "--port", str(NetTuning.PORT)))
	var max_players: int = clampi(int(_value(args, "--max-players", "8")), 2, RaceSnapshot.MAX_KARTS)
	var error: Error = session.host(port, max_players)
	if error != OK:
		push_error("SERVER startup failed: " + error_string(error))
		session.close()
		get_tree().quit(1)
		return
	var runner: NetServerRun = NetServerRun.new()
	GameState.add_child(runner)
	runner.configure(session)
	print("SERVER_READY port=%d max_players=%d track=%s" % [port, max_players, session.track_id])

func _start_network(args: PackedStringArray) -> void:
	var session: NetSession = NetSession.new()
	session.name = "NetSession"
	session.automated = DisplayServer.get_name() == "headless"
	session.ai_count = clampi(int(_value(args, "--ai", "6")), 0, 10)
	session.laps = clampi(int(_value(args, "--laps", "1")), 1, 9)
	session.conditions.latency_seconds = maxf(0.0, float(_value(args, "--net-latency", "0"))) / 1000.0
	session.conditions.loss = clampf(float(_value(args, "--net-loss", "0")), 0.0, 1.0)
	GameState.automation_mode = session.automated
	GameState.net_session = session
	GameState.add_child(session)
	var port: int = int(_value(args, "--net-port", str(NetTuning.PORT)))
	var error: Error = session.host(port) if args.has("--net-host") else session.join(_value(args, "--net-join", "127.0.0.1"), port)
	if error != OK:
		push_error("NET startup failed: " + error_string(error))
		session.close()
		get_tree().quit(1)
		return
	if session.automated:
		var runner: NetTestRun = NetTestRun.new()
		GameState.add_child(runner)
		runner.configure(session)
	print("NET_READY " + ("host" if args.has("--net-host") else "client"))

func _value(args: PackedStringArray, key: String, fallback: String) -> String:
	var index: int = args.find(key)
	return args[index + 1] if index >= 0 and index + 1 < args.size() else fallback
