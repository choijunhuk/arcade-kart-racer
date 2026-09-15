extends GutTest

## `NetSessionLobby.broadcast_lobby()` coverage (backlog item 6, review
## finding 1), split out of test_net_lobby.gd for the 400-line rule the same
## way test_net_session_admission.gd was split out of it.

## Backlog item 6: a burst of triggers landing on the same physics tick (e.g.
## a peer looping `_selection`) must coalesce to a single reliable `_lobby`
## send, not one per accepted call — `_clock_ticks` only advances inside
## `_physics_process`, so the three direct `_update_player` calls below all
## land on the same tick, exactly like several RPCs delivered in one frame.
func test_broadcast_lobby_coalesces_multiple_triggers_within_one_physics_tick() -> void:
	var session: NetSession = NetSession.new()
	add_child_autofree(session)
	session.peer = ENetMultiplayerPeer.new()
	var driver_id: String = NetContentCatalog.default_driver_id()
	var kart_id: String = NetContentCatalog.default_kart_id()
	session.players = [{"peer": 1, "driver": driver_id, "kart": kart_id, "ready": false}]
	var before: int = session.conditions.delivered
	session._update_player(1, driver_id, kart_id, true)
	session._update_player(1, driver_id, kart_id, false)
	session._update_player(1, driver_id, kart_id, true)
	session.conditions.advance(NetSession.now() + 1.0)
	assert_eq(session.conditions.delivered - before, 1, "three updates within one physics tick must coalesce into a single _lobby broadcast")
	assert_true(bool(session.players[0]["ready"]), "the roster itself must still reflect every update, only the broadcast is coalesced")

## Review finding 1: the coalescing above used to DISCARD every trigger after
## the first within one physics tick, with no periodic resend — two mutations
## landing in the same tick (routine with ENet: several `_selection` RPCs
## delivered in one poll) meant the second was never broadcast at all, and
## every client rendered a stale roster/ready flag indefinitely. It must now
## defer instead: the second mutation's broadcast flushes once `_clock_ticks`
## advances past the tick it was coalesced on, exactly as
## `NetSession._physics_process` does each tick on the real server.
func test_two_mutations_in_one_tick_defer_a_broadcast_carrying_the_second() -> void:
	var session: NetSession = NetSession.new()
	add_child_autofree(session)
	session.peer = ENetMultiplayerPeer.new()
	var driver_id: String = NetContentCatalog.default_driver_id()
	var kart_id: String = NetContentCatalog.default_kart_id()
	session.players = [{"peer": 1, "driver": driver_id, "kart": kart_id, "ready": false}]
	var before: int = session.conditions.delivered
	session._update_player(1, driver_id, kart_id, true) # First mutation this tick: sends immediately.
	session._update_player(1, driver_id, kart_id, false) # Second mutation, same tick: must be deferred, not dropped.
	session.conditions.advance(NetSession.now() + 1.0)
	assert_eq(session.conditions.delivered - before, 1, "only the first mutation's broadcast has gone out so far")
	assert_false(bool(session.players[0]["ready"]), "the roster already reflects the second mutation, ahead of its own broadcast")
	session._clock_ticks += 1 # What NetSession._physics_process does each real tick.
	session._roster.flush_pending_lobby_broadcast()
	session.conditions.advance(NetSession.now() + 1.0)
	assert_eq(session.conditions.delivered - before, 2, "the deferred second mutation must now have been broadcast too, carrying the roster's current (second-mutation) state")

## A tick with no pending broadcast must not send anything extra.
func test_flush_pending_lobby_broadcast_is_a_no_op_with_nothing_pending() -> void:
	var session: NetSession = NetSession.new()
	add_child_autofree(session)
	session.peer = ENetMultiplayerPeer.new()
	session.players = [{"peer": 1, "driver": NetContentCatalog.default_driver_id(), "kart": NetContentCatalog.default_kart_id(), "ready": false}]
	var before: int = session.conditions.delivered
	session._clock_ticks += 1
	session._roster.flush_pending_lobby_broadcast()
	session.conditions.advance(NetSession.now() + 1.0)
	assert_eq(session.conditions.delivered - before, 0, "nothing was deferred, so flushing must not send a broadcast")

## Regression coverage for the mid-race desync fix (review finding:
## `broadcast_lobby()`'s `started` guard) — split out here rather than added
## to test_net_lobby.gd for the same 400-line-budget reason this whole file
## was. `reject_peer()` used to be the only caller without its own `started`
## guard: a version/password rejection mid-race reached every RACING
## client's `_lobby` handler, whose `apply_lobby()` -> `replace()` on
## `players` desynced roster/kart indices for a peer still in the load fade.
func test_reject_peer_sends_no_lobby_broadcast_once_started() -> void:
	var session: NetSession = NetSession.new()
	add_child_autofree(session)
	session.peer = ENetMultiplayerPeer.new()
	session.players = [{"peer": 1, "driver": NetContentCatalog.default_driver_id(), "kart": NetContentCatalog.default_kart_id(), "ready": true}]
	session.started = true
	var before: int = session.conditions.delivered
	session._roster.reject_peer(2, "bad handshake")
	session.conditions.advance(NetSession.now() + 1.0)
	assert_eq(session.conditions.delivered - before, 0, "reject_peer() must not broadcast the lobby once the race has started")

## `_update_player()` already refuses the mutation itself once `started`
## (net_session.gd's own guard); pinned here alongside its sibling started-
## guard regressions so the whole set lives in one place.
func test_update_player_sends_no_lobby_broadcast_once_started() -> void:
	var session: NetSession = NetSession.new()
	add_child_autofree(session)
	session.peer = ENetMultiplayerPeer.new()
	var driver_id: String = NetContentCatalog.default_driver_id()
	var kart_id: String = NetContentCatalog.default_kart_id()
	session.players = [{"peer": 1, "driver": driver_id, "kart": kart_id, "ready": false}]
	session.started = true
	var before: int = session.conditions.delivered
	session._update_player(1, driver_id, kart_id, true)
	session.conditions.advance(NetSession.now() + 1.0)
	assert_eq(session.conditions.delivered - before, 0, "_update_player() must not broadcast once the race has started")
	assert_false(bool(session.players[0]["ready"]), "started must also block the roster mutation itself, not just the broadcast")

## The started guard applies along the peer-disconnect path too:
## `_peer_disconnected()` routes a departure through the `started` branch
## (queue-and-notify via `_player_left`), never through the not-started
## branch's immediate `_roster.remove()` + `broadcast_lobby()`. Asserting
## exactly one delivery (just `_player_left`) rather than zero proves a
## second, stray `_lobby` broadcast did not also go out alongside it.
func test_peer_disconnected_sends_no_lobby_broadcast_once_started() -> void:
	var session: NetSession = NetSession.new()
	add_child_autofree(session)
	session.peer = ENetMultiplayerPeer.new()
	session.players = [{"peer": 1, "ready": true}, {"peer": 2, "ready": true}]
	session.started = true
	var before: int = session.conditions.delivered
	session._peer_disconnected(2)
	session.conditions.advance(NetSession.now() + 1.0)
	assert_eq(session.conditions.delivered - before, 1, "only _player_left must have been sent — a second delivery here would be a stray _lobby broadcast")
	assert_eq(session.players.size(), 2, "the roster row must not be removed synchronously here: the not-started branch's immediate _roster.remove() must not have run")

## Backlog item 6 interacting with the started guard: a broadcast coalesced/
## deferred in the lobby (two mutations landing on the same physics tick)
## must never flush once the race has started. `NetSessionLobby.start_race()`
## resets `_broadcast_tick`/`_lobby_pending` for exactly this reason (the
## same two lines `clear_race_state()` resets); the real RPC path
## (`start_race()` -> `_prepare_race()`) defers a scene change, so this test
## mirrors just that reset instead of driving a scene change in a unit test.
func test_pending_broadcast_set_before_start_race_does_not_flush_afterwards() -> void:
	var session: NetSession = NetSession.new()
	add_child_autofree(session)
	session.peer = ENetMultiplayerPeer.new()
	var driver_id: String = NetContentCatalog.default_driver_id()
	var kart_id: String = NetContentCatalog.default_kart_id()
	session.players = [
		{"peer": 1, "driver": driver_id, "kart": kart_id, "ready": true},
		{"peer": 2, "driver": driver_id, "kart": kart_id, "ready": true},
	]
	session._update_player(1, driver_id, kart_id, true) # First mutation this tick: sends immediately.
	session._update_player(2, driver_id, kart_id, false) # Second mutation, same tick: coalesced/deferred, not sent yet.
	assert_true(session._roster._lobby_pending, "sanity: the second mutation must still be pending before start_race()")
	session.conditions.advance(NetSession.now() + 1.0) # Let the first mutation's own immediate broadcast land; only the second stays pending.
	session._roster._broadcast_tick = -1 # What start_race() resets (NetSessionLobby.start_race), mirrored directly here.
	session._roster._lobby_pending = false
	session.started = true
	session._clock_ticks += 1 # What NetSession._physics_process does each real tick.
	var before: int = session.conditions.delivered
	session._roster.flush_pending_lobby_broadcast()
	session.conditions.advance(NetSession.now() + 1.0)
	assert_eq(session.conditions.delivered - before, 0, "the pending pre-start-race broadcast must never flush once the race has started")

## Review finding 7 + backlog item 3 interaction: a mid-race joiner queued in
## `waiting` (admitted while `started`, so it never got a roster row nor any
## `_lobby` broadcast) must be promoted into the roster AND actually reach
## the `_lobby` broadcast restart_to_lobby() sends — not just silently gain a
## row nobody's client rendering was told about.
func test_restart_to_lobby_broadcasts_to_a_promoted_waiting_joiner() -> void:
	var session: NetSession = NetSession.new()
	add_child_autofree(session)
	session.peer = ENetMultiplayerPeer.new()
	session.players = [{"peer": 1, "ready": true}]
	session.started = true
	session._roster.add_waiting(2)
	assert_true(session._roster.waiting_has(2), "sanity: peer 2 joined mid-race as a waiting spectator")
	var before: int = session.conditions.delivered
	session.restart_to_lobby()
	session.conditions.advance(NetSession.now() + 1.0)
	assert_eq(session.conditions.delivered - before, 2, "restart_to_lobby must still queue both _return_to_lobby and the _lobby broadcast with a promoted joiner present")
	assert_true(session._roster.waiting.is_empty(), "the promoted joiner must have been moved out of waiting")
	assert_eq(session.players.size(), 2, "the promoted joiner must now hold a roster row")
	assert_eq(int(session.players[1]["peer"]), 2)
