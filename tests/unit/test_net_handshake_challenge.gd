extends GutTest

## Phase 18i item 1: password challenge-response (protocol 0.7.0). Split out
## of test_net_internet.gd (400-line budget, same reason test_net_upnp_reachability.gd
## was split out of it) rather than added there. Covers `NetHandshake.response()`
## itself plus the server-side one-time-nonce plumbing in `NetPeerGate`/
## `NetSessionLobby.process_handshake` that closes the "capture one hash off
## the wire, replay it later" hole a plain hashed-password compare left open.

func test_response_differs_for_the_same_password_under_different_nonces() -> void:
	var hash: String = "secret".sha256_text()
	assert_ne(NetHandshake.response("nonce-a", hash), NetHandshake.response("nonce-b", hash))

func test_response_is_empty_when_no_password_is_set() -> void:
	assert_eq(NetHandshake.response("any-nonce", ""), "")
	assert_eq(NetHandshake.response("", ""), "", "an empty nonce must not itself produce a non-empty response for a passwordless session")

func test_gate_nonce_is_consumed_exactly_once() -> void:
	var gate: NetPeerGate = NetPeerGate.new()
	gate.track(1, 0.0)
	var nonce: String = gate.issue_nonce(1)
	assert_eq(gate.nonce_for(1), nonce, "nonce_for must peek without consuming")
	assert_eq(gate.take_nonce(1), nonce)
	assert_eq(gate.take_nonce(1), "", "a nonce must not be usable a second time")
	assert_eq(gate.nonce_for(1), "", "a consumed nonce must also read back empty")

## Server-side NetSession with a scriptable RPC sender id, mirroring
## test_net_internet.gd's own GateSession but kept local to this file so it
## does not also need updating whenever that one changes shape.
class ChallengeSession extends NetSession:
	var sender_id: int = 0
	var rejects: Array[Dictionary] = []

	func _sender() -> int:
		return sender_id

	func _deliver_reject(id: int, message: String) -> void:
		rejects.append({"peer": id, "message": message})

	func handshake_from(id: int, response: String) -> void:
		sender_id = id
		_handshake(_expected_version(), response)

	func _expected_version() -> String:
		return String(ProjectSettings.get_setting("application/config/version", ""))

## Spec item 6: a peer that is tracked (past `_peer_connected`) but has no
## outstanding nonce — because the real challenge round trip never actually
## reached it, or a prior attempt already consumed it — must be dropped
## silently. Neither admitting it (obviously) nor rejecting it: a reject
## would leak that this id is even being watched, and would draw an
## unnecessary kick for a peer that may just be slow to receive its
## `_challenge`.
func test_handshake_before_any_challenge_is_ignored_not_rejected() -> void:
	var session: ChallengeSession = ChallengeSession.new()
	add_child_autofree(session)
	session._gate.track(5, NetSession.now()) # Tracked, but no nonce ever issued.
	session.handshake_from(5, "anything")
	assert_true(session.rejects.is_empty(), "a handshake with no outstanding challenge must be dropped, not rejected")
	assert_eq(session.players.size(), 0)
	assert_false(session._gate.allows(5))

## Spec item 6: a response computed against an earlier (now-stale) nonce must
## fail once compared against the peer's current one — the whole point of
## binding the hash to a per-connection nonce is that a captured response
## cannot be replayed later, even against the same peer id.
func test_reusing_a_stale_nonces_response_is_rejected_against_the_current_nonce() -> void:
	var session: ChallengeSession = ChallengeSession.new()
	add_child_autofree(session)
	session.set_password("secret")
	session._peer_connected(6)
	var stale_response: String = NetHandshake.response(session._gate.nonce_for(6), "secret".sha256_text())
	session._gate.take_nonce(6) # Simulates that response having already been consumed once.
	session._gate.issue_nonce(6) # A fresh nonce is now pending; the captured response no longer matches it.
	session.handshake_from(6, stale_response)
	assert_eq(session.rejects.size(), 1)
	assert_true(String(session.rejects[0]["message"]).findn("password") >= 0)
	assert_eq(session.players.size(), 0)
