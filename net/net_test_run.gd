class_name NetTestRun
extends Node

## Two-process acceptance runner: real ENet, real race, no synthetic finish events.
const TIMEOUT_SECONDS: float = 240.0
const SHUTDOWN_SECONDS: float = 1.0
const MEAN_LIMIT: float = 0.5
var session: NetSession
var _started_at: float = 0.0
var _reported: bool = false
var _exit_at: float = -1.0
var _exit_code: int = 0

## Installs the command-line headless test on the persistent GameState owner.
func configure(owner_session: NetSession) -> void:
	session = owner_session
	_started_at = NetSession.now()
	session.test_report_received.connect(_report_received)
	session.event_received.connect(_event_received)
	session.disconnected.connect(_disconnected)

func _physics_process(_delta: float) -> void:
	var now: float = NetSession.now()
	if _exit_at > 0.0 and now >= _exit_at:
		session.close()
		get_tree().quit(_exit_code)
		return
	if now - _started_at > TIMEOUT_SECONDS:
		push_error("NET_TEST timeout before both peers reached RESULTS")
		session.close()
		get_tree().quit(1)
		return
	if session.race == null or _reported or session.race.manager.get_state() != RaceState.RESULTS:
		return
	_reported = true
	var entries: Array[RaceResults.Entry] = session.race.manager.get_results()
	var finished: bool = entries.size() == session.players.size() + session.ai_count
	for entry: RaceResults.Entry in entries:
		finished = finished and entry.total_time_seconds >= 0.0
	print("NET_RESULTS role=%s karts=%d all_finished=%s" % ["host" if multiplayer.is_server() else "client", entries.size(), finished])
	if not multiplayer.is_server():
		var rows: Dictionary = {}
		var passed: bool = finished and not session.race.statistics.is_empty()
		for slot: int in session.race.statistics:
			var stats: Dictionary = session.race.statistics[slot]
			var mean: float = float(stats["sum"]) / maxi(1, int(stats["count"]))
			rows[str(slot)] = {"samples": stats["count"], "mean": mean, "max": stats["max"]}
			passed = passed and mean < MEAN_LIMIT and float(stats["max"]) < NetTuning.SNAP_METERS
		var report: Dictionary = {"passed": passed, "predicted_karts": rows,
			"dropped_outbound": session.conditions.dropped, "rtt": session.clock.rtt_seconds}
		print("NET_STATS " + JSON.stringify(report))
		session.send(&"_test_report", NetSession.SERVER_ID, [report], true)
	elif not finished:
		_exit_code = 1

func _report_received(report: Dictionary) -> void:
	if session.race.manager.get_state() != RaceState.RESULTS:
		push_error("Client results preceded authoritative results")
		_exit_code = 1
	_exit_code = _exit_code if bool(report.get("passed", false)) else 1
	print("NET_TEST %s" % ("PASS" if _exit_code == 0 else "FAIL"))
	session.send(&"_event", 0, ["test_done", [_exit_code]], true)
	_exit_at = NetSession.now() + session.conditions.latency_seconds + SHUTDOWN_SECONDS

func _event_received(kind: String, args: Array) -> void:
	if kind == "test_done":
		_exit_code = int(args[0])
		print("NET_TEST %s" % ("PASS" if _exit_code == 0 else "FAIL"))
		_exit_at = NetSession.now() + SHUTDOWN_SECONDS * 0.5

func _disconnected(message: String) -> void:
	if _exit_at < 0.0:
		push_error("NET_TEST disconnected: " + message)
		get_tree().quit(1)
