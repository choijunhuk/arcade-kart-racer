extends GutTest

class _FullThrottleProvider extends InputProvider:
	func get_frame() -> InputFrame:
		var frame: InputFrame = InputFrame.new()
		frame.throttle = 1.0
		return frame


const KART_SCENE: PackedScene = preload("res://kart/kart.tscn")
const OFFROAD_SCENE: PackedScene = preload("res://track/elements/offroad_zone.tscn")
const HILLS_SCENE: PackedScene = preload("res://track/tracks/test_loop_hills/test_loop_hills.tscn")
const TICKS_PER_SECOND: int = 60
const TERRAIN_SETTLE_SECONDS: float = 3.0
const RESPAWN_TIMEOUT_SECONDS: float = 3.0
const POSITION_TOLERANCE: float = 0.25


func test_heavy_ram_displaces_light_more_than_heavy() -> void:
	add_child_autofree(_build_floor())
	var resolver: KartCollisionResolver = KartCollisionResolver.new()
	add_child_autofree(resolver)
	var heavy: KartController = _spawn_kart(
		load("res://data/karts/heavy.tres") as KartData,
		Vector3(0.0, 0.65, 1.0),
	)
	var light: KartController = _spawn_kart(
		load("res://data/karts/light.tres") as KartData,
		Vector3(0.0, 0.65, -1.0),
	)
	resolver.register_kart(heavy)
	resolver.register_kart(light)
	await wait_physics_frames(1)

	var heavy_start: Vector3 = heavy.global_position
	var light_start: Vector3 = light.global_position
	heavy.apply_impulse_arcade(Vector3(0.0, 0.0, -12.0), 0.0)
	await wait_physics_frames(12)

	var heavy_displacement: float = heavy.global_position.distance_to(heavy_start)
	var light_displacement: float = light.global_position.distance_to(light_start)
	assert_gt(light_displacement, heavy_displacement)
	assert_ne(heavy.get_state(), KartState.HIT)
	assert_ne(light.get_state(), KartState.HIT)


func test_grass_caps_speed_then_asphalt_recovers_it() -> void:
	add_child_autofree(_build_floor())
	var zone: OffroadZone = OFFROAD_SCENE.instantiate() as OffroadZone
	zone.scale = Vector3(200.0, 1.0, 200.0)
	add_child_autofree(zone)
	var kart: KartController = _spawn_kart(
		load("res://data/karts/medium.tres") as KartData,
		Vector3(0.0, 0.65, 0.0),
	)
	kart.set_input_provider(_FullThrottleProvider.new())
	await wait_physics_frames(int(TERRAIN_SETTLE_SECONDS * TICKS_PER_SECOND))

	var expected_grass_max: float = kart.kart_data.max_speed * lerpf(
		0.7, 1.0, kart.kart_data.offroad_resistance,
	)
	var grass_speed: float = kart.get_speed()
	assert_eq(kart.get_terrain_id(), &"grass")
	assert_almost_eq(grass_speed, expected_grass_max, expected_grass_max * 0.12)

	kart.global_position.x = 150.0
	await wait_physics_frames(int(TERRAIN_SETTLE_SECONDS * TICKS_PER_SECOND))

	assert_eq(kart.get_terrain_id(), &"asphalt")
	assert_gt(kart.get_speed(), grass_speed)
	assert_gte(kart.get_speed(), kart.kart_data.max_speed * 0.9)


func test_hills_gap_kill_zone_respawns_at_grid_with_zero_speed() -> void:
	var track: TrackRoot = HILLS_SCENE.instantiate() as TrackRoot
	add_child_autofree(track)
	var respawn: RespawnSystem = RespawnSystem.new()
	add_child_autofree(respawn)
	var kart: KartController = _spawn_kart(
		load("res://data/karts/medium.tres") as KartData,
		Vector3(58.5, 0.65, 0.0),
	)
	kart.rotation_degrees.y = -90.0
	var grid: Marker3D = track.get_node("StartGrid/Grid01") as Marker3D
	respawn.register_kart(kart, func(_target: KartController) -> Transform3D: return grid.global_transform)
	for child: Node in track.get_node("KillZones").get_children():
		respawn.register_kill_zone(child as KillZone)
	await wait_physics_frames(1)
	kart.apply_impulse_arcade(Vector3(18.0, 0.0, 0.0), 0.0)

	var saw_respawning: bool = false
	var total_ticks: int = int(RESPAWN_TIMEOUT_SECONDS * TICKS_PER_SECOND)
	for tick: int in range(total_ticks):
		await wait_physics_frames(1)
		saw_respawning = saw_respawning or kart.get_state() == KartState.RESPAWNING
		if saw_respawning and kart.get_state() == KartState.GROUNDED:
			break

	assert_true(saw_respawning)
	assert_eq(kart.get_state(), KartState.GROUNDED)
	assert_almost_eq(kart.global_position.x, grid.global_position.x, POSITION_TOLERANCE)
	assert_almost_eq(kart.global_position.z, grid.global_position.z, POSITION_TOLERANCE)
	assert_almost_eq(kart.get_speed(), 0.0, 0.001)


func _spawn_kart(data: KartData, position: Vector3) -> KartController:
	var kart: KartController = KART_SCENE.instantiate() as KartController
	kart.kart_data = data.duplicate(true) as KartData
	add_child_autofree(kart)
	kart.global_position = position
	return kart


func _build_floor() -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(400.0, 1.0, 400.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	body.add_child(shape)
	return body
