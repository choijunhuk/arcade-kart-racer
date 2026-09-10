class_name NetPeerGate
extends RefCounted

## Server-side handshake enforcement (spec item 6). A peer is UNVERIFIED from
## the instant ENet accepts it until its own `_handshake` RPC passes version
## and password validation: until then it owns no roster row (so no kart) and
## every other RPC it sends is ignored. A peer that never sends a valid
## handshake within DEADLINE_SECONDS is kicked, so simply staying silent is
## not a way past the password/version check.
##
## Also owns the deferred kick queue (spec item 1): a rejection reason is sent
## first and the disconnect is drained one physics tick later, so the peer
## learns the real reason instead of seeing a bare "Host disconnected".
##
## Pure and time-injected; NetSession supplies the clock and performs the RPC
## and disconnect side effects.

const DEADLINE_SECONDS: float = 3.0

var _deadlines: Dictionary[int, float] = {}
var _verified: Dictionary[int, bool] = {}
var _kicks: Array[int] = []


## Starts the handshake deadline for a freshly connected peer.
func track(id: int, now: float) -> void:
	_verified[id] = false
	_deadlines[id] = now + DEADLINE_SECONDS


## Marks a peer's handshake accepted. Returns false when the peer is unknown
## or already verified, so a replayed handshake cannot re-admit it twice.
func verify(id: int) -> bool:
	if not _verified.has(id) or bool(_verified[id]):
		return false
	_verified[id] = true
	_deadlines.erase(id)
	return true


## True only for a peer that has completed the handshake.
func allows(id: int) -> bool:
	return bool(_verified.get(id, false))


## Forgets a peer entirely (disconnected, rejected, or kicked).
func remove(id: int) -> void:
	_deadlines.erase(id)
	_verified.erase(id)
	_kicks.erase(id)


## Peers whose handshake deadline has elapsed, for the caller to reject.
func expired(now: float) -> Array[int]:
	var ids: Array[int] = []
	for id: int in _deadlines.keys():
		if now >= float(_deadlines[id]):
			ids.append(id)
	return ids


## Queues a disconnect to be drained on a later tick, after the reason RPC
## has had a tick to flush.
func queue_kick(id: int) -> void:
	if not _kicks.has(id):
		_kicks.append(id)


## Returns and clears the queued disconnects.
func take_kicks() -> Array[int]:
	var pending: Array[int] = _kicks.duplicate()
	_kicks.clear()
	return pending
