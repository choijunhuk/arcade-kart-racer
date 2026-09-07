extends GutTest

## Drives `test_hairpin.tscn` with `ScriptedInputProvider`'s drift-on-corners
## mode against its legacy no-drift default and checks the Phase 3 DoD claim:
## drift mode reaches mini-turbo tier >= 2 at least once and completes a lap
## at least `MIN_DRIFT_SPEEDUP_RATIO` faster than the no-drift baseline
## (spec §24 Phase 3, delivery contract item 8).

const TICKS_PER_SECOND: int = 60
const WARMUP_SECONDS: float = 3.0
const MAX_LAP_SECONDS: float = 180.0
const MIN_DRIFT_SPEEDUP_RATIO: float = 0.03
const MIN_REQUIRED_TIER: int = 2
const HAIRPIN_PATH: String = "res://track/tracks/test_hairpin/test_hairpin.tscn"
const KART_PATH: String = "res://kart/kart.tscn"
## Fraction of `baked_length` the kart must actually travel (by cumulative
## world-space distance, not curve offset) before a return to the start is
## accepted as a completed lap rather than the opening few meters off the grid.
const MIN_LAP_DISTANCE_RATIO: float = 0.8
## How close (world units) the kart must be to its post-warmup start position
## to count as having returned to complete the lap.
const LAP_CLOSE_RADIUS: float = 12.0

class LapResult extends RefCounted:
	var lap_time: float = -1.0
	var max_tier: int = 0


func test_drift_mode_reaches_tier_two_or_higher_during_a_lap() -> void:
	var result: LapResult = await _drive_one_lap(true)

	assert_gte(result.lap_time, 0.0, "drift-mode kart never completed a lap")
	assert_gte(result.max_tier, MIN_REQUIRED_TIER, "drift mode never reached tier >= 2 on the hairpin")


func test_drift_mode_completes_a_lap_faster_than_no_drift_mode() -> void:
	var no_drift: LapResult = await _drive_one_lap(false)
	var drift: LapResult = await _drive_one_lap(true)

	assert_gte(no_drift.lap_time, 0.0, "no-drift kart never completed a lap")
	assert_gte(drift.lap_time, 0.0, "drift-mode kart never completed a lap")
	var required_time: float = no_drift.lap_time * (1.0 - MIN_DRIFT_SPEEDUP_RATIO)
	assert_lte(
		drift.lap_time, required_time,
		"drift mode (%.2fs) was not >= %.0f%% faster than no-drift mode (%.2fs)" % [
			drift.lap_time, MIN_DRIFT_SPEEDUP_RATIO * 100.0, no_drift.lap_time,
		],
	)


## Drives one full lap of the hairpin and returns elapsed time plus the
## highest mini-turbo tier reached, or a sentinel result if it times out.
## Lap completion is measured by cumulative world-space distance traveled
## plus a return within `LAP_CLOSE_RADIUS` of the start, rather than
## `Curve3D.get_closest_offset()`: this track's two straights run close and
## parallel to each other, so a kart's closest point on the curve can be
## ambiguous between them and make offset-delta tracking unreliable.
func _drive_one_lap(drift_on_corners: bool) -> LapResult:
	var track: TrackRoot = (load(HAIRPIN_PATH) as PackedScene).instantiate() as TrackRoot
	add_child_autofree(track)
	var kart: KartController = (load(KART_PATH) as PackedScene).instantiate() as KartController
	add_child_autofree(kart)

	var racing_line: Path3D = track.get_node("RacingLine") as Path3D
	var grid_slot: Marker3D = track.get_node("StartGrid/Grid01") as Marker3D
	await wait_physics_frames(1)
	kart.global_transform = grid_slot.global_transform
	kart.velocity = Vector3.ZERO

	var provider: ScriptedInputProvider = ScriptedInputProvider.new(kart, racing_line)
	provider.set_drift_on_corners(drift_on_corners)
	kart.set_input_provider(provider)

	# Warm-up mirrors test_kart_lap.gd: let the scripted driver settle onto
	# the line before lap timing and tier tracking begin.
	await wait_physics_frames(int(WARMUP_SECONDS * TICKS_PER_SECOND))

	var baked_length: float = racing_line.curve.get_baked_length()
	var min_lap_distance: float = baked_length * MIN_LAP_DISTANCE_RATIO
	var start_position: Vector3 = kart.global_position
	var previous_position: Vector3 = start_position
	var traveled_distance: float = 0.0
	var max_tier: int = 0
	var elapsed_ticks: int = 0
	var max_ticks: int = int(MAX_LAP_SECONDS * TICKS_PER_SECOND)
	var result: LapResult = LapResult.new()

	while elapsed_ticks < max_ticks:
		await wait_physics_frames(1)
		elapsed_ticks += 1
		# Sample every tick (not just periodically): a released mini-turbo
		# tier is only visible for the few ticks between crossing its charge
		# threshold and the drift ending, so a coarser stride can step right
		# over it and under-report the tier this lap actually reached.
		max_tier = maxi(max_tier, kart.get_drift_tier())

		traveled_distance += previous_position.distance_to(kart.global_position)
		previous_position = kart.global_position

		if traveled_distance >= min_lap_distance and kart.global_position.distance_to(start_position) <= LAP_CLOSE_RADIUS:
			result.lap_time = elapsed_ticks / float(TICKS_PER_SECOND)
			result.max_tier = max_tier
			return result

	result.max_tier = max_tier
	return result
