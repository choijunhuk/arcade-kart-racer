extends GutTest

## Pure one-shot tests for FirstRaceHintsState (spec §1): each of the 3
## contextual hints fires exactly once, and disabling hints suppresses all of
## them even when none have been seen yet.


func test_unseen_hint_consumes_once_and_then_stays_suppressed() -> void:
	var state: FirstRaceHintsState = FirstRaceHintsState.new(true, {})

	assert_true(state.consume(FirstRaceHintsState.Hint.DRIFT))
	assert_false(state.consume(FirstRaceHintsState.Hint.DRIFT), "a second consume of the same hint must fail")
	assert_true(state.has_seen(FirstRaceHintsState.Hint.DRIFT))


func test_hints_are_tracked_independently() -> void:
	var state: FirstRaceHintsState = FirstRaceHintsState.new(true, {})
	state.consume(FirstRaceHintsState.Hint.DRIFT)

	assert_false(state.has_seen(FirstRaceHintsState.Hint.ITEM))
	assert_true(state.consume(FirstRaceHintsState.Hint.ITEM))
	assert_true(state.consume(FirstRaceHintsState.Hint.RAMP))


func test_disabled_hints_never_consume() -> void:
	var state: FirstRaceHintsState = FirstRaceHintsState.new(false, {})

	assert_false(state.consume(FirstRaceHintsState.Hint.DRIFT))
	assert_false(state.consume(FirstRaceHintsState.Hint.ITEM))
	assert_false(state.consume(FirstRaceHintsState.Hint.RAMP))
	assert_false(state.has_seen(FirstRaceHintsState.Hint.DRIFT))


func test_restoring_from_a_persisted_seen_dictionary_keeps_it_suppressed() -> void:
	var state: FirstRaceHintsState = FirstRaceHintsState.new(true, {"drift": true})

	assert_true(state.has_seen(FirstRaceHintsState.Hint.DRIFT))
	assert_false(state.consume(FirstRaceHintsState.Hint.DRIFT))
	assert_true(state.consume(FirstRaceHintsState.Hint.ITEM))


func test_seen_snapshot_is_independent_of_internal_state() -> void:
	var state: FirstRaceHintsState = FirstRaceHintsState.new(true, {})
	state.consume(FirstRaceHintsState.Hint.RAMP)

	var snapshot: Dictionary = state.seen_snapshot()
	snapshot["ramp"] = false

	assert_true(state.has_seen(FirstRaceHintsState.Hint.RAMP), "mutating the snapshot must not affect internal state")
