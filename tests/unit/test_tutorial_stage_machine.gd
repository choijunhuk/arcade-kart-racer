extends GutTest

## Pure progression tests for TutorialStageMachine (spec §1): each stage must
## complete only from the real signal/sample it is wired to, in order, with
## no stage skipping ahead from an unrelated event.


func test_starts_on_accelerate_and_is_not_complete() -> void:
	var machine: TutorialStageMachine = TutorialStageMachine.new()

	assert_eq(machine.current_stage(), TutorialStageMachine.Stage.ACCELERATE)
	assert_false(machine.is_complete())
	assert_eq(machine.progress(), 0)


func test_accelerate_stage_requires_both_throttle_and_minimum_speed() -> void:
	var machine: TutorialStageMachine = TutorialStageMachine.new()

	machine.on_kart_sample(0.0, 1.0, 0.0)
	assert_eq(machine.current_stage(), TutorialStageMachine.Stage.ACCELERATE, "speed below threshold must not advance")

	machine.on_kart_sample(5.0, 0.0, 0.0)
	assert_eq(machine.current_stage(), TutorialStageMachine.Stage.ACCELERATE, "no throttle held must not advance")

	machine.on_kart_sample(5.0, 1.0, 0.0)
	assert_eq(machine.current_stage(), TutorialStageMachine.Stage.STEER)


func test_steer_stage_requires_speed_and_steer_magnitude() -> void:
	var machine: TutorialStageMachine = TutorialStageMachine.new()
	machine.on_kart_sample(5.0, 1.0, 0.0)
	assert_eq(machine.current_stage(), TutorialStageMachine.Stage.STEER)

	machine.on_kart_sample(5.0, 1.0, 0.1)
	assert_eq(machine.current_stage(), TutorialStageMachine.Stage.STEER, "weak steer input must not advance")

	machine.on_kart_sample(5.0, 1.0, -0.6)
	assert_eq(machine.current_stage(), TutorialStageMachine.Stage.DRIFT_RELEASE)


func test_drift_release_only_advances_on_mini_turbo_boost_source() -> void:
	var machine: TutorialStageMachine = _advanced_to(TutorialStageMachine.Stage.DRIFT_RELEASE)

	machine.on_boost_started(&"trick")
	assert_eq(machine.current_stage(), TutorialStageMachine.Stage.DRIFT_RELEASE, "unrelated boost source must not advance")

	machine.on_boost_started(&"mini_turbo_2")
	assert_eq(machine.current_stage(), TutorialStageMachine.Stage.START_BOOST)


func test_start_boost_only_advances_on_start_boost_source() -> void:
	var machine: TutorialStageMachine = _advanced_to(TutorialStageMachine.Stage.START_BOOST)

	machine.on_boost_started(&"mini_turbo_1")
	assert_eq(machine.current_stage(), TutorialStageMachine.Stage.START_BOOST)

	machine.on_boost_started(&"start_boost")
	assert_eq(machine.current_stage(), TutorialStageMachine.Stage.RAMP_TRICK)


func test_ramp_trick_only_advances_on_trick_boost_source() -> void:
	var machine: TutorialStageMachine = _advanced_to(TutorialStageMachine.Stage.RAMP_TRICK)

	machine.on_boost_started(&"start_boost")
	assert_eq(machine.current_stage(), TutorialStageMachine.Stage.RAMP_TRICK)

	machine.on_boost_started(&"trick")
	assert_eq(machine.current_stage(), TutorialStageMachine.Stage.ITEM_PICKUP)


func test_item_pickup_then_item_use_completes_the_tutorial() -> void:
	var machine: TutorialStageMachine = _advanced_to(TutorialStageMachine.Stage.ITEM_PICKUP)

	machine.on_item_used()
	assert_eq(machine.current_stage(), TutorialStageMachine.Stage.ITEM_PICKUP, "using an item before pickup must not advance")

	machine.on_item_box_collected()
	assert_eq(machine.current_stage(), TutorialStageMachine.Stage.ITEM_USE)
	assert_false(machine.is_complete())

	machine.on_item_used()
	assert_true(machine.is_complete())
	assert_eq(machine.current_stage(), TutorialStageMachine.Stage.DONE)
	assert_eq(machine.progress(), machine.stage_count())


func test_events_for_a_later_stage_do_not_leak_into_an_earlier_one() -> void:
	var machine: TutorialStageMachine = TutorialStageMachine.new()

	machine.on_boost_started(&"start_boost")
	machine.on_item_used()
	machine.on_item_box_collected()

	assert_eq(machine.current_stage(), TutorialStageMachine.Stage.ACCELERATE)


## Drives a fresh machine through every stage before `target`, using the same
## real-event calls each stage requires, and returns it positioned at `target`.
func _advanced_to(target: TutorialStageMachine.Stage) -> TutorialStageMachine:
	var machine: TutorialStageMachine = TutorialStageMachine.new()
	if target == TutorialStageMachine.Stage.ACCELERATE:
		return machine
	machine.on_kart_sample(5.0, 1.0, 0.0)
	if target == TutorialStageMachine.Stage.STEER:
		return machine
	machine.on_kart_sample(5.0, 1.0, -0.6)
	if target == TutorialStageMachine.Stage.DRIFT_RELEASE:
		return machine
	machine.on_boost_started(&"mini_turbo_2")
	if target == TutorialStageMachine.Stage.START_BOOST:
		return machine
	machine.on_boost_started(&"start_boost")
	if target == TutorialStageMachine.Stage.RAMP_TRICK:
		return machine
	machine.on_boost_started(&"trick")
	if target == TutorialStageMachine.Stage.ITEM_PICKUP:
		return machine
	machine.on_item_box_collected()
	if target == TutorialStageMachine.Stage.ITEM_USE:
		return machine
	machine.on_item_used()
	return machine
