extends GutTest

## Locks the wall-only emergency recovery contract: seam failures recover at
## the last grounded transform, while ordinary cliff falls remain KillZone-owned.

const STEP: float = 1.0 / 60.0
const FALL_DISTANCE: float = 4.0

var _respawn_count: int = 0


func before_each() -> void:
	_respawn_count = 0
	EventBus.kart_respawned.connect(_on_kart_respawned)


func after_each() -> void:
	if EventBus.kart_respawned.is_connected(_on_kart_respawned):
		EventBus.kart_respawned.disconnect(_on_kart_respawned)


func test_recent_wall_contact_recovers_a_kart_that_drops_below_its_last_ground() -> void:
	var kart: KartController = await _build_grounded_kart()
	var safe_transform: Transform3D = kart.global_transform
	var respawn: RespawnSystem = _build_respawn_system(kart)
	respawn._physics_process(STEP)

	EventBus.wall_impacted.emit(kart)
	kart.global_position.y -= FALL_DISTANCE
	respawn._physics_process(STEP)

	assert_almost_eq(kart.global_position.distance_to(safe_transform.origin), 0.0, 0.01)
	assert_eq(kart.get_state(), KartState.GROUNDED)
	assert_eq(_respawn_count, 1)


func test_cliff_fall_without_wall_contact_remains_owned_by_kill_zone_flow() -> void:
	var kart: KartController = await _build_grounded_kart()
	var respawn: RespawnSystem = _build_respawn_system(kart)
	respawn._physics_process(STEP)
	var fallen_y: float = kart.global_position.y - FALL_DISTANCE

	kart.global_position.y = fallen_y
	respawn._physics_process(STEP)

	assert_almost_eq(kart.global_position.y, fallen_y, 0.001)
	assert_eq(_respawn_count, 0)


func _build_grounded_kart() -> KartController:
	var floor_body: StaticBody3D = StaticBody3D.new()
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	var floor_shape: CollisionShape3D = CollisionShape3D.new()
	var floor_box: BoxShape3D = BoxShape3D.new()
	floor_box.size = Vector3(20.0, 1.0, 20.0)
	floor_shape.shape = floor_box
	floor_shape.position = Vector3(0.0, -0.5, 0.0)
	floor_body.add_child(floor_shape)
	add_child_autofree(floor_body)
	var kart: KartController = (load("res://kart/kart.tscn") as PackedScene).instantiate() as KartController
	add_child_autofree(kart)
	kart.global_position = Vector3(0.0, 0.65, 0.0)
	await wait_physics_frames(2)
	assert_true(kart.is_grounded(), "test precondition: kart must begin grounded")
	return kart


func _build_respawn_system(kart: KartController) -> RespawnSystem:
	var respawn: RespawnSystem = RespawnSystem.new()
	respawn.set_physics_process(false)
	add_child_autofree(respawn)
	respawn.register_kart(kart, func(_target: KartController) -> Transform3D: return Transform3D.IDENTITY)
	return respawn


func _on_kart_respawned(_kart: Node) -> void:
	_respawn_count += 1
