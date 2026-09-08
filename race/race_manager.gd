class_name RaceManager
extends Node3D

## Owns legal race-state transitions and, after composition, scene orchestration.

const LEGAL_TRANSITIONS: Dictionary = {
	RaceState.LOADING: [RaceState.COUNTDOWN],
	RaceState.COUNTDOWN: [RaceState.RACING, RaceState.PAUSED],
	RaceState.RACING: [RaceState.FINISHING, RaceState.PAUSED],
	RaceState.FINISHING: [RaceState.RESULTS],
	RaceState.RESULTS: [RaceState.LOADING],
	RaceState.PAUSED: [RaceState.COUNTDOWN, RaceState.RACING],
}


## Returns whether a requested state edge belongs to the Phase 5 table.
static func can_transition(from_state: int, to_state: int) -> bool:
	var allowed: Array = LEGAL_TRANSITIONS.get(from_state, []) as Array
	return allowed.has(to_state)


## Returns whether FINISHING may close because everyone finished or time expired.
static func finishing_complete(finished_count: int, kart_count: int, elapsed: float, timeout: float) -> bool:
	return finished_count >= kart_count or elapsed >= timeout

