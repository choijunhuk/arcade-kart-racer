class_name NetSessionTransport
extends RefCounted

## Queued RPC delivery and peer-handshake servicing for one NetSession.

var _session: NetSession


func attach(session: NetSession) -> void:
	_session = session


## Queues a real RPC through the session's optional delay and loss model.
func send(method: StringName, target: int, args: Array, reliable: bool) -> void:
	_session.conditions.enqueue(
		NetSession.now(), reliable, deliver.bind(method, target, args, reliable),
	)


## Rejects oversized unreliable payloads, departed targets, and closed peers.
func deliver(method: StringName, target: int, args: Array, reliable: bool) -> void:
	if not reliable and not NetTuning.fits_unreliable(method, args):
		return
	if _session.peer != null and _session.peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		if target != 0 and not _session.multiplayer.get_peers().has(target):
			return
		_session.rpc_id.callv([target, method] + args)


## Drains deferred kicks and rejects peers whose handshake deadline elapsed.
## Kicks are always a reject/handshake-timeout outcome (never a normal leave),
## so they force the disconnect rather than waiting on the peer's own ack —
## a half-open or hostile peer would otherwise keep its connection slot for
## the full widened timeout instead of dropping immediately (finding 2).
func service_peers() -> void:
	for id: int in _session._gate.take_kicks(NetSession.now()):
		if _session.peer != null and _session.multiplayer.get_peers().has(id):
			_session.peer.disconnect_peer(id, true)
	for id: int in _session._gate.expired(NetSession.now()):
		_session._reject_peer(id, "Handshake timed out.")


## Host-only: reopens the ENet listener to new connections once the lobby
## scene is genuinely active again (finding: lobby-reopen connection window).
## Called from the lobby scene's own rebind path, never automatically by
## `NetSession.restart_to_lobby()` — see its doc comment. Guarded explicitly
## (review finding 4), not just by callers already clearing `started`/`race`
## first; moved from NetSession itself (400-line budget). push_warning when
## the guard refuses (review finding 6), so a caller that assumed it ran
## doesn't fail silently.
func reopen_connections() -> void:
	if _session.multiplayer.is_server() and _session.peer != null and not _session.started and _session.race == null:
		_session.peer.refuse_new_connections = false
	else:
		push_warning("reopen_connections() refused: server=%s peer_set=%s started=%s race_active=%s" % [_session.multiplayer.is_server(), _session.peer != null, _session.started, _session.race != null])
