extends GutTest

## Regression: karts must wait ON the road during the countdown (not sunk
## into it) and must not pop vertically at GO. Track01's hand-authored grid
## markers sat 0.1 m below its road top, so karts spawned 0.45 m under their
## hover height with every ground ray starting inside the road collision.

const RACE_SCENE_PATH: String = "res://race/race.tscn"
const TRACKS: Array[String] = [
	"res://data/tracks/track_01.tres",
	"res://data/tracks/track_02.tres",
	"res://data/tracks/track_03.tres",
	"res://data/tracks/track_04.tres",
]
const KART_COUNT: int = 8
const COUNTDOWN_TIMEOUT_TICKS: int = 600
const POST_GO_TICKS: int = 10
const HOVER_TOLERANCE: float = 0.03
## An upright kart on a sloped grid (Glacier Crown, ~7 degrees) must ride a
## little higher than hover so its body box clears the road; never float more.
const MAX_SLOPE_LIFT: float = 0.15
## Allowed vertical motion across GO for a kart given zero input.
const GO_POP_TOLERANCE: float = 0.02


func test_every_grid_kart_waits_on_the_road_and_does_not_pop_at_go() -> void:
	for path: String in TRACKS:
		await _check_track(path)


func _check_track(track_path: String) -> void:
	var track_name: String = track_path.get_file()
	var manager: Node = (load(RACE_SCENE_PATH) as PackedScene).instantiate()
	manager.call("configure", _make_config(track_path), _make_zero_input_provider)
	add_child(manager)
	var karts: Array[KartController] = manager.call("get_karts") as Array[KartController]
	_silence_ai(karts)
	# Spawned inside physics tick N; the settle must have run by the end of
	# tick N+1, before NetRace's first snapshot could ever go out (tick N+2 at
	# the earliest: SNAPSHOT_INTERVAL = 3 ticks after the session runs).
	await wait_physics_frames(2)
	assert_eq(int(manager.call("get_state")), RaceState.COUNTDOWN, "%s: still counting down" % track_name)
	assert_eq(karts.size(), KART_COUNT)
	var countdown_y: Array[float] = []
	for slot: int in range(karts.size()):
		var kart: KartController = karts[slot]
		var gap: float = _height_above_road(kart)
		countdown_y.append(kart.global_position.y)
		assert_between(gap, kart.tuning.hover_height - HOVER_TOLERANCE, kart.tuning.hover_height + MAX_SLOPE_LIFT,
			"%s slot %d must rest at hover height above the road during the countdown" % [track_name, slot])
		assert_false(_body_overlaps_world(kart), "%s slot %d body must not sit inside the road" % [track_name, slot])
		assert_true(_center_ray_hits(kart), "%s slot %d ground ray must see the road during the countdown" % [track_name, slot])
		assert_null(kart.get_node_or_null("GridSettle"), "%s slot %d settle must finish on the first tick after spawn" % [track_name, slot])
	for _tick: int in range(COUNTDOWN_TIMEOUT_TICKS):
		if int(manager.call("get_state")) == RaceState.RACING:
			break
		await wait_physics_frames(1)
	assert_eq(int(manager.call("get_state")), RaceState.RACING, "%s: race must start" % track_name)
	await wait_physics_frames(POST_GO_TICKS)
	for slot: int in range(karts.size()):
		assert_almost_eq(karts[slot].global_position.y, countdown_y[slot], GO_POP_TOLERANCE,
			"%s slot %d must not pop vertically at GO" % [track_name, slot])
	remove_child(manager)
	manager.free()
	await wait_physics_frames(1)


func _make_config(track_path: String) -> RaceConfig:
	var config: RaceConfig = RaceConfig.new()
	config.track = load(track_path) as TrackData
	config.laps = 1
	config.kart_count = KART_COUNT
	config.player_kart = load("res://data/karts/medium.tres") as KartData
	config.set("player_slot", 0)
	return config


## Kart origin height above the world (layer 1) surface directly below it;
## INF when no road is found.
func _height_above_road(kart: KartController) -> float:
	var origin: Vector3 = kart.global_position
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		origin + Vector3.UP * 5.0, origin + Vector3.DOWN * 5.0, 1)
	var hit: Dictionary = kart.get_world_3d().direct_space_state.intersect_ray(query)
	return origin.y - (hit["position"] as Vector3).y if not hit.is_empty() else INF


func _body_overlaps_world(kart: KartController) -> bool:
	var body_shape: CollisionShape3D = kart.get_node("CollisionShape3D") as CollisionShape3D
	var params: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	params.shape = body_shape.shape
	params.transform = body_shape.global_transform
	params.collision_mask = 1
	return not kart.get_world_3d().direct_space_state.intersect_shape(params, 1).is_empty()


func _center_ray_hits(kart: KartController) -> bool:
	var ray: RayCast3D = kart.get_node("GroundRays/RayCenter") as RayCast3D
	ray.force_raycast_update()
	return ray.is_colliding()


## Every kart, human slot and AI slots alike, gets zero input, so any
## vertical motion after GO comes from the spawn height, not from driving.
func _silence_ai(karts: Array[KartController]) -> void:
	for kart: KartController in karts:
		var ai: Node = kart.get_node_or_null("AIController")
		if ai != null:
			ai.process_mode = Node.PROCESS_MODE_DISABLED
		kart.set_input_provider(InputProvider.new())


func _make_zero_input_provider(_kart: KartController, _line: RacingLine) -> InputProvider:
	return InputProvider.new()
