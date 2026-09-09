class_name NetTestRun
extends Node

## Two-process acceptance runner: real ENet, real race, no synthetic finish events.
const TIMEOUT_SECONDS: float = 240.0
const SHUTDOWN_SECONDS: float = 1.0
const MEAN_LIMIT: float = 0.5
const START_RETRY_SECONDS: float = 1.0
const PROGRESS_SECONDS: float = 5.0
var session: NetSession
var _started_at: float = 0.0
var _reported: bool = false
var _exit_at: float = -1.0
var _exit_code: int = 0
var _clock_reported: bool = false
var _recent_events: Array[Dictionary] = []
var _next_start_retry: float = 0.0
var _next_progress: float = 0.0
const STATE_NAMES: Array[String] = ["LOADING", "COUNTDOWN", "RACING", "FINISHING", "RESULTS", "PAUSED"]

## Installs the command-line headless test on the persistent GameState owner.
func configure(owner_session: NetSession) -> void:
	session = owner_session
	_started_at = NetSession.now()
	_next_start_retry = _started_at + START_RETRY_SECONDS
	_next_progress = _started_at + PROGRESS_SECONDS
	session.test_report_received.connect(_report_received)
	session.event_received.connect(_event_received)
	session.disconnected.connect(_disconnected)
	session.snapshot_received.connect(_trace_divergence)
	EventBus.race_state_changed.connect(_state_changed)
	print("NET_STATE role=%s state=LOBBY" % _role())
	if session.race != null:
		_state_changed(-1, session.race.manager.get_state())

func _role() -> String:
	return "host" if multiplayer.is_server() else "client"

func _state_changed(_old_state: int, state: int) -> void:
	print("NET_STATE role=%s state=%s" % [_role(), STATE_NAMES[state]])

func _physics_process(_delta: float) -> void:
	var now: float = NetSession.now()
	if now >= _next_start_retry:
		session.retry_start()
		_next_start_retry = now + START_RETRY_SECONDS
	# The estimator becomes usable after its first valid round-trip sample.
	if session.clock.initialized and not _clock_reported:
		_clock_reported = true
		print("NET_CLOCK offset=%.6f rtt=%.6f" % [session.clock.offset_seconds, session.clock.rtt_seconds])
	if _exit_at > 0.0 and now >= _exit_at:
		session.close()
		get_tree().quit(_exit_code)
		return
	if now - _started_at > TIMEOUT_SECONDS:
		push_error("NET_TEST timeout before both peers reached RESULTS")
		session.close()
		get_tree().quit(1)
		return
	if multiplayer.is_server() and session.race != null and session.race.manager.get_state() == RaceState.RACING and now >= _next_progress:
		_log_progress()
		_next_progress = now + PROGRESS_SECONDS
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
	if kind in ["kart_hit", "kart_respawned", "kart_contacted", "item_hit", "item_used", "item_defense_triggered", "wall_head_on", "kart_launched"]:
		_recent_events.append({"event": kind, "args": args.duplicate(true), "time": NetSession.now()})
		if _recent_events.size() > 32:
			_recent_events.pop_front()
	if kind == "test_done":
		_exit_code = int(args[0])
		print("NET_TEST %s" % ("PASS" if _exit_code == 0 else "FAIL"))
		_exit_at = NetSession.now() + SHUTDOWN_SECONDS * 0.5

func _trace_divergence(snapshot: RaceSnapshot) -> void:
	if session.race == null:
		return
	var slot: int = session.local_slot()
	if slot < 0 or slot >= snapshot.karts.size():
		return
	var row: Dictionary = snapshot.karts[slot]
	var ack: int = int(row["ack"])
	var history: Dictionary = session.race.get("_predicted_positions")
	if not history.has(ack):
		return
	var values: Array = row["state"]["position"]
	var server_position: Vector3 = Vector3(values[0], values[1], values[2])
	var predicted_position: Vector3 = history[ack]
	var error: float = predicted_position.distance_to(server_position)
	if error <= NetTuning.SNAP_METERS:
		return
	var kart: KartController = session.race.manager.get_karts()[slot]
	print("NET_DIVERGE " + JSON.stringify({"tick": snapshot.tick, "ack": ack, "error": error,
		"server_state": row["state"]["components"]["."]["state"], "local_state": kart.get_state(),
		"server_position": values, "predicted_position": [predicted_position.x, predicted_position.y, predicted_position.z],
		"local_position": [kart.global_position.x, kart.global_position.y, kart.global_position.z],
		"replay_frames": session.race.prediction.frames.size(), "events": _recent_events}))

func _disconnected(message: String) -> void:
	if _exit_at < 0.0:
		push_error("NET_TEST disconnected: " + message)
		get_tree().quit(1)

func _log_progress() -> void:
	var race: NetRace = session.race
	var manager: RaceManager = race.manager
	var laps: LapTracker = manager.get_node("LapTracker") as LapTracker
	var positions: PositionTracker = manager.get_node("PositionTracker") as PositionTracker
	var buffers: Array = race.get("_buffers")
	var starts: Array = race.get("_start_ticks")
	var rows: Array[Dictionary] = []
	var karts: Array[KartController] = manager.get_karts()
	for index: int in range(karts.size()):
		var kart: KartController = karts[index]
		var buffer: NetInputBuffer = buffers[index]
		var human: bool = index < session.players.size()
		var target: int = race.tick - int(starts[index]) + 1
		rows.append({"name": String(kart.name), "lap": laps.get_lap(kart),
			"checkpoint": laps.get_next_checkpoint_index(kart), "progress": positions.get_progress(kart),
			"speed": kart.get_speed(), "state": kart.get_state(),
			"last_input_tick": buffer.last_received_tick if human else -1,
			"input_age_ticks": maxi(0, target - buffer.last_received_tick) if human else -1,
			"last_processed_tick": buffer.last_processed_tick if human else -1,
			"last_applied_input_tick": buffer.last_input_tick if human else -1,
			"throttle": kart.get_throttle_input(), "brake": kart.get_brake_input(),
			"position": [kart.global_position.x, kart.global_position.y, kart.global_position.z]})
	for row: Dictionary in rows:
		print("NET_PROGRESS tick=%d kart=%s lap=%d cp=%d progress=%.3f speed=%.3f state=%d last_input_tick=%d input_age=%d details=%s" % [
			race.tick, row["name"], row["lap"], row["checkpoint"], row["progress"], row["speed"], row["state"],
			row["last_input_tick"], row["input_age_ticks"], JSON.stringify(row)])
