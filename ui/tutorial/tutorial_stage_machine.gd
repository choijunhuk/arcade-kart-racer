class_name TutorialStageMachine
extends RefCounted

## Pure, tree-free onboarding progression. A scene controller feeds this real
## EventBus signals and per-frame kart input samples; it never advances from
## timers or guesses. See `ui/tutorial/tutorial_controller.gd` for the wiring
## and `.omc/phase18c_first_impressions.md` §1 for the staged task list.

enum Stage {
	ACCELERATE,
	STEER,
	DRIFT_RELEASE,
	START_BOOST,
	RAMP_TRICK,
	ITEM_PICKUP,
	ITEM_USE,
	DONE,
}

const STAGE_ORDER: Array[Stage] = [
	Stage.ACCELERATE,
	Stage.STEER,
	Stage.DRIFT_RELEASE,
	Stage.START_BOOST,
	Stage.RAMP_TRICK,
	Stage.ITEM_PICKUP,
	Stage.ITEM_USE,
]

const MIN_ACCELERATE_SPEED: float = 2.5
const MIN_STEER_SPEED: float = 1.5
const MIN_STEER_INPUT: float = 0.35
const DRIFT_RELEASE_PREFIX: String = "mini_turbo_"
const START_BOOST_SOURCE: String = "start_boost"
const TRICK_SOURCE: String = "trick"

var _index: int = 0


## Returns the stage currently awaiting completion (`Stage.DONE` once finished).
func current_stage() -> Stage:
	return STAGE_ORDER[_index] if _index < STAGE_ORDER.size() else Stage.DONE


func is_complete() -> bool:
	return _index >= STAGE_ORDER.size()


## Zero-based count of stages already completed.
func progress() -> int:
	return _index


func stage_count() -> int:
	return STAGE_ORDER.size()


## Real per-frame sample from the tracked player kart; drives stages 1-2
## (accelerate/steer) since no discrete EventBus signal exists for raw input.
func on_kart_sample(speed: float, throttle_input: float, steer_input: float) -> void:
	match current_stage():
		Stage.ACCELERATE:
			if throttle_input > 0.0 and speed >= MIN_ACCELERATE_SPEED:
				_advance()
		Stage.STEER:
			if speed >= MIN_STEER_SPEED and absf(steer_input) >= MIN_STEER_INPUT:
				_advance()


## Forwards `EventBus.boost_started`'s resolved source (`kart.get_boost_source()`)
## for the tracked player kart; covers stages 3-5 (drift release / start boost /
## ramp trick), each a distinct boost source already emitted by BoostController.
func on_boost_started(source: StringName) -> void:
	var text: String = String(source)
	match current_stage():
		Stage.DRIFT_RELEASE:
			if text.begins_with(DRIFT_RELEASE_PREFIX):
				_advance()
		Stage.START_BOOST:
			if text == START_BOOST_SOURCE:
				_advance()
		Stage.RAMP_TRICK:
			if text == TRICK_SOURCE:
				_advance()


## Forwards `EventBus.roulette_started` for the tracked player kart (stage 6).
func on_item_box_collected() -> void:
	if current_stage() == Stage.ITEM_PICKUP:
		_advance()


## Forwards `EventBus.item_used` for the tracked player kart (stage 7).
func on_item_used() -> void:
	if current_stage() == Stage.ITEM_USE:
		_advance()


func _advance() -> void:
	_index += 1
