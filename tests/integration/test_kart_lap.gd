extends GutTest

## Drives `kart.tscn` around `test_loop.tscn` autonomously with
## `ScriptedInputProvider` for a full lap and checks the DoD claims: stays
## near the racing line, never falls through the floor, reaches highway
## speed, and completes at least one lap (spec §24 Phase 1).

const TICKS_PER_SECOND: int = 60
const SIMULATION_SECONDS: float = 90.0
const WARMUP_SECONDS: float = 3.0
const SAMPLE_STRIDE_TICKS: int = 4
const MAX_LINE_DEVIATION: float = 10.0
const MIN_Y: float = -1.0
const MIN_STRAIGHT_SPEED_RATIO: float = 0.9


func test_kart_completes_a_lap_following_the_racing_line() -> void:
	var track: Node = (load("res://track/tracks/test_loop/test_loop.tscn") as PackedScene).instantiate()
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

	# Warm-up: the grid slot's heading does not exactly match the placeholder
	# racing line's tangent, so give the scripted driver a moment to settle
	# onto the line before the DoD deviation/speed measurements begin.
	await wait_physics_frames(int(WARMUP_SECONDS * TICKS_PER_SECOND))

	var baked_length: float = racing_line.curve.get_baked_length()
	var previous_offset: float = racing_line.curve.get_closest_offset(racing_line.to_local(kart.global_position))
	var unwrapped_progress: float = 0.0
	var max_deviation: float = 0.0
	var min_y: float = kart.global_position.y
	var max_speed_ratio: float = 0.0
	var total_ticks: int = int((SIMULATION_SECONDS - WARMUP_SECONDS) * TICKS_PER_SECOND)

	var elapsed_ticks: int = 0
	while elapsed_ticks < total_ticks:
		await wait_physics_frames(SAMPLE_STRIDE_TICKS)
		elapsed_ticks += SAMPLE_STRIDE_TICKS

		var local_position: Vector3 = racing_line.to_local(kart.global_position)
		var closest: Vector3 = racing_line.curve.get_closest_point(local_position)
		max_deviation = maxf(max_deviation, local_position.distance_to(closest))
		min_y = minf(min_y, kart.global_position.y)
		max_speed_ratio = maxf(max_speed_ratio, kart.get_speed_ratio())

		var current_offset: float = racing_line.curve.get_closest_offset(local_position)
		var delta_offset: float = current_offset - previous_offset
		if delta_offset < -baked_length * 0.5:
			delta_offset += baked_length
		elif delta_offset > baked_length * 0.5:
			delta_offset -= baked_length
		unwrapped_progress += delta_offset
		previous_offset = current_offset

	assert_lte(max_deviation, MAX_LINE_DEVIATION, "kart drifted too far from the racing line")
	assert_gte(min_y, MIN_Y, "kart fell below the floor")
	assert_gte(max_speed_ratio, MIN_STRAIGHT_SPEED_RATIO, "kart never reached highway speed")
	assert_gte(unwrapped_progress, baked_length, "kart did not complete a full lap")
