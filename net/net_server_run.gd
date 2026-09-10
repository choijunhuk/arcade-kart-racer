class_name NetServerRun
extends Node

## Dedicated headless server driver (spec item 3): hosts a session with no
## local kart, auto-starts via NetServerState once ready (or a grace
## timeout elapses), and reopens the lobby after RESULTS so already-
## connected peers are not dropped. Prints `SERVER_STATE <name>` on every
## transition, matching the existing `NET_STATE`/`SERVER_STATE` log style.

const RESULTS_GRACE_SECONDS: float = 3.0
const STATE_NAMES: Array[String] = ["LOBBY", "COUNTDOWN", "RUNNING"]

var session: NetSession
var _state: NetServerState = NetServerState.new()
var _results_seen_at: float = -1.0
var _last_printed: int = -1


## Installs the dedicated-server loop on the persistent GameState owner.
func configure(owner_session: NetSession) -> void:
	session = owner_session
	session.test_report_received.connect(_on_test_report)
	_print_state()


func _physics_process(delta: float) -> void:
	if session == null or not multiplayer.is_server():
		return
	if _state.state == NetServerState.State.RUNNING:
		_watch_results()
	elif _state.update(delta, session.players.size(), _ready_count()):
		session.start_race(true)
	_print_state()


func _ready_count() -> int:
	var count: int = 0
	for row: Dictionary in session.players:
		if bool(row["ready"]):
			count += 1
	return count


func _watch_results() -> void:
	if session.race == null or session.race.manager.get_state() != RaceState.RESULTS:
		_results_seen_at = -1.0
		return
	if _results_seen_at < 0.0:
		_results_seen_at = NetSession.now()
	elif NetSession.now() - _results_seen_at >= RESULTS_GRACE_SECONDS:
		session.restart_to_lobby()
		_state.finish_and_restart()


## Relays a test client's own pass/fail report back as a "test_done" event,
## exactly like the loopback harness's server side would (spec item 7:
## tools/run_server_test.sh reuses the existing automated client codepath).
func _on_test_report(report: Dictionary) -> void:
	session.send(&"_event", 0, ["test_done", [0 if bool(report.get("passed", false)) else 1]], true)


func _print_state() -> void:
	if int(_state.state) == _last_printed:
		return
	_last_printed = int(_state.state)
	print("SERVER_STATE %s" % STATE_NAMES[_state.state])
