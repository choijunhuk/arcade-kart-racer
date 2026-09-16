extends GutTest

## Backlog item 6: NetEvents.configure() reflects EventBus's own signal list
## to build its server-side mirrors, matching each EVENTS entry by name and
## arity. A signal EventBus no longer declares (renamed/removed) — or one
## whose arg count falls outside the 1-3 range every EVENTS entry expects —
## used to connect an uninitialized, invalid Callable instead of failing
## loudly. Full mismatch-path coverage would need EventBus's real signal list
## disturbed at runtime, not practical here; this locks in the current,
## matching setup connecting every declared event with no warning.
func test_configure_connects_every_declared_event_when_the_signal_list_matches() -> void:
	var events: NetEvents = NetEvents.new()
	add_child_autofree(events)
	var session: NetSession = NetSession.new()
	add_child_autofree(session)
	events.configure(session, [])
	assert_eq((events.get("_connections") as Dictionary).size(), NetEvents.EVENTS.size(),
		"every declared event must connect when EventBus's signal list matches EVENTS (no mismatch warning fires)")
