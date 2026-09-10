class_name NetServerState
extends RefCounted

## Pure, tick-driven lobby/restart state machine for the dedicated headless
## server (spec item 3): starts once at least one human is ready and either
## everyone is ready or a 20s grace has elapsed; restarts to LOBBY after
## RESULTS. No networking or scene logic lives here; NetServerRun drives it.
enum State { LOBBY, COUNTDOWN, RUNNING }

const COUNTDOWN_SECONDS: float = 20.0

var state: State = State.LOBBY
var _countdown_remaining: float = COUNTDOWN_SECONDS


## Advances the machine by `delta` seconds given the current lobby facts.
## Returns true on exactly the tick a race should be started.
func update(delta: float, human_count: int, ready_count: int) -> bool:
	match state:
		State.LOBBY:
			if human_count >= 1:
				state = State.COUNTDOWN
				_countdown_remaining = COUNTDOWN_SECONDS
			return false
		State.COUNTDOWN:
			if human_count < 1:
				state = State.LOBBY
				return false
			_countdown_remaining = maxf(0.0, _countdown_remaining - delta)
			var everyone_ready: bool = ready_count >= human_count
			var timed_out: bool = _countdown_remaining <= 0.0
			if ready_count >= 1 and (everyone_ready or timed_out):
				state = State.RUNNING
				return true
			return false
		_:
			return false


## Seconds left before a forced start, for display/telemetry only.
func countdown_remaining() -> float:
	return _countdown_remaining


## Reopens the lobby once the current race has reached RESULTS and its
## grace period has elapsed; callers decide the grace window themselves.
func finish_and_restart() -> void:
	state = State.LOBBY
	_countdown_remaining = COUNTDOWN_SECONDS
