extends GutTest

const SANDBOX_PATH: String = "res://scenes/test/kart_sandbox.tscn"


func test_sandbox_instantiates_track_kart_mesh_and_active_camera() -> void:
	var packed: PackedScene = load(SANDBOX_PATH) as PackedScene
	assert_not_null(packed)
	var sandbox: Node = packed.instantiate()
	add_child_autofree(sandbox)

	var kart: CharacterBody3D = sandbox.get_node("Kart") as CharacterBody3D
	var kart_mesh: MeshInstance3D = sandbox.get_node("Kart/Visuals/Body") as MeshInstance3D
	var camera: Camera3D = sandbox.get_node("RaceCamera") as Camera3D

	assert_not_null(sandbox.get_node_or_null("TestLoop/RacingLine"))
	assert_not_null(kart)
	assert_not_null(kart_mesh.mesh)
	assert_eq(kart.collision_layer, 2)
	assert_eq(kart.collision_mask, 1)
	assert_true(camera.current)


func test_test_loop_geometry_uses_world_collision_layer() -> void:
	var packed: PackedScene = load(SANDBOX_PATH) as PackedScene
	var sandbox: Node = packed.instantiate()
	add_child_autofree(sandbox)

	var geometry: StaticBody3D = sandbox.get_node("TestLoop/Geometry") as StaticBody3D

	assert_not_null(geometry)
	assert_eq(geometry.collision_layer, 1)
	assert_gte(geometry.get_child_count(), 1)


func test_debug_overlay_autoload_is_visible_in_the_sandbox_bootstrap() -> void:
	var overlay: CanvasLayer = get_tree().root.get_node_or_null("DebugOverlay") as CanvasLayer

	assert_not_null(overlay)
	assert_true(overlay.visible)


func test_sandbox_resets_kart_to_grid_slot_on_r_key() -> void:
	var packed: PackedScene = load(SANDBOX_PATH) as PackedScene
	var sandbox: Node = packed.instantiate()
	add_child_autofree(sandbox)
	await wait_physics_frames(1)

	var kart: KartController = sandbox.get_node("Kart") as KartController
	var grid_slot: Marker3D = sandbox.get_node("TestLoop/StartGrid/Grid01") as Marker3D
	kart.global_position += Vector3(5.0, 0.0, 5.0)

	var reset_event: InputEventKey = InputEventKey.new()
	reset_event.physical_keycode = KEY_R
	reset_event.pressed = true
	sandbox._unhandled_input(reset_event)

	assert_almost_eq(kart.global_position.x, grid_slot.global_position.x, 0.01)
	assert_almost_eq(kart.global_position.z, grid_slot.global_position.z, 0.01)


func test_sandbox_wires_collision_and_respawn_systems() -> void:
	var sandbox: Node = (load(SANDBOX_PATH) as PackedScene).instantiate()
	add_child_autofree(sandbox)

	assert_not_null(sandbox.get_node_or_null("KartCollisionResolver"))
	assert_not_null(sandbox.get_node_or_null("RespawnSystem"))


func test_t_key_switches_to_hills_track() -> void:
	var sandbox: Node = (load(SANDBOX_PATH) as PackedScene).instantiate()
	add_child_autofree(sandbox)
	await wait_physics_frames(1)

	sandbox._unhandled_input(_key_event(KEY_T))
	await wait_physics_frames(1)

	assert_null(sandbox.get_node_or_null("TestLoop"))
	assert_not_null(sandbox.get_node_or_null("TestLoopHills"))


func test_number_keys_swap_light_medium_and_heavy_kart_data() -> void:
	var sandbox: Node = (load(SANDBOX_PATH) as PackedScene).instantiate()
	add_child_autofree(sandbox)
	await wait_physics_frames(1)
	var kart: KartController = sandbox.get_node("Kart") as KartController

	sandbox._unhandled_input(_key_event(KEY_1))
	assert_eq(kart.kart_data.id, &"light")
	sandbox._unhandled_input(_key_event(KEY_2))
	assert_eq(kart.kart_data.id, &"medium")
	sandbox._unhandled_input(_key_event(KEY_3))
	assert_eq(kart.kart_data.id, &"heavy")


func test_b_key_spawns_three_registered_dummy_karts() -> void:
	var sandbox: Node = (load(SANDBOX_PATH) as PackedScene).instantiate()
	add_child_autofree(sandbox)
	await wait_physics_frames(1)

	sandbox._unhandled_input(_key_event(KEY_B))
	await wait_physics_frames(1)

	assert_not_null(sandbox.get_node_or_null("DummyKart1"))
	assert_not_null(sandbox.get_node_or_null("DummyKart2"))
	assert_not_null(sandbox.get_node_or_null("DummyKart3"))


func _key_event(keycode: Key) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = keycode
	event.pressed = true
	return event
