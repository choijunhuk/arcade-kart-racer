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
## Grace window between sending a rejected peer's reason RPC and actually
## disconnecting it. A single physics tick was not always enough for the
## reliable send to really reach the peer before the disconnect landed
## (real-UI testing caught a rejected join seeing a bare "Host disconnected"
## instead of the real reason under real-world scheduling jitter); this
## keeps the reason ahead of the disconnect without leaving the peer
## connected for long.
const KICK_GRACE_SECONDS: float = 1.0

var _deadlines: Dictionary[int, float] = {}
var _verified: Dictionary[int, bool] = {}
var _kicks: Dictionary[int, float] = {}


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


## True only while a peer is still inside its handshake deadline (tracked but
## not yet verified, rejected, or expired). A rejected/kicked peer's deadline
## is erased by `remove`, so this goes false the instant it is rejected —
## closing the resend-during-grace-window loophole where a peer could keep
## resending `_handshake` to stay connected forever (spec item 1).
func is_pending(id: int) -> bool:
	return _deadlines.has(id)


## True once a disconnect has been queued for this peer, so callers can avoid
## re-queuing (which would otherwise push the deadline later).
func is_kicking(id: int) -> bool:
	return _kicks.has(id)


## Number of connected peers still inside the handshake deadline.
func pending_count() -> int:
	return _deadlines.size()


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


## Queues a disconnect to be drained once KICK_GRACE_SECONDS have passed,
## giving the reason RPC sent just before this call real time to flush.
func queue_kick(id: int, now: float) -> void:
	if not _kicks.has(id):
		_kicks[id] = now + KICK_GRACE_SECONDS


## Returns and clears the disconnects whose grace window has elapsed.
func take_kicks(now: float) -> Array[int]:
	var pending: Array[int] = []
	for id: int in _kicks.keys():
		if now >= float(_kicks[id]):
			pending.append(id)
	for id: int in pending:
		_kicks.erase(id)
	return pending
