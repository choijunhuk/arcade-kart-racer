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
