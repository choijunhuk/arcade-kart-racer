class_name NetSession
extends Node

## Persistent GameState child. Only the server mutates lobby and starts a race.
signal lobby_changed()
signal disconnected(message: String)
signal test_report_received(report: Dictionary)
signal snapshot_received(snapshot: RaceSnapshot)
signal event_received(kind: String, args: Array)

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
## Dedicated headless server (spec item 3): occupies no player row/kart.
## Independent of `automated` ("this is a scripted test harness").
var dedicated: bool = false
var max_players: int = NetTuning.MAX_PLAYERS
## "" keeps the default track; only the dedicated server CLI sets this.
var track_id: String = ""
## SHA-256 of the session password ("" = none); plaintext is never stored
## or logged (spec item 6).
var password_hash: String = ""
var _password_attempt_hash: String = ""
var _input_limiter: NetRateLimiter = NetRateLimiter.new()
var _gate: NetPeerGate = NetPeerGate.new()
var _loss: NetLossEstimator = NetLossEstimator.new()
var _roster: NetSessionLobby = NetSessionLobby.new()
var _pending_departures: Array[int] = []
var _clock_ticks: int = 0
var _closing: bool = false

func _init() -> void:
	_roster.attach(self)

func _ready() -> void:
	multiplayer.peer_connected.connect(_peer_connected)
	multiplayer.peer_disconnected.connect(_peer_disconnected)
	multiplayer.connected_to_server.connect(_connected)
	multiplayer.connection_failed.connect(_connection_failed)
	multiplayer.server_disconnected.connect(_server_disconnected)

## Opens a listen server, with no TLS or extra autoload. `dedicated` must be
## set before calling so a headless server never occupies a player row — and
## therefore never reserves an ENet slot either, so `--max-players 8` really
## admits 8 clients on a dedicated server and 7 plus the host on a listen one.
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

## Connects to the supplied address (LAN or internet host); completion
## arrives through lobby_changed. `password` is hashed locally, never sent
## or logged in cleartext (spec item 6).
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

## Real transport loss (0.0-1.0) measured from sequence gaps over a 2 s
## window: snapshot ticks on a client, per-peer input-packet ticks on the
## server (spec item 5). Unlike `conditions.dropped` this counts traffic that
## actually went missing, not the synthetic drops this process injected.
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

## Repeats preparation only for peers whose scene-load acknowledgement is missing.
func retry_start() -> void:
	_roster.retry_start()

## Dedicated-server-only: reopens the lobby after RESULTS (spec item 3).
func restart_to_lobby() -> void:
	_roster.restart_to_lobby()

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
	conditions.enqueue(now(), reliable, _deliver.bind(method, target, args, reliable))

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
	if not reliable and not NetTuning.fits_unreliable(method, args):
		return
	if peer != null and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		if target != 0 and not multiplayer.get_peers().has(target):
			return
		rpc_id.callv([target, method] + args)

## Server tick: drains the deferred kicks queued a tick earlier (so their
## reason RPC has flushed, spec item 1) and rejects every peer that let its
## handshake deadline lapse (spec item 6).
func _service_peers() -> void:
	for id: int in _gate.take_kicks():
		if multiplayer.get_peers().has(id):
			multiplayer.disconnect_peer(id)
	for id: int in _gate.expired(now()):
		_reject_peer(id, "Handshake timed out.")

## A connected peer is not a joined player yet: it holds no roster row (and so
## no kart) until its handshake passes, and is kicked if it never sends one.
func _peer_connected(id: int) -> void:
	if not multiplayer.is_server():
		return
	# Track unconditionally: a peer whose connection lands after the race has
	# started must still get a deadline, otherwise it holds a slot forever
	# without ever handshaking (and so never becomes kickable).
	_gate.track(id, now())
	if started:
		_reject_peer(id, "Match already started.")

func _admit_peer(id: int) -> void:
	if not started and _roster.add(id, automated):
		_broadcast_lobby()

func _connected() -> void:
	send(&"_ping", SERVER_ID, [now()], true)
	send(&"_handshake", SERVER_ID, [String(ProjectSettings.get_setting("application/config/version", "")), _password_attempt_hash], true)
	if automated:
		var row: Dictionary = _roster.new_row(multiplayer.get_unique_id(), true)
		select(row["driver"], row["kart"], true)

func _update_player(id: int, driver: String, kart: String, ready: bool) -> void:
	if started or not NetContentCatalog.has(LocalLobby.DRIVER_DIRECTORY, driver) or not NetContentCatalog.has(LocalLobby.KART_DIRECTORY, kart):
		return
	if _roster.update(id, driver, kart, ready):
		_broadcast_lobby()

func _broadcast_lobby() -> void:
	send(&"_lobby", 0, [players], true)
	lobby_changed.emit()

## Sender id of the `any_peer` RPC being handled, or -1 when this process is
## not the server or the sender has not passed the handshake yet (spec item
## 6: every packet from an unverified peer is dropped, not just its inputs).
func _verified_sender() -> int:
	var id: int = _sender()
	return id if multiplayer.is_server() and _gate.allows(id) else -1

func _sender() -> int:
	return multiplayer.get_remote_sender_id()

@rpc("any_peer", "call_remote", "reliable")
func _selection(driver: String, kart: String, ready: bool) -> void:
	var id: int = _verified_sender()
	if id > 0:
		_update_player(id, driver, kart, ready)

@rpc("authority", "call_remote", "reliable")
func _lobby(roster: Array) -> void:
	_roster.replace(roster)
	lobby_changed.emit()

@rpc("authority", "call_remote", "reliable")
func _prepare_race(roster: Array, bots: int, lap_count: int, race_seed: int, race_track_id: String = "") -> void:
	if _roster.preparing or race != null:
		if not multiplayer.is_server() and race != null:
			send(&"_race_loaded", SERVER_ID, [], true)
		return
	_roster.preparing = true
	_roster.replace(roster)
	ai_count = clampi(bots, 0, RaceSnapshot.MAX_KARTS - players.size())
	laps = clampi(lap_count, 1, 9)
	seed = race_seed
	track_id = race_track_id
	started = true
	GameState.pending_race_config = NetRaceSetup.build(players, ai_count, laps, seed, track_id)
	GameState.current_mode = GameState.Mode.RACE
	get_tree().change_scene_to_file.call_deferred(RACE_PATH)

## Validates a newly connected peer's version/password (spec item 6);
## rejection never logs the password itself. Only a peer that gets here with
## an acceptable handshake earns a roster row.
@rpc("any_peer", "call_remote", "reliable")
func _handshake(client_version: String, password_attempt: String) -> void:
	var id: int = _sender()
	if not multiplayer.is_server() or _gate.allows(id):
		return
	var expected_version: String = String(ProjectSettings.get_setting("application/config/version", ""))
	var reason: String = NetHandshake.reject_reason(client_version, expected_version, password_attempt, password_hash)
	if not reason.is_empty():
		_reject_peer(id, reason)
	elif _gate.verify(id):
		_admit_peer(id)

## Sends the real reason straight out (bypassing the debug delay queue, which
## would otherwise be skipped once the peer has left `get_peers()`), then
## defers the disconnect by a tick so ENet flushes it: the peer sees why it
## was refused instead of a bare "Host disconnected" (spec item 1).
func _reject_peer(id: int, message: String) -> void:
	_deliver_reject(id, message)
	_roster.remove(id)
	_input_limiter.remove(id)
	_loss.remove(id)
	_gate.remove(id)
	_gate.queue_kick(id)
	_broadcast_lobby()

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

## Rate-limited (spec item 6) against a runaway/hostile peer flooding input.
## A sender can only ever supply input for its own roster slot: `race`
## resolves the slot from the RPC sender id, never client-sent data, so
## spoofing another slot is already structurally impossible (see
## NetRace._receive_input_frame).
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
	_loss.remove(id)
	_gate.remove(id)
	if automated and race != null and race.manager.get_state() == RaceState.RESULTS:
		return # Test peers may depart after the results/metrics handshake.
	if started:
		send(&"_player_left", 0, [id], true)
		_player_left(id)
	else:
		_roster.remove(id)
		_broadcast_lobby()

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

## Broadened beyond `automated` so a dedicated server (never automated,
## spec item 3) can relay the "test_done" ack to automated test clients
## joining it (tools/run_server_test.sh); a no-op for real play otherwise.
@rpc("any_peer", "call_remote", "reliable")
func _test_report(report: Dictionary) -> void:
	if _verified_sender() > 0:
		test_report_received.emit(report)

func _exit_tree() -> void:
	conditions.clear()
	if peer != null:
		peer.close()
