class_name MainBootstrap
extends Node

func _ready() -> void:
	GameState.current_mode = GameState.Mode.MENU
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.has("--net-host") and not args.has("--net-join"):
		return
	_start_network.call_deferred(args)

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
