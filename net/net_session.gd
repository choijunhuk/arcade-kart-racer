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
var _loaded: Array[int] = []
var _pending_departures: Array[int] = []
var _clock_ticks: int = 0
var _closing: bool = false
var _preparing: bool = false

func _ready() -> void:
	multiplayer.peer_connected.connect(_peer_connected)
	multiplayer.peer_disconnected.connect(_peer_disconnected)
	multiplayer.connected_to_server.connect(_connected)
	multiplayer.connection_failed.connect(_connection_failed)
	multiplayer.server_disconnected.connect(_server_disconnected)

## Opens a listen server, with no TLS or extra autoload. `dedicated` must be
## set before calling so a headless server never occupies a player row.
func host(port: int = NetTuning.PORT, max_players_value: int = NetTuning.MAX_PLAYERS) -> Error:
	peer = ENetMultiplayerPeer.new()
	var error: Error = peer.create_server(port, max_players_value - 1, NetTuning.CHANNEL_COUNT)
	if error != OK:
		return error
	multiplayer.multiplayer_peer = peer
	GameState.is_networked = true
	max_players = max_players_value
	players = [] if dedicated else [_new_player(SERVER_ID)]
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
		_password_attempt_hash = password.sha256_text() if not password.is_empty() else ""
	return error

## Sets the session password as its hash only (spec item 6: hashed compare,
## never logged). Pass "" to clear (no password required).
func set_password(plain: String) -> void:
	password_hash = plain.sha256_text() if not plain.is_empty() else ""

## Resolves this process's grid index from the server-owned roster.
func local_slot() -> int:
	for index: int in range(players.size()):
		if int(players[index]["peer"]) == multiplayer.get_unique_id():
			return index
	return -1

## Sends only our selection; the server derives ownership from the RPC sender.
func select(driver: String, kart: String, ready: bool) -> void:
	if multiplayer.is_server():
		_update_player(SERVER_ID, driver, kart, ready)
	else:
		send(&"_selection", SERVER_ID, [driver, kart, ready], true)

## Starts once every participant is ready (two-to-four for a listen server,
## one-plus for a dedicated server, since it occupies no row itself); late
## joins are refused. `force` skips the all-ready check (dedicated server
## grace-timeout auto-start, spec item 3).
func start_race(force: bool = false) -> bool:
	if not multiplayer.is_server() or started or players.size() < (1 if dedicated else 2):
		return false
	if not force:
		for row: Dictionary in players:
			if not bool(row["ready"]):
				return false
	started = true
	peer.refuse_new_connections = true
	send(&"_prepare_race", 0, [players, ai_count, laps, seed, track_id], true)
	_prepare_race(players, ai_count, laps, seed, track_id)
	return true

## Repeats preparation only for peers whose scene-load acknowledgement is missing.
func retry_start() -> void:
	if not multiplayer.is_server() or not started or running:
		return
	for row: Dictionary in players:
		var id: int = int(row["peer"])
		if id != SERVER_ID and not _loaded.has(id):
			send(&"_prepare_race", id, [players, ai_count, laps, seed, track_id], true)

## Dedicated-server-only: reopens the lobby after RESULTS, keeping already-
## connected peers on the same ENet session (spec item 3).
func restart_to_lobby() -> void:
	if not multiplayer.is_server() or not dedicated:
		return
	started = false
	running = false
	race = null
	_preparing = false
	_loaded.clear()
	peer.refuse_new_connections = false
	for row: Dictionary in players:
		row["ready"] = false
	send(&"_lobby", 0, [players], true)
	lobby_changed.emit()

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
	if not multiplayer.is_server() and _clock_ticks % NetTuning.CLOCK_INTERVAL == 0:
		send(&"_ping", SERVER_ID, [now()], true)
	if automated and not started and multiplayer.is_server() and players.size() >= 2:
		start_race()

func _deliver(method: StringName, target: int, args: Array, reliable: bool) -> void:
	if not reliable:
		var bytes: int = var_to_bytes(args).size() + NetTuning.RPC_OVERHEAD_BYTES
		if bytes > NetTuning.MAX_UNRELIABLE_BYTES:
			push_error("Unreliable RPC %s exceeds %d bytes (%d including framing reserve); not sent" % [method, NetTuning.MAX_UNRELIABLE_BYTES, bytes])
			return
	if peer != null and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		if target != 0 and not multiplayer.get_peers().has(target):
			return
		rpc_id.callv([target, method] + args)

func _new_player(id: int) -> Dictionary:
	return {"peer": id, "driver": NetContentCatalog.default_driver_id(),
		"kart": NetContentCatalog.default_kart_id(), "ready": automated}

func _peer_connected(id: int) -> void:
	if not multiplayer.is_server() or started:
		return
	players.append(_new_player(id))
	_broadcast_lobby()

func _connected() -> void:
	send(&"_ping", SERVER_ID, [now()], true)
	send(&"_handshake", SERVER_ID, [String(ProjectSettings.get_setting("application/config/version", "")), _password_attempt_hash], true)
	if automated:
		var row: Dictionary = _new_player(multiplayer.get_unique_id())
		select(row["driver"], row["kart"], true)

func _update_player(id: int, driver: String, kart: String, ready: bool) -> void:
	if started or not NetContentCatalog.has(LocalLobby.DRIVER_DIRECTORY, driver) or not NetContentCatalog.has(LocalLobby.KART_DIRECTORY, kart):
		return
	for row: Dictionary in players:
		if int(row["peer"]) == id:
			row["driver"] = driver
			row["kart"] = kart
			row["ready"] = ready
	_broadcast_lobby()

func _broadcast_lobby() -> void:
	send(&"_lobby", 0, [players], true)
	lobby_changed.emit()

@rpc("any_peer", "call_remote", "reliable")
func _selection(driver: String, kart: String, ready: bool) -> void:
	if multiplayer.is_server():
		_update_player(multiplayer.get_remote_sender_id(), driver, kart, ready)

@rpc("authority", "call_remote", "reliable")
func _lobby(roster: Array) -> void:
	players.assign(roster.duplicate(true))
	lobby_changed.emit()

@rpc("authority", "call_remote", "reliable")
func _prepare_race(roster: Array, bots: int, lap_count: int, race_seed: int, race_track_id: String = "") -> void:
	if _preparing or race != null:
		if not multiplayer.is_server() and race != null:
			send(&"_race_loaded", SERVER_ID, [], true)
		return
	_preparing = true
	players.assign(roster.duplicate(true))
	ai_count = clampi(bots, 0, RaceSnapshot.MAX_KARTS - players.size())
	laps = clampi(lap_count, 1, 9)
	seed = race_seed
	track_id = race_track_id
	started = true
	var slots: Array[PlayerSlot] = []
	for index: int in range(players.size()):
		var slot: PlayerSlot = PlayerSlot.new()
		slot.grid_slot = index
		slot.device_id = index - 1
		slot.driver_id = StringName(players[index]["driver"])
		slot.kart_id = StringName(players[index]["kart"])
		slots.append(slot)
	var config: RaceConfig = RaceConfigBuilder.build_local(slots, NetContentCatalog.resolve_track(race_track_id), LocalLobby.DEFAULT_DIFFICULTY, slots.size() + ai_count)
	config.laps = laps
	config.seed = seed
	GameState.pending_race_config = config
	GameState.current_mode = GameState.Mode.RACE
	get_tree().change_scene_to_file.call_deferred(RACE_PATH)

## Validates a newly connected peer's version/password (spec item 6);
## rejection never logs the password itself.
@rpc("any_peer", "call_remote", "reliable")
func _handshake(client_version: String, password_attempt: String) -> void:
	if not multiplayer.is_server():
		return
	var id: int = multiplayer.get_remote_sender_id()
	var expected_version: String = String(ProjectSettings.get_setting("application/config/version", ""))
	var reason: String = NetHandshake.reject_reason(client_version, expected_version, password_attempt, password_hash)
	if not reason.is_empty():
		_reject_peer(id, reason)

func _reject_peer(id: int, message: String) -> void:
	send(&"_session_ended", id, [message], true)
	players = players.filter(func(row: Dictionary) -> bool: return int(row["peer"]) != id)
	_input_limiter.remove(id)
	_broadcast_lobby()
	multiplayer.disconnect_peer(id)

@rpc("any_peer", "call_remote", "reliable")
func _race_loaded() -> void:
	if multiplayer.is_server():
		_mark_loaded(multiplayer.get_remote_sender_id())

func _mark_loaded(id: int) -> void:
	var known: bool = false
	for row: Dictionary in players:
		known = known or int(row["peer"]) == id
	if not known or _loaded.has(id):
		return
	_loaded.append(id)
	if _loaded.size() == players.size():
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
	if not multiplayer.is_server() or not running or race == null:
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if not _input_limiter.allow(sender, now()):
		return
	race.receive_input(sender, data)

@rpc("authority", "call_remote", "unreliable_ordered", 2)
func _snapshot(bytes: PackedByteArray) -> void:
	var snapshot: RaceSnapshot = RaceSnapshot.unpack(bytes)
	if snapshot != null and race != null:
		snapshot_received.emit(snapshot)

@rpc("authority", "call_remote", "reliable")
func _event(kind: String, args: Array) -> void:
	if race != null:
		event_received.emit(kind, args)

@rpc("any_peer", "call_remote", "reliable")
func _ping(sent: float) -> void:
	if multiplayer.is_server():
		send(&"_pong", multiplayer.get_remote_sender_id(), [sent, now()], true)

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
	if automated and race != null and race.manager.get_state() == RaceState.RESULTS:
		return # Test peers may depart after the results/metrics handshake.
	if started:
		send(&"_player_left", 0, [id], true)
		_player_left(id)
	else:
		players = players.filter(func(row: Dictionary) -> bool: return int(row["peer"]) != id)
		_broadcast_lobby()

@rpc("authority", "call_remote", "reliable")
func _player_left(id: int) -> void:
	if race == null:
		if not _pending_departures.has(id):
			_pending_departures.append(id)
		return
	for index: int in range(players.size()):
		if int(players[index]["peer"]) != id:
			continue
		if race != null:
			race.remove_player(index)
		players.remove_at(index)
		_loaded.erase(id)
		lobby_changed.emit()
		if multiplayer.is_server() and not running and race != null and _loaded.size() == players.size():
			send(&"_begin_race", 0, [], true)
			_begin_race()
		return

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
	if multiplayer.is_server():
		test_report_received.emit(report)

func _exit_tree() -> void:
	conditions.clear()
	if peer != null:
		peer.close()
