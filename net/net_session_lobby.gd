class_name NetSessionLobby
extends RefCounted

## The session's lobby half: the server-owned player roster (one row per
## joined peer) plus the race start / retry / restart-to-lobby sequencing that
## reads it. Split out of NetSession — which keeps transport, the handshake
## and the race-time RPCs — so both files stay inside the project's 400-line
## budget and the roster rules stay readable on their own.
##
## Every roster mutation happens in place through this class. Never rebuild
## `players` with `Array.filter` or an `a if c else b` ternary: both yield an
## untyped `Array`, which cannot be assigned back to `Array[Dictionary]` and
## aborts `host()` with a runtime type error (Phase 16 gate breaker).

## Peers whose race scene has finished loading, keyed by peer id.
var loaded: Array[int] = []
## True between `_prepare_race` and the race scene binding itself.
var preparing: bool = false
var _session: NetSession


func attach(session: NetSession) -> void:
	_session = session


## ENet client slots to open for `max_players`. A listen server spends one of
## them on its own host row; a dedicated server takes none (spec item 3), so
## `--max-players 8` really admits 8 clients there instead of 7.
static func connection_slots(max_players: int, dedicated: bool) -> int:
	return max_players - (0 if dedicated else 1)


## Rebuilds the roster for a freshly opened server. A dedicated server takes
## no row at all (spec item 3): it drives no kart.
func reset_for_host(dedicated: bool, ready: bool) -> void:
	_session.players.clear()
	if not dedicated:
		_session.players.append(new_row(NetSession.SERVER_ID, ready))


func new_row(id: int, ready: bool) -> Dictionary:
	return {"peer": id, "driver": NetContentCatalog.default_driver_id(),
		"kart": NetContentCatalog.default_kart_id(), "ready": ready}


## Roster position of `id`, or -1 when it holds no row.
func index_of(id: int) -> int:
	for index: int in range(_session.players.size()):
		if int(_session.players[index]["peer"]) == id:
			return index
	return -1


## Appends a row for a newly admitted peer; false when it already had one.
func add(id: int, ready: bool) -> bool:
	if index_of(id) >= 0:
		return false
	_session.players.append(new_row(id, ready))
	return true


func remove(id: int) -> void:
	var index: int = index_of(id)
	if index >= 0:
		_session.players.remove_at(index)


## Replaces the whole roster from an authoritative broadcast.
func replace(source: Array) -> void:
	_session.players.assign(source.duplicate(true))


## Applies one peer's driver/kart/ready choice; false when it has no row.
func update(id: int, driver: String, kart: String, ready: bool) -> bool:
	var index: int = index_of(id)
	if index < 0:
		return false
	_session.players[index]["driver"] = driver
	_session.players[index]["kart"] = kart
	_session.players[index]["ready"] = ready
	return true


## Starts once every participant is ready (two-to-four for a listen server,
## one-plus for a dedicated server, since it occupies no row itself); late
## joins are refused. `force` skips the all-ready check (dedicated server
## grace-timeout auto-start, spec item 3).
func start_race(force: bool) -> bool:
	if not _session.multiplayer.is_server() or _session.started:
		return false
	if _session.players.size() < (1 if _session.dedicated else 2):
		return false
	if not force:
		for row: Dictionary in _session.players:
			if not bool(row["ready"]):
				return false
	_session.started = true
	_session.peer.refuse_new_connections = true
	_session.send(&"_prepare_race", 0, _prepare_args(), true)
	_session._prepare_race(_session.players, _session.ai_count, _session.laps, _session.seed, _session.track_id)
	return true


## Repeats preparation only for peers whose scene-load acknowledgement is missing.
func retry_start() -> void:
	if not _session.multiplayer.is_server() or not _session.started or _session.running:
		return
	for row: Dictionary in _session.players:
		var id: int = int(row["peer"])
		if id != NetSession.SERVER_ID and not loaded.has(id):
			_session.send(&"_prepare_race", id, _prepare_args(), true)


## Dedicated-server-only: reopens the lobby after RESULTS, keeping already-
## connected peers on the same ENet session (spec item 3).
func restart_to_lobby() -> void:
	if not _session.multiplayer.is_server() or not _session.dedicated:
		return
	_session.started = false
	_session.running = false
	_session.race = null
	preparing = false
	loaded.clear()
	_session.peer.refuse_new_connections = false
	for row: Dictionary in _session.players:
		row["ready"] = false
	_session.send(&"_lobby", 0, [_session.players], true)
	_session.lobby_changed.emit()


func _prepare_args() -> Array:
	return [_session.players, _session.ai_count, _session.laps, _session.seed, _session.track_id]
