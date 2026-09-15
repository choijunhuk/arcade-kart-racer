class_name NetSession
extends Node

## Persistent GameState child. Only the server mutates lobby and starts a race.
signal lobby_changed()
signal disconnected(message: String)
signal test_report_received(report: Dictionary)
signal snapshot_received(snapshot: RaceSnapshot)
signal prediction_measured(snapshot: RaceSnapshot, row: Dictionary, predicted_position: Vector3, error: float, replay_frames: int)
signal event_received(kind: String, args: Array)
signal admitted(waiting: bool)
const SERVER_ID: int = 1
const RACE_PATH: String = "res://race/race.tscn"
var players: Array[Dictionary] = []
var clock: NetClock = NetClock.new()
var conditions: NetDebugConditions = NetDebugConditions.new()
var peer: ENetMultiplayerPeer
var race: NetRace
var started: bool = false
var running: bool = false
var automated: bool = false
var ai_count: int = 6
var laps: int = 1
var seed: int = 15
## Dedicated headless server (spec item 3): occupies no player row/kart; independent of `automated` ("this is a scripted test harness").
var dedicated: bool = false
var max_players: int = NetTuning.MAX_PLAYERS
## "" keeps the default track/AI difficulty; only the dedicated server CLI sets track_id.
var track_id: String = ""
var difficulty_id: String = ""
## SHA-256 of the session password ("" = none); plaintext is never stored or logged (spec item 6).
var password_hash: String = ""
var _password_attempt_hash: String = ""
var _input_limiter: NetRateLimiter = NetRateLimiter.new()
## Guards `_selection` (backlog item 6): much lower-frequency than race input,
## since it is only ever a lobby UI action, not a per-physics-tick send.
var _selection_limiter: NetRateLimiter = NetRateLimiter.new(10.0, 5.0)
var _gate: NetPeerGate = NetPeerGate.new()
var _loss: NetLossEstimator = NetLossEstimator.new()
var _roster: NetSessionLobby = NetSessionLobby.new()
var _transport: NetSessionTransport = NetSessionTransport.new()
var _pending_departures: Array[int] = []
var _clock_ticks: int = 0
var _closing: bool = false

func _init() -> void:
	_roster.attach(self)
	_transport.attach(self)

func _ready() -> void:
	multiplayer.peer_connected.connect(_peer_connected)
	multiplayer.peer_disconnected.connect(_peer_disconnected)
	multiplayer.connected_to_server.connect(_connected)
	multiplayer.connection_failed.connect(_connection_failed)
	multiplayer.server_disconnected.connect(_server_disconnected)

## Opens a listen server; `dedicated` keeps a headless server off the player row/slot, so `--max-players 8` admits 8 dedicated, 7+host listen.
func host(port: int = NetTuning.PORT, max_players_value: int = NetTuning.MAX_PLAYERS) -> Error:
	peer = ENetMultiplayerPeer.new()
	var slots: int = NetSessionLobby.connection_slots(max_players_value, dedicated)
	var error: Error = peer.create_server(port, slots, NetTuning.CHANNEL_COUNT)
	if error != OK:
		return error
	multiplayer.multiplayer_peer = peer
	GameState.is_networked = true
	max_players = max_players_value
	_roster.reset_for_host(dedicated, automated)
	lobby_changed.emit()
	return OK

## Connects to the supplied address; completion arrives through lobby_changed.
## `password` is hashed locally, never sent or logged in cleartext (spec 6).
func join(ip: String, port: int = NetTuning.PORT, password: String = "") -> Error:
	peer = ENetMultiplayerPeer.new()
	var error: Error = peer.create_client(ip, port, NetTuning.CHANNEL_COUNT)
	if error == OK:
		multiplayer.multiplayer_peer = peer
		GameState.is_networked = true
		_loss.stride = NetTuning.SNAPSHOT_INTERVAL
		_password_attempt_hash = password.sha256_text() if not password.is_empty() else ""
	return error

## Sets the session password as its hash only (spec item 6: hashed compare,
## never logged). Pass "" to clear (no password required).
func set_password(plain: String) -> void:
	password_hash = plain.sha256_text() if not plain.is_empty() else ""

## Resolves this process's grid index from the server-owned roster.
func local_slot() -> int:
	return _roster.index_of(multiplayer.get_unique_id())

## Real transport loss (0.0-1.0) measured from sequence gaps over a 2 s window
## (spec item 5); unlike `conditions.dropped`, this counts genuinely missing traffic.
func get_loss_estimate() -> float:
	return _loss.loss(now())

## Sends only our selection; the server derives ownership from the RPC sender.
func select(driver: String, kart: String, ready: bool) -> void:
	if multiplayer.is_server():
		_update_player(SERVER_ID, driver, kart, ready)
	else:
		send(&"_selection", SERVER_ID, [driver, kart, ready], true)

## Starts the race once the roster allows it (NetSessionLobby.start_race).
func start_race(force: bool = false) -> bool:
	return _roster.start_race(force)

func set_race_options(new_laps: int, new_ai_count: int, new_track_id: String, new_difficulty_id: String) -> void: # Host-only (spec item 1).
	_roster.set_race_options(new_laps, new_ai_count, new_track_id, new_difficulty_id)

## Repeats preparation only for peers whose scene-load acknowledgement is missing.
func retry_start() -> void:
	_roster.retry_start()

## Host-only: reopens the lobby after RESULTS (NetSessionLobby, spec item 3).
func restart_to_lobby() -> void:
	_roster.restart_to_lobby()

## Host-only: reopens the ENet listener to new connections once the lobby
## scene is genuinely active again (finding: lobby-reopen connection window).
## Called from the lobby scene's own rebind path, never automatically by
## `restart_to_lobby()` — see its doc comment. Guarded explicitly (review
## finding 4), not just by callers already clearing `started`/`race` first.
func reopen_connections() -> void:
	if multiplayer.is_server() and peer != null and not started and race == null:
		peer.refuse_new_connections = false

## Non-host counterpart to `restart_to_lobby()`: clears only local race state
## on BACK TO LOBBY; `started` waits for the host's own broadcast to clear.
func clear_local_race_state() -> void:
	race = null
	running = false
	_roster.preparing = false

## Registers a loaded race and waits until all peers have matching scene nodes.
func bind_race(value: NetRace) -> void:
	race = value
	for id: int in _pending_departures:
		_player_left(id)
	_pending_departures.clear()
	if multiplayer.is_server():
		_mark_loaded(SERVER_ID)
	else:
		send(&"_race_loaded", SERVER_ID, [], true)

## Queues a real RPC through optional one-way delay and unreliable loss.
func send(method: StringName, target: int, args: Array, reliable: bool) -> void:
	_transport.send(method, target, args, reliable)

## Monotonic time is restricted to transport, never race adjudication.
static func now() -> float:
	return float(Time.get_ticks_usec()) / 1000000.0

## Closes networking, releases delayed callbacks and clears the persistent owner.
func close() -> void:
	if _closing:
		return
	_closing = true
	conditions.clear()
	if peer != null:
		peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	GameState.is_networked = false
	GameState.net_session = null
	queue_free()

func _physics_process(_delta: float) -> void:
	conditions.advance(now())
	if peer == null or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	_clock_ticks += 1
	if multiplayer.is_server():
		_service_peers()
	if not multiplayer.is_server() and _clock_ticks % NetTuning.CLOCK_INTERVAL == 0:
		send(&"_ping", SERVER_ID, [now()], true)
	if automated and not started and multiplayer.is_server() and players.size() >= 2:
		start_race()

func _deliver(method: StringName, target: int, args: Array, reliable: bool) -> void:
	_transport.deliver(method, target, args, reliable)

func _service_peers() -> void:
	_transport.service_peers()

## A connected peer is not a joined player yet: no roster row/kart until its handshake passes, and it is kicked if it never sends one.
func _peer_connected(id: int) -> void:
	if not multiplayer.is_server():
		return
	_gate.track(id, now())
func _admit_peer(id: int) -> void:
	_roster.admit_peer(id) # Body lives on NetSessionLobby (400-line budget); test_net_session_admission.gd calls this wrapper directly.
## Tells a just-admitted client whether it joined mid-race as a `waiting`
## spectator (no row until the next lobby, so `local_slot()` stays -1).
@rpc("authority", "call_remote", "reliable")
func _admitted(waiting: bool) -> void:
	admitted.emit(waiting)

func _connected() -> void:
	NetTuning.widen_peer_timeout(peer, SERVER_ID)
	send(&"_ping", SERVER_ID, [now()], true)
	send(&"_handshake", SERVER_ID, [String(ProjectSettings.get_setting("application/config/version", "")), _password_attempt_hash], true)
	if automated:
		var row: Dictionary = _roster.new_row(multiplayer.get_unique_id(), true)
		select(row["driver"], row["kart"], true)

func _update_player(id: int, driver: String, kart: String, ready: bool) -> void:
	if started or not NetContentCatalog.has(LocalLobby.DRIVER_DIRECTORY, driver) or not NetContentCatalog.has(LocalLobby.KART_DIRECTORY, kart):
		return
	if _roster.update(id, driver, kart, ready):
		_roster.broadcast_lobby()

## Sender id of the `any_peer` RPC being handled, or -1 off-server / unverified (spec 6).
func _verified_sender() -> int:
	var id: int = _sender()
	return id if multiplayer.is_server() and _gate.allows(id) else -1

func _sender() -> int:
	return multiplayer.get_remote_sender_id()

@rpc("any_peer", "call_remote", "reliable")
func _selection(driver: String, kart: String, ready: bool) -> void:
	var id: int = _verified_sender()
	if id > 0 and _selection_limiter.allow(id, now()):
		_update_player(id, driver, kart, ready)

@rpc("authority", "call_remote", "reliable")
func _lobby(roster: Array, lobby_laps: int = 1, lobby_ai_count: int = 6, lobby_track_id: String = "", lobby_difficulty_id: String = "") -> void:
	_roster.apply_lobby(roster, lobby_laps, lobby_ai_count, lobby_track_id, lobby_difficulty_id)
	lobby_changed.emit()

@rpc("authority", "call_remote", "reliable")
func _return_to_lobby(roster: Array) -> void:
	_roster.clear_race_state()
	_roster.replace(roster)
	lobby_changed.emit()

@rpc("authority", "call_remote", "reliable")
func _prepare_race(roster: Array, bots: int, lap_count: int, race_seed: int, race_track_id: String = "", race_difficulty_id: String = "") -> void:
	if _roster.preparing or race != null:
		if not multiplayer.is_server() and race != null:
			send(&"_race_loaded", SERVER_ID, [], true)
		return
	_roster.begin_prepare(roster, lap_count, bots, race_track_id, race_difficulty_id) # apply_race_settings clamps (spec item 3).
	seed = race_seed
	started = true
	GameState.pending_race_config = NetRaceSetup.build(players, ai_count, laps, seed, track_id, difficulty_id)
	GameState.current_mode = GameState.Mode.RACE
	get_tree().change_scene_to_file.call_deferred(RACE_PATH)

## Validates a newly connected peer's version/password (spec 6, never logging
## the password); only an acceptable handshake earns a roster row.
@rpc("any_peer", "call_remote", "reliable")
func _handshake(client_version: String, password_attempt: String) -> void:
	var id: int = _sender()
	if not multiplayer.is_server() or _gate.allows(id) or not _gate.is_pending(id):
		return
	var expected_version: String = String(ProjectSettings.get_setting("application/config/version", ""))
	var reason: String = NetHandshake.reject_reason(client_version, expected_version, password_attempt, password_hash)
	if not reason.is_empty():
		_reject_peer(id, reason)
	elif _gate.verify(id):
		_admit_peer(id)

func _reject_peer(id: int, message: String) -> void:
	_roster.reject_peer(id, message) # Body lives on NetSessionLobby (400-line budget); test_net_internet.gd calls this wrapper directly.

func _deliver_reject(id: int, message: String) -> void:
	if multiplayer.has_multiplayer_peer() and multiplayer.get_peers().has(id):
		rpc_id(id, &"_session_ended", message)

@rpc("any_peer", "call_remote", "reliable")
func _race_loaded() -> void:
	var id: int = _verified_sender()
	if id > 0:
		_mark_loaded(id)

func _mark_loaded(id: int) -> void:
	if _roster.index_of(id) < 0 or _roster.loaded.has(id):
		return
	_roster.loaded.append(id)
	if _roster.loaded.size() == players.size():
		send(&"_begin_race", 0, [], true)
		_begin_race()

@rpc("authority", "call_remote", "reliable")
func _begin_race() -> void:
	running = true
	if race != null:
		race.begin()

## Rate-limited (spec 6) against a runaway/hostile peer flooding input; `race`
## resolves the slot from the RPC sender id, so spoofing another slot is impossible.
@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _receive_input(data: Dictionary) -> void:
	var sender: int = _verified_sender()
	if sender < 0 or not running or race == null:
		return
	if not _input_limiter.allow(sender, now()):
		return
	_loss.observe(sender, NetLossEstimator.batch_tick(data), now())
	race.receive_input(sender, data)

@rpc("authority", "call_remote", "unreliable_ordered", 2)
func _snapshot(bytes: PackedByteArray) -> void:
	var snapshot: RaceSnapshot = RaceSnapshot.unpack(bytes)
	if snapshot != null and race != null:
		_loss.observe(SERVER_ID, snapshot.tick, now())
		snapshot_received.emit(snapshot)

@rpc("authority", "call_remote", "reliable")
func _event(kind: String, args: Array) -> void:
	if race != null:
		event_received.emit(kind, args)

@rpc("any_peer", "call_remote", "reliable")
func _ping(sent: float) -> void:
	var id: int = _verified_sender()
	if id > 0:
		send(&"_pong", id, [sent, now()], true)

@rpc("authority", "call_remote", "reliable")
func _pong(sent: float, server: float) -> void:
	clock.observe(sent, server, now())

func _peer_disconnected(id: int) -> void:
	if _closing:
		return
	if id == SERVER_ID:
		_server_disconnected()
		return
	if not multiplayer.is_server():
		return
	_input_limiter.remove(id)
	_selection_limiter.remove(id)
	_loss.remove(id)
	_gate.remove(id)
	if _roster.waiting_has(id):
		_roster.remove(id)
		return
	if automated and race != null and race.manager.get_state() == RaceState.RESULTS:
		return # Test peers may depart after the results/metrics handshake.
	if started:
		send(&"_player_left", 0, [id], true)
		_player_left(id)
	else:
		_roster.remove(id)
		_roster.broadcast_lobby()

@rpc("authority", "call_remote", "reliable")
func _player_left(id: int) -> void:
	if race == null:
		if not _pending_departures.has(id):
			_pending_departures.append(id)
		return
	var index: int = _roster.index_of(id)
	if index < 0:
		return
	race.remove_player(index)
	players.remove_at(index)
	_roster.loaded.erase(id)
	lobby_changed.emit()
	if multiplayer.is_server() and not running and _roster.loaded.size() == players.size():
		send(&"_begin_race", 0, [], true)
		_begin_race()

func _connection_failed() -> void:
	_session_ended("Could not connect to host.")

func _server_disconnected() -> void:
	_session_ended("Host disconnected.")

@rpc("authority", "call_remote", "reliable")
func _session_ended(message: String) -> void:
	if _closing:
		return
	GameState.network_message = message
	disconnected.emit(message)
	close()
	if not automated:
		get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")

## Broadened beyond `automated` so a dedicated server can relay "test_done" to automated test clients joining it; a no-op otherwise.
@rpc("any_peer", "call_remote", "reliable")
func _test_report(report: Dictionary) -> void:
	if _verified_sender() > 0:
		test_report_received.emit(report)

func _exit_tree() -> void:
	conditions.clear()
	if peer != null:
		peer.close()
