extends GutTest

## Spec §14.3: sequential-only checkpoint/lap state machine.

const CHECKPOINT_COUNT: int = 4


func test_sequential_pass_advances_next_index() -> void:
	var result: Dictionary = LapTracker.evaluate_checkpoint_transition(1, 1, CHECKPOINT_COUNT)
	assert_true(result["passed"])
	assert_eq(int(result["next_index"]), 2)
	assert_false(result["lap_completed"])


func test_skipping_a_checkpoint_is_ignored_and_next_does_not_advance() -> void:
	# next expects 2; kart drove through checkpoint 3 instead.
	var result: Dictionary = LapTracker.evaluate_checkpoint_transition(3, 2, CHECKPOINT_COUNT)
	assert_false(result["passed"])
	assert_eq(int(result["next_index"]), 2)


func test_reentering_the_previous_checkpoint_is_ignored() -> void:
	# next is 2 (checkpoint 1 already passed); backing into 1 must not regress state.
	var result: Dictionary = LapTracker.evaluate_checkpoint_transition(1, 2, CHECKPOINT_COUNT)
	assert_false(result["passed"])
	assert_eq(int(result["next_index"]), 2)


func test_passing_checkpoint_zero_without_completing_the_circuit_does_not_complete_a_lap() -> void:
	# A kart starting the race sits near checkpoint 0; next starts at 1, so an
	# accidental checkpoint-0 re-trigger must not look like "next == 0".
	var result: Dictionary = LapTracker.evaluate_checkpoint_transition(0, 1, CHECKPOINT_COUNT)
	assert_false(result["passed"])


func test_full_circuit_then_checkpoint_zero_completes_a_lap_and_wraps_next() -> void:
	# next has already wrapped to 0 (checkpoints 1..3 all passed this lap).
	var result: Dictionary = LapTracker.evaluate_checkpoint_transition(0, 0, CHECKPOINT_COUNT)
	assert_true(result["passed"])
	assert_true(result["lap_completed"])
	assert_eq(int(result["next_index"]), 1)


func test_zero_checkpoints_never_passes() -> void:
	var result: Dictionary = LapTracker.evaluate_checkpoint_transition(0, 0, 0)
	assert_false(result["passed"])


func test_register_kart_starts_at_checkpoint_one_and_lap_zero() -> void:
	var tracker: LapTracker = LapTracker.new()
	add_child_autofree(tracker)
	var kart: KartController = (load("res://kart/kart.tscn") as PackedScene).instantiate()
	add_child_autofree(kart)
	# LapTracker.setup() needs a Track; register_kart() alone is enough here
	# since _checkpoints defaults empty and the getters must still be safe.
	tracker.register_kart(kart)
	assert_eq(tracker.get_lap(kart), 0)
	assert_eq(tracker.get_last_checkpoint_index(kart), 0)
	assert_false(tracker.is_finished(kart))
