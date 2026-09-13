extends GutTest

## Permanent headless smoke coverage for the risky actions players perform:
## wall impacts, jump/landing, cliff respawn, item use, pause/resume and restart.

class SmokeInputProvider extends InputProvider:
	var steer: float = 0.0
	var _tick: int = 0
	var _use_item_next: bool = false

	func get_frame() -> InputFrame:
		_tick += 1
		var frame: InputFrame = InputFrame.new()
		frame.tick = _tick
		frame.throttle = 1.0
		frame.steer = steer
		frame.item = _use_item_next
		_use_item_next = false
		return frame

	func use_item_once() -> void:
		_use_item_next = true


const KART_SCENE: PackedScene = preload("res://kart/kart.tscn")
const RACE_SCENE: PackedScene = preload("res://race/race.tscn")
const TRACK_01_SCENE: PackedScene = preload("res://track/tracks/track_01_ridgeline_circuit/track_01_ridgeline_circuit.tscn")
const HILLS_SCENE: PackedScene = preload("res://track/tracks/test_loop_hills/test_loop_hills.tscn")
const TEST_LOOP_SCENE: PackedScene = preload("res://track/tracks/test_loop/test_loop.tscn")
const MEDIUM_KART: KartData = preload("res://data/karts/medium.tres")
const NITRO_ITEM: ItemData = preload("res://data/items/nitro_can.tres")
const TICKS_PER_SECOND: int = 60
const RECOVERY_TICKS: int = 3 * TICKS_PER_SECOND
const TRACK_FALL_LIMIT: float = -2.0
const POSITION_EPSILON: float = 0.01


func after_each() -> void:
	get_tree().paused = false


func test_full_speed_head_on_and_angled_wall_impacts_resume_within_three_seconds() -> void:
	var head_on: Dictionary = await _run_track_01_wall_impact(false)
	var angled: Dictionary = await _run_track_01_wall_impact(true)

	for result: Dictionary in [head_on, angled]:
		assert_true(bool(result["saw_wall"]), "%s impact never reached a wall" % result["kind"])
		assert_gte(float(result["min_y"]), TRACK_FALL_LIMIT, "%s impact lost the kart below Track 01" % result["kind"])
		assert_true(bool(result["grounded"]), "%s impact did not return to grounded driving" % result["kind"])
		assert_ne(int(result["state"]), KartState.HIT, "%s impact remained stuck in HIT" % result["kind"])
		assert_gt(float(result["speed"]), 3.0, "%s impact could not resume driving within three seconds" % result["kind"])


func test_jump_lands_and_cliff_fall_respawns_within_three_seconds() -> void:
	var track: TrackRoot = HILLS_SCENE.instantiate() as TrackRoot
	add_child_autofree(track)
	var kart: KartController = KART_SCENE.instantiate() as KartController
	add_child_autofree(kart)
	var grid: Marker3D = track.get_node("StartGrid/Grid01") as Marker3D
	var line: RacingLine = track.get_racing_line()
	var respawn: RespawnSystem = RespawnSystem.new()
	add_child_autofree(respawn)
	respawn.register_kart(kart, func(_target: KartController) -> Transform3D: return grid.global_transform)
	for child: Node in track.get_node("KillZones").get_children():
		respawn.register_kill_zone(child as KillZone)
	await wait_physics_frames(1)
	kart.global_transform = grid.global_transform
	kart.reset_motion_arcade()
	kart.set_input_provider(ScriptedInputProvider.new(kart, line))

	var saw_airborne: bool = false
	var landing_ticks: int = 0
	for _tick: int in range(5 * TICKS_PER_SECOND):
		await wait_physics_frames(1)
		if kart.get_state() == KartState.AIRBORNE:
			saw_airborne = true
			landing_ticks = 0
		elif saw_airborne and kart.is_grounded():
			break
		if saw_airborne:
			landing_ticks += 1
	assert_true(saw_airborne, "scripted play never triggered the hills JumpPad")
	assert_lte(landing_ticks, RECOVERY_TICKS, "jump did not land within three seconds")
	assert_true(kart.is_grounded(), "jump did not return to grounded state")
	assert_gte(kart.global_position.y, TRACK_FALL_LIMIT, "jump landing lost the kart below the track")

	var fall_kart: KartController = KART_SCENE.instantiate() as KartController
	add_child_autofree(fall_kart)
	fall_kart.set_input_provider(InputProvider.new())
	fall_kart.global_position = Vector3(58.5, 0.65, 0.0)
	fall_kart.rotation_degrees = Vector3(0.0, -90.0, 0.0)
	var fall_respawn: RespawnSystem = RespawnSystem.new()
	add_child_autofree(fall_respawn)
	fall_respawn.register_kart(fall_kart, func(_target: KartController) -> Transform3D: return grid.global_transform)
	for child: Node in track.get_node("KillZones").get_children():
		fall_respawn.register_kill_zone(child as KillZone)
	await wait_physics_frames(1)
	fall_kart.apply_impulse_arcade(Vector3(18.0, 0.0, 0.0), 0.0)
	var saw_respawning: bool = false
	var recovered: bool = false
	for _tick: int in range(RECOVERY_TICKS):
		await wait_physics_frames(1)
		saw_respawning = saw_respawning or fall_kart.get_state() == KartState.RESPAWNING
		if saw_respawning and fall_kart.get_state() == KartState.GROUNDED:
			recovered = true
			break
	assert_true(saw_respawning, "cliff fall never entered RESPAWNING")
	assert_true(recovered, "cliff fall did not resume within three seconds")
	assert_almost_eq(fall_kart.global_position.x, grid.global_position.x, 0.25)
	assert_almost_eq(fall_kart.global_position.z, grid.global_position.z, 0.25)
	assert_almost_eq(fall_kart.get_speed(), 0.0, 0.001)


func test_item_pause_resume_and_restart_return_to_grid() -> void:
	var provider: SmokeInputProvider = SmokeInputProvider.new()
	var race: RaceManager = RACE_SCENE.instantiate() as RaceManager
	race.configure(_race_config(), func(_kart: KartController, _line: RacingLine) -> InputProvider: return provider)
	add_child_autofree(race)
	await _wait_for_race_state(race, RaceState.RACING, 4 * TICKS_PER_SECOND)
	assert_eq(race.get_state(), RaceState.RACING)
	var kart: KartController = race.get_karts()[0]
	await wait_physics_frames(TICKS_PER_SECOND)
	var item_manager: ItemManager = race.get_node("ItemManager") as ItemManager
	watch_signals(EventBus)
	assert_true(item_manager.give_item(kart, NITRO_ITEM))
	provider.use_item_once()
	await wait_physics_frames(2)
	assert_signal_emit_count(EventBus, "item_used", 1)
	assert_false(kart.item_slot.has_item(), "item input did not consume the held item")

	race.pause_race()
	assert_eq(race.get_state(), RaceState.PAUSED)
	var paused_position: Vector3 = kart.global_position
	await wait_physics_frames(30)
	assert_almost_eq(kart.global_position.distance_to(paused_position), 0.0, POSITION_EPSILON)
	race.resume_race()
	assert_eq(race.get_state(), RaceState.RACING)
	var resumed_position: Vector3 = kart.global_position
	await wait_physics_frames(60)
	assert_gt(kart.global_position.distance_to(resumed_position), POSITION_EPSILON)

	race.restart()
	await wait_physics_frames(2)
	assert_eq(race.get_state(), RaceState.COUNTDOWN)
	var restarted_kart: KartController = race.get_karts()[0]
	var restart_grid: Marker3D = race.get_node("Track/StartGrid/Grid01") as Marker3D
	assert_almost_eq(restarted_kart.global_position.distance_to(restart_grid.global_position), 0.0, 0.25)
	assert_eq(restarted_kart.get_state(), KartState.FROZEN)


func _run_track_01_wall_impact(angled: bool) -> Dictionary:
	var track: TrackRoot
	if angled:
		track = TRACK_01_SCENE.instantiate() as TrackRoot
		add_child_autofree(track)
	else:
		add_child_autofree(_build_floor())
		add_child_autofree(_build_wall())
	var kart: KartController = KART_SCENE.instantiate() as KartController
	add_child_autofree(kart)
	await wait_physics_frames(2)
	var direction: Vector3
	var start_position: Vector3
	if angled:
		# The permanent probe's grounded 45-degree Track 01 chicane regression.
		direction = Vector3(-0.9845, 0.0, 0.1755).normalized()
		start_position = Vector3(-297.516, 0.95, -2.42)
	else:
		direction = Vector3.FORWARD
		start_position = Vector3(0.0, 0.65, 0.0)
	kart.global_transform = Transform3D(Basis.looking_at(direction, Vector3.UP), start_position)
	var provider: SmokeInputProvider = SmokeInputProvider.new()
	kart.set_input_provider(provider)
	(kart.get_node("KartPhysics") as KartPhysics).speed = kart.kart_data.max_speed
	var saw_wall: bool = false
	var min_y: float = kart.global_position.y
	for _tick: int in range(RECOVERY_TICKS):
		await wait_physics_frames(1)
		min_y = minf(min_y, kart.global_position.y)
		for collision_index: int in range(kart.get_slide_collision_count()):
			var collision: KinematicCollision3D = kart.get_slide_collision(collision_index)
			if absf(collision.get_normal().dot(Vector3.UP)) < kart.tuning.wall_normal_threshold:
				saw_wall = true
				provider.steer = 1.0
	return {
		"kind": "angled" if angled else "head_on",
		"saw_wall": saw_wall,
		"min_y": min_y,
		"grounded": kart.is_grounded(),
		"state": kart.get_state(),
		"speed": kart.get_speed(),
	}


func _build_floor() -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(60.0, 1.0, 60.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	body.add_child(shape)
	return body


func _build_wall() -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(20.0, 4.0, 1.0)
	shape.shape = box
	shape.position = Vector3(0.0, 2.0, -10.0)
	body.add_child(shape)
	return body


func _race_config() -> RaceConfig:
	var track_data: TrackData = TrackData.new()
	track_data.id = &"test_loop"
	track_data.display_name = "Test Loop"
	track_data.scene = TEST_LOOP_SCENE
	track_data.laps_default = 1
	var config: RaceConfig = RaceConfig.new()
	config.track = track_data
	config.laps = 1
	config.kart_count = 1
	config.player_slot = 0
	config.player_kart = MEDIUM_KART
	config.items_enabled = true
	return config


func _wait_for_race_state(race: RaceManager, target_state: int, max_ticks: int) -> void:
	for _tick: int in range(max_ticks):
		if race.get_state() == target_state:
			return
		await wait_physics_frames(1)
