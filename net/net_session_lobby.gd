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
## Validated peers that joined during a dedicated-server race. They remain in
## the lobby scene as spectators and move into the roster on the next round.
var waiting: Array[Dictionary] = []
## True between `_prepare_race` and the race scene binding itself.
var preparing: bool = false
var _session: NetSession
## Last `_session._clock_ticks` value a `broadcast_lobby()` call actually
## sent on, so a burst of triggers within one physics tick (backlog item 6:
## a looping `_selection` RPC) coalesces to a single reliable broadcast.
var _broadcast_tick: int = -1


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
	waiting.clear()
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
	if index_of(id) >= 0 or waiting_has(id):
		return false
	_session.players.append(new_row(id, ready))
	return true


## Queues a validated mid-race peer without changing active kart slots.
func add_waiting(id: int) -> bool:
	if index_of(id) >= 0 or waiting_has(id):
		return false
	waiting.append(new_row(id, false))
	return true


## Returns whether `id` is admitted for the next lobby but not this race.
func waiting_has(id: int) -> bool:
	for row: Dictionary in waiting:
		if int(row["peer"]) == id:
			return true
	return false


## Moves spectators into the next lobby, preserving their connection/order.
func promote_waiting() -> void:
	for row: Dictionary in waiting:
		_session.players.append(row)
	waiting.clear()


func remove(id: int) -> void:
	var index: int = index_of(id)
	if index >= 0:
		_session.players.remove_at(index)
	for waiting_index: int in range(waiting.size() - 1, -1, -1):
		if int(waiting[waiting_index]["peer"]) == id:
			waiting.remove_at(waiting_index)


## Replaces the whole roster from an authoritative broadcast, truncating to
## `RaceSnapshot.MAX_KARTS` rows: an oversized roster from a hostile/buggy
## authority must not leave `apply_race_settings` a negative ai_count ceiling.
func replace(source: Array) -> void:
	var bounded: Array = source.duplicate(true)
	if bounded.size() > RaceSnapshot.MAX_KARTS:
		bounded.resize(RaceSnapshot.MAX_KARTS)
	_session.players.assign(bounded)


## Admits or queues a freshly handshaked peer. Moved from
## `NetSession._admit_peer` (kept there as a 1-line wrapper) to pay for the
## 400-line rule when the rate-limit/cache fixes below landed in the same
## commit. A connected peer is not a joined player yet: no roster row/kart
## until its handshake passes, and it is kicked if it never sends one.
func admit_peer(id: int) -> void:
	var ok: bool = add_waiting(id) if _session.started else add(id, _session.automated)
	if not ok:
		return
	NetTuning.widen_peer_timeout(_session.peer, id) # Finding 1: only once admitted — an unauthenticated peer keeps ENet's default ~5s timeout so it can't squat a connection slot on the widened one.
	print("SERVER_ADMIT peer=%d" % id)
	_session.send(&"_admitted", id, [_session.started], true)
	if not _session.started:
		broadcast_lobby()


## Sends the reason first, then defers the disconnect via KICK_GRACE_SECONDS
## (spec item 1); a no-op once queued so a resend can't delay it. Moved from
## `NetSession._reject_peer` for the same 400-line-budget reason as
## `admit_peer`. `_session._deliver_reject` stays virtual-dispatched here
## (test_net_internet.gd's GateSession overrides it).
func reject_peer(id: int, message: String) -> void:
	if _session._gate.is_kicking(id):
		return
	print("SERVER_REJECT peer=%d reason=%s" % [id, message])
	_session._deliver_reject(id, message)
	remove(id)
	_session._input_limiter.remove(id)
	_session._selection_limiter.remove(id)
	_session._loss.remove(id)
	_session._gate.remove(id)
	_session._gate.queue_kick(id, NetSession.now())
	broadcast_lobby()


## Coalesces repeated triggers (a looping `_selection` RPC, several peers
## admitted/rejected in the same tick, ...) to at most one reliable `_lobby`
## send per physics tick (backlog item 6), keyed off the session's own
## `_clock_ticks` counter, which only `_physics_process` advances.
func broadcast_lobby() -> void:
	if _broadcast_tick == _session._clock_ticks:
		return
	_broadcast_tick = _session._clock_ticks
	_session.send(&"_lobby", 0, [_session.players, _session.laps, _session.ai_count, _session.track_id, _session.difficulty_id], true)
	_session.lobby_changed.emit()


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
	_session.peer.refuse_new_connections = not _session.dedicated
	_session.send(&"_prepare_race", 0, _prepare_args(), true)
	_session._prepare_race(_session.players, _session.ai_count, _session.laps, _session.seed, _session.track_id, _session.difficulty_id)
	return true


## Repeats preparation only for peers whose scene-load acknowledgement is missing.
func retry_start() -> void:
	if not _session.multiplayer.is_server() or not _session.started or _session.running:
		return
	for row: Dictionary in _session.players:
		var id: int = int(row["peer"])
		if id != NetSession.SERVER_ID and not loaded.has(id):
			_session.send(&"_prepare_race", id, _prepare_args(), true)


## Reopens the lobby after RESULTS for any server (listen or dedicated),
## keeping already-connected peers on the same ENet session and promoting
## mid-race "waiting" joiners into the roster (spec item 3).
func restart_to_lobby() -> void:
	if not _session.multiplayer.is_server():
		return
	clear_race_state()
	_session.peer.refuse_new_connections = false
	promote_waiting()
	for row: Dictionary in _session.players:
		row["ready"] = false
	_session.send(&"_return_to_lobby", 0, [_session.players], true)
	# Review finding 7: a mid-race joiner promoted above only just received a
	# roster row, never the host's laps/bots/track/difficulty — without this,
	# its controls stick on NetSession's constructor defaults instead of the
	# real settings until the host happens to change one. Also covers the
	# `lobby_changed` emit this used to do directly.
	broadcast_lobby()


## Clears every per-race flag while preserving the connected peer roster.
func clear_race_state() -> void:
	_session.started = false
	_session.running = false
	_session.race = null
	preparing = false
	loaded.clear()


## Host-only: updates laps/bots/track/difficulty and rebroadcasts the lobby
## so every client's UI reflects the host's choice (spec item 1). Ignored
## once the race has started, since `_prepare_race` owns those fields then.
func set_race_options(new_laps: int, new_ai_count: int, new_track_id: String, new_difficulty_id: String) -> void:
	if not _session.multiplayer.is_server() or _session.started:
		return
	apply_race_settings(new_laps, new_ai_count, new_track_id, new_difficulty_id)
	broadcast_lobby()


## Raw setter shared by `_lobby` and `_prepare_race` (spec item 1): both
## receive the same four host-chosen fields over their own RPC already.
## Clamps laps/bots itself (review finding 3) so every caller — including a
## hostile `_lobby`/`_prepare_race` payload — is bounded the same way, and
## the bot cap always reads the roster this call just saw: callers that
## replace the roster do so before reaching here, so a mid-race-promoted
## joiner's post-replace roster is what gets evaluated, never a stale
## pre-replace count that could let `slots + ai_count` exceed
## `RaceSnapshot.MAX_KARTS` and desync that peer for the whole race.
func apply_race_settings(new_laps: int, new_ai_count: int, new_track_id: String, new_difficulty_id: String) -> void:
	_session.laps = clampi(new_laps, 1, 9)
	_session.ai_count = clampi(new_ai_count, 0, maxi(0, RaceSnapshot.MAX_KARTS - _session.players.size()))
	_session.track_id = new_track_id
	_session.difficulty_id = new_difficulty_id


## `_lobby`'s full body: replaces the roster and applies the host's fields.
func apply_lobby(roster: Array, new_laps: int, new_ai_count: int, new_track_id: String, new_difficulty_id: String) -> void:
	replace(roster)
	apply_race_settings(new_laps, new_ai_count, new_track_id, new_difficulty_id)


## `_prepare_race`'s roster/lobby half: marks preparation started, replaces
## the roster and applies the host's fields together (spec item 1).
func begin_prepare(roster: Array, new_laps: int, new_ai_count: int, new_track_id: String, new_difficulty_id: String) -> void:
	preparing = true
	replace(roster)
	apply_race_settings(new_laps, new_ai_count, new_track_id, new_difficulty_id)


func _prepare_args() -> Array:
	return [_session.players, _session.ai_count, _session.laps, _session.seed, _session.track_id, _session.difficulty_id]
