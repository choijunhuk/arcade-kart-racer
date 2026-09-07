extends GutTest

## Drives `kart.tscn` over the ramp on `test_loop_hills.tscn` and checks the
## DoD claims: the kart actually climbs the hill, and any airborne->grounded
## landing loses no more speed than `landing_speed_loss_cap` allows (spec
## §9.7, §24 Phase 1). Only genuine landings are checked against the cap —
## a wall hit is a separate, much larger, intentionally-allowed loss (spec
## §9.8) and must not be confused with a landing.

const TICKS_PER_SECOND: int = 60
const SIMULATION_SECONDS: float = 4.0
const MIN_Y: float = -1.0
const MIN_CLIMB_HEIGHT: float = 1.0


func test_kart_climbs_the_ramp_without_exceeding_the_landing_loss_cap() -> void:
	var track: Node = (load("res://track/tracks/test_loop_hills/test_loop_hills.tscn") as PackedScene).instantiate()
	add_child_autofree(track)
	var kart: KartController = (load("res://kart/kart.tscn") as PackedScene).instantiate()
	add_child_autofree(kart)

	var racing_line: Path3D = track.get_node("RacingLine") as Path3D
	var grid_slot: Marker3D = track.get_node("StartGrid/Grid01") as Marker3D
	await wait_physics_frames(1)
	kart.global_transform = grid_slot.global_transform
	kart.velocity = Vector3.ZERO

	var provider: ScriptedInputProvider = ScriptedInputProvider.new(kart, racing_line)
	kart.set_input_provider(provider)

	var tuning: PhysicsTuning = kart.tuning
	var max_height: float = kart.global_position.y
	var min_y: float = kart.global_position.y
	var previous_speed: float = kart.get_speed()
	var was_grounded: bool = kart.is_grounded()
	var worst_landing_loss_ratio: float = 0.0
	var saw_airborne: bool = false
	var saw_landing_after_airborne: bool = false
	var total_ticks: int = int(SIMULATION_SECONDS * TICKS_PER_SECOND)

	for tick: int in range(total_ticks):
		await wait_physics_frames(1)
		max_height = maxf(max_height, kart.global_position.y)
		min_y = minf(min_y, kart.global_position.y)
		var current_speed: float = kart.get_speed()
		var grounded: bool = kart.is_grounded()
		saw_airborne = saw_airborne or kart.get_state() == KartState.AIRBORNE
		if grounded and not was_grounded and previous_speed > 0.1 and current_speed < previous_speed:
			var loss_ratio: float = (previous_speed - current_speed) / previous_speed
			worst_landing_loss_ratio = maxf(worst_landing_loss_ratio, loss_ratio)
		if saw_airborne and grounded:
			saw_landing_after_airborne = true
		was_grounded = grounded
		previous_speed = current_speed

	assert_gte(max_height, MIN_CLIMB_HEIGHT, "kart never climbed the ramp")
	assert_gte(min_y, MIN_Y, "kart fell through the hills track")
	assert_true(saw_airborne, "ledge never produced AIRBORNE state")
	assert_true(saw_landing_after_airborne, "kart never returned to ground after the ledge")
	assert_lte(
		worst_landing_loss_ratio,
		tuning.landing_speed_loss_cap + 0.05,
		"a landing lost more speed than the landing loss cap allows",
	)
