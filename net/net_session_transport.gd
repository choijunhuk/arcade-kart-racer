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
func service_peers() -> void:
	for id: int in _session._gate.take_kicks():
		if _session.multiplayer.get_peers().has(id):
			_session.multiplayer.disconnect_peer(id)
	for id: int in _session._gate.expired(NetSession.now()):
		_session._reject_peer(id, "Handshake timed out.")
