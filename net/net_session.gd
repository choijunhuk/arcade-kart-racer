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
var _loaded: Array[int] = []
var _pending_departures: Array[int] = []
var _clock_ticks: int = 0
var _closing: bool = false

func _ready() -> void:
	multiplayer.peer_connected.connect(_peer_connected)
	multiplayer.peer_disconnected.connect(_peer_disconnected)
	multiplayer.connected_to_server.connect(_connected)
	multiplayer.connection_failed.connect(_connection_failed)
	multiplayer.server_disconnected.connect(_server_disconnected)

## Opens a LAN listen server, with no TLS or extra autoload.
func host(port: int = NetTuning.PORT) -> Error:
	peer = ENetMultiplayerPeer.new()
	var error: Error = peer.create_server(port, NetTuning.MAX_PLAYERS - 1, NetTuning.CHANNEL_COUNT)
	if error != OK:
		return error
	multiplayer.multiplayer_peer = peer
	GameState.is_networked = true
	players = [_new_player(SERVER_ID)]
	lobby_changed.emit()
	return OK

## Connects to the supplied LAN address; completion arrives through lobby_changed.
func join(ip: String, port: int = NetTuning.PORT) -> Error:
	peer = ENetMultiplayerPeer.new()
	var error: Error = peer.create_client(ip, port, NetTuning.CHANNEL_COUNT)
	if error == OK:
		multiplayer.multiplayer_peer = peer
		GameState.is_networked = true
	return error

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

## Starts only with two-to-four ready participants; late joins are refused.
func start_race() -> bool:
	if not multiplayer.is_server() or started or players.size() < 2:
		return false
	for row: Dictionary in players:
		if not bool(row["ready"]):
			return false
	started = true
	peer.refuse_new_connections = true
	send(&"_prepare_race", 0, [players, ai_count, laps, seed], true)
	_prepare_race(players, ai_count, laps, seed)
	return true

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
	conditions.enqueue(now(), reliable, _deliver.bind(method, target, args))

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

func _deliver(method: StringName, target: int, args: Array) -> void:
	if peer != null and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		if target != 0 and not multiplayer.get_peers().has(target):
			return
		rpc_id.callv([target, method] + args)

func _new_player(id: int) -> Dictionary:
	var drivers: Array[Resource] = ResourceScanner.scan_tres(LocalLobby.DRIVER_DIRECTORY)
	var karts: Array[Resource] = ResourceScanner.scan_tres(LocalLobby.KART_DIRECTORY)
	return {"peer": id, "driver": String((drivers[0] as DriverData).id),
		"kart": String((karts[0] as KartData).id), "ready": automated}

func _peer_connected(id: int) -> void:
	if not multiplayer.is_server() or started:
		return
	players.append(_new_player(id))
	_broadcast_lobby()

func _connected() -> void:
	send(&"_ping", SERVER_ID, [now()], true)
	if automated:
		var row: Dictionary = _new_player(multiplayer.get_unique_id())
		select(row["driver"], row["kart"], true)

func _update_player(id: int, driver: String, kart: String, ready: bool) -> void:
	if started or not _catalog_has(LocalLobby.DRIVER_DIRECTORY, driver) or not _catalog_has(LocalLobby.KART_DIRECTORY, kart):
		return
	for row: Dictionary in players:
		if int(row["peer"]) == id:
			row["driver"] = driver
			row["kart"] = kart
			row["ready"] = ready
	_broadcast_lobby()

func _catalog_has(directory: String, id: String) -> bool:
	for resource: Resource in ResourceScanner.scan_tres(directory):
		if String(resource.get("id")) == id:
			return true
	return false

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
func _prepare_race(roster: Array, bots: int, lap_count: int, race_seed: int) -> void:
	players.assign(roster.duplicate(true))
	ai_count = clampi(bots, 0, RaceSnapshot.MAX_KARTS - players.size())
	laps = clampi(lap_count, 1, 9)
	seed = race_seed
	started = true
	var slots: Array[PlayerSlot] = []
	for index: int in range(players.size()):
		var slot: PlayerSlot = PlayerSlot.new()
		slot.grid_slot = index
		slot.device_id = index - 1
		slot.driver_id = StringName(players[index]["driver"])
		slot.kart_id = StringName(players[index]["kart"])
		slots.append(slot)
	var config: RaceConfig = RaceConfigBuilder.build_local(slots, LocalLobby.DEFAULT_TRACK, LocalLobby.DEFAULT_DIFFICULTY, slots.size() + ai_count)
	config.laps = laps
	config.seed = seed
	GameState.pending_race_config = config
	GameState.current_mode = GameState.Mode.RACE
	get_tree().change_scene_to_file.call_deferred(RACE_PATH)

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

@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _receive_input(data: Dictionary) -> void:
	if multiplayer.is_server() and running and race != null:
		race.receive_input(multiplayer.get_remote_sender_id(), data)

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

@rpc("any_peer", "call_remote", "reliable")
func _test_report(report: Dictionary) -> void:
	if automated and multiplayer.is_server():
		test_report_received.emit(report)

func _exit_tree() -> void:
	conditions.clear()
	if peer != null:
		peer.close()
