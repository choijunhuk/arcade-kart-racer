extends GutTest

## Spec §24 Phase 4 DoD: drives track_01 autonomously (drift mode) for a full
## 3-lap race and checks laps count correctly, the race "finishes", and the
## kart never needs a respawn (no RespawnSystem wired here, so any fall would
## show up as the kart dropping far below the road instead).

const TRACK_SCENE: String = "res://track/tracks/track_01_ridgeline_circuit/track_01_ridgeline_circuit.tscn"
const TICKS_PER_SECOND: int = 60
const MAX_SIMULATION_SECONDS: float = 340.0
const SAMPLE_STRIDE_TICKS: int = 8
const MIN_Y: float = -4.0
const TOTAL_LAPS: int = 3


func test_three_laps_complete_without_falling_off() -> void:
	var track: Node = (load(TRACK_SCENE) as PackedScene).instantiate()
	add_child_autofree(track)
	var kart: KartController = (load("res://kart/kart.tscn") as PackedScene).instantiate()
	add_child_autofree(kart)

	var racing_line: Path3D = track.get_node("RacingLine") as Path3D
	var grid_slot: Marker3D = track.get_node("StartGrid/Grid01") as Marker3D
	await wait_physics_frames(1)
	kart.global_transform = grid_slot.global_transform
	kart.velocity = Vector3.ZERO

	var provider: ScriptedInputProvider = ScriptedInputProvider.new(kart, racing_line)
	provider.set_drift_on_corners(true)
	kart.set_input_provider(provider)

	var lap_tracker: LapTracker = LapTracker.new()
	lap_tracker.total_laps = TOTAL_LAPS
	add_child_autofree(lap_tracker)
	lap_tracker.setup(track as TrackRoot)
	lap_tracker.register_kart(kart)

	var min_y: float = kart.global_position.y
	var elapsed_ticks: int = 0
	var total_ticks: int = int(MAX_SIMULATION_SECONDS * TICKS_PER_SECOND)
	while elapsed_ticks < total_ticks and not lap_tracker.is_finished(kart):
		await wait_physics_frames(SAMPLE_STRIDE_TICKS)
		elapsed_ticks += SAMPLE_STRIDE_TICKS
		min_y = minf(min_y, kart.global_position.y)

	assert_true(lap_tracker.is_finished(kart), "kart did not finish 3 laps within the time budget")
	assert_eq(lap_tracker.get_lap(kart), TOTAL_LAPS)
	assert_gte(min_y, MIN_Y, "kart fell far below the road at some point")
