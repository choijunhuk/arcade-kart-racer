class_name NetRace
extends Node

## Race-local fixed-tick transport adapter; server alone owns all race adjudication.
var session: NetSession
var manager: RaceManager
var tick: int = 0
var prediction: NetPrediction = NetPrediction.new()
var statistics: Dictionary[int, Dictionary] = {}
var _state: NetRaceState
var _karts: Array[KartController] = []
var _buffers: Array[NetInputBuffer] = []
var _start_ticks: Array[int] = []
var _source: InputProvider
var _input_tick: int = 0
var _input_history: Array[Dictionary] = []
var _local: int = 0
var _local_grid_slot: int = 0
var _render_queue: Array[RaceSnapshot] = []
var _has_render_sample: bool = false
var _pending: RaceSnapshot
var _last_snapshot: int = -1
var _interpolators: Array[NetInterpolator] = []
var _predicted_positions: Dictionary[int, Vector3] = {}
var _projectiles: NetProjectiles
var _reported_results: bool = false
var _countdown_value: int = -1
var _go_server_time: float = 0.0

## Binds explicit race-owned services after composition, before network countdown.
func configure(owner_race: RaceManager, owner_session: NetSession) -> void:
	manager = owner_race
	session = owner_session
	_state = NetRaceState.new(manager)
	_karts = manager.get_karts()
	_local = session.local_slot()
	_local_grid_slot = _local
	process_physics_priority = NetTuning.RACE_PROCESS_PRIORITY
	for kart: KartController in _karts:
		kart.set_physics_process(false)
		_buffers.append(NetInputBuffer.new())
		_start_ticks.append(-1)
		_interpolators.append(NetInterpolator.new())
	_source = ScriptedRaceInputProvider.new(_karts[_local], (manager.get_node("Track") as TrackRoot).get_racing_line()) if session.automated else PlayerInputProvider.new()
	var events: NetEvents = NetEvents.new()
	add_child(events)
	events.configure(session, _karts)
	var track_events: NetTrackEvents = NetTrackEvents.new()
	add_child(track_events)
	track_events.configure(session, manager.get_node("Track"), manager.network_replica)
	_projectiles = NetProjectiles.new()
	manager.add_child(_projectiles)
	session.snapshot_received.connect(_receive_snapshot)
	session.event_received.connect(_receive_event)
	session.bind_race(self)

## Starts the authoritative countdown only after every participant has loaded.
func begin() -> void:
	if multiplayer.is_server():
		(manager.get_node("Countdown") as Countdown).start()

## Accepts only the sender's roster slot, with finite, bounded input fields.
func receive_input(sender: int, data: Dictionary) -> void:
	var frames: Variant = data.get("frames", [data])
	if not frames is Array or frames.is_empty() or frames.size() > NetTuning.INPUT_BATCH_TICKS:
		return
	for frame: Variant in frames:
		if frame is Dictionary:
			_receive_input_frame(sender, frame)

func _receive_input_frame(sender: int, data: Dictionary) -> void:
	for key: String in ["tick", "throttle", "brake", "steer"]:
		if not (data.get(key) is int or data.get(key) is float):
			return
	if not data["tick"] is int:
		return
	for key: String in ["drift", "drift_pressed", "item", "look_back"]:
		if not data.get(key) is bool:
			return
	var frame: InputFrame = InputFrame.from_dict(data)
	for index: int in range(session.players.size()):
		if int(session.players[index]["peer"]) == sender:
			if bool(_karts[index].get("_finished")):
				return
			if _buffers[index].insert(frame) and _start_ticks[index] < 0:
				_start_ticks[index] = tick + NetTuning.INPUT_DELAY
			return

func _physics_process(_delta: float) -> void:
	if not session.running:
		return
	tick += 1
	if multiplayer.is_server():
		_server_step()
	else:
		_client_step()

func _server_step() -> void:
	if not bool(_karts[_local].get("_finished")):
		var frame: InputFrame = _next_input()
		receive_input(NetSession.SERVER_ID, frame.to_dict())
	var acknowledgements: Array[int] = []
	for index: int in range(_karts.size()):
		var input: InputFrame
		if index < session.players.size() and not bool(_karts[index].get("_finished")):
			var target: int = tick - _start_ticks[index] + 1
			input = _buffers[index].consume(target) if _start_ticks[index] >= 0 and target > 0 else InputFrame.zero()
			acknowledgements.append(_buffers[index].last_processed_tick)
		else:
			input = _karts[index].input_provider.get_frame()
			acknowledgements.append(_buffers[index].last_processed_tick if index < session.players.size() else 0)
		_karts[index].step_input(input, NetTuning.STEP)
	if tick % NetTuning.SNAPSHOT_INTERVAL == 0:
		session.send(&"_snapshot", 0, [_state.capture(tick, acknowledgements).pack()], false)
	if manager.get_state() == RaceState.RESULTS and not _reported_results:
		_reported_results = true
		session.send(&"_event", 0, ["results", NetResults.pack(manager.get_results())], true)

func _client_step() -> void:
	if _pending != null:
		_apply_snapshot(_pending)
		_pending = null
	if bool(_karts[_local].get("_finished")):
		return
	var frame: InputFrame = _next_input()
	_input_history.append(frame.to_dict())
	if _input_history.size() > NetTuning.INPUT_BATCH_TICKS:
		_input_history.pop_front()
	# Keep transport history through respawns/hits, independently of prediction replay.
	session.send(&"_receive_input", NetSession.SERVER_ID, [{"frames": _input_history.duplicate(true)}], false)
	if NetPrediction.requires_server_pose(_karts[_local].get_state()):
		_update_countdown()
		return
	prediction.record(frame)
	_karts[_local].step_input(frame, NetTuning.STEP)
	_predicted_positions[frame.tick] = _karts[_local].global_position
	_predicted_positions.erase(frame.tick - NetTuning.HISTORY_TICKS)
	_update_countdown()

func _next_input() -> InputFrame:
	_input_tick += 1
	var frame: InputFrame = _source.get_frame()
	frame.tick = _input_tick
	return frame

func _receive_snapshot(snapshot: RaceSnapshot) -> void:
	if snapshot.tick <= _last_snapshot or snapshot.karts.size() != _karts.size():
		return
	_last_snapshot = snapshot.tick
	_pending = snapshot
	_render_queue.append(snapshot)
	if _render_queue.size() > NetTuning.HISTORY_TICKS:
		_render_queue.pop_front()

func _apply_snapshot(snapshot: RaceSnapshot) -> void:
	_state.apply(snapshot)
	_go_server_time = snapshot.server_seconds + snapshot.countdown_seconds
	for index: int in range(_karts.size()):
		var row: Dictionary = snapshot.karts[index]
		var state: Dictionary = row["state"]
		var values: Array = state["position"]
		var position: Vector3 = Vector3(values[0], values[1], values[2])
		if index == _local:
			var ack: int = int(row["ack"])
			var server_state: int = int(state["components"]["."]["state"])
			if NetPrediction.requires_server_pose(server_state) or NetPrediction.requires_server_pose(_karts[index].get_state()):
				_predicted_positions.clear()
			elif _predicted_positions.has(ack):
				_measure(index, _predicted_positions[ack].distance_to(position))
			prediction.reconcile(_karts[index], state, ack, _predicted_positions)
		else:
			_karts[index].apply_state(state)
	_projectiles.apply(snapshot.projectiles, _state)

func _process(delta: float) -> void:
	if session == null or multiplayer.is_server() or not session.running:
		return
	var render_time: float = session.clock.server_time(NetSession.now()) - NetTuning.INTERPOLATION_SECONDS
	_advance_render_samples(render_time)
	for index: int in range(_karts.size()):
		var visuals: KartVisuals = _karts[index].get_node("Visuals") as KartVisuals
		if index == _local:
			visuals.network_pose = Transform3D(Basis.IDENTITY, _karts[index].global_basis.inverse() * prediction.advance_visual(delta))
		elif _has_render_sample:
			visuals.network_pose = _karts[index].global_transform.affine_inverse() * _interpolators[index].sample(render_time)

func _measure(index: int, error: float) -> void:
	var stats: Dictionary = statistics.get(index, {"count": 0, "sum": 0.0, "max": 0.0})
	stats["count"] = int(stats["count"]) + 1
	stats["sum"] = float(stats["sum"]) + error
	stats["max"] = maxf(float(stats["max"]), error)
	statistics[index] = stats

func _receive_event(kind: String, args: Array) -> void:
	if kind == "results":
		manager.apply_network_results(NetResults.unpack(args, _local_grid_slot))
	elif kind == "countdown_tick" and args.size() == 1:
		_emit_countdown(int(args[0]))

func _update_countdown() -> void:
	if not session.clock.initialized or _go_server_time <= 0.0 or manager.get_state() != RaceState.COUNTDOWN:
		return
	var remaining: float = _go_server_time - session.clock.server_time(NetSession.now())
	var value: int = clampi(ceili(remaining), Countdown.GO_TICK, Countdown.FIRST_TICK)
	_emit_countdown(value)

func _emit_countdown(value: int) -> void:
	if value < Countdown.GO_TICK or value > Countdown.FIRST_TICK:
		return
	# Reliable ticks can arrive after clock prediction; never repeat or rewind them.
	if _countdown_value < 0 or value < _countdown_value:
		_countdown_value = value
		EventBus.countdown_tick.emit(value)

func _advance_render_samples(render_time: float) -> void:
	# Hold transport samples until the two interpolation endpoints bracket the delayed time.
	while not _render_queue.is_empty():
		if _has_render_sample and _render_queue[0].server_seconds > render_time + NetTuning.SNAPSHOT_INTERVAL * NetTuning.STEP:
			break
		var snapshot: RaceSnapshot = _render_queue.pop_front()
		for index: int in range(_karts.size()):
			var state: Dictionary = snapshot.karts[index]["state"]
			var pos: Array = state["position"]
			var pose: Transform3D = Transform3D(Basis(Vector3.UP, float(state["rotation"][1])), Vector3(pos[0], pos[1], pos[2]))
			_interpolators[index].push(snapshot.server_seconds, pose)
		_has_render_sample = true

## Removes the departed peer's transport slot while retaining result grid identity.
func remove_player(index: int) -> void:
	var kart: KartController = _karts[index]
	manager.remove_network_player(kart)
	_karts.remove_at(index)
	_buffers.remove_at(index)
	_start_ticks.remove_at(index)
	_interpolators.remove_at(index)
	if index < _local:
		_local -= 1
	_pending = null
	_render_queue.clear()
	_has_render_sample = false
