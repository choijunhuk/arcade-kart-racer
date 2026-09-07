extends GutTest

const KART_SCENE: PackedScene = preload("res://kart/kart.tscn")


func test_kart_scene_contains_phase2_sensor_contact_and_hit_components() -> void:
	var kart: KartController = KART_SCENE.instantiate() as KartController
	add_child_autofree(kart)

	var terrain_probe: Area3D = kart.get_node_or_null("TerrainProbe") as Area3D
	var bump_area: Area3D = kart.get_node_or_null("BumpArea") as Area3D
	var slipstream_cast: ShapeCast3D = kart.get_node_or_null("SlipstreamSensor/ShapeCast3D") as ShapeCast3D

	assert_not_null(kart.get_node_or_null("TerrainSensor"))
	assert_not_null(kart.get_node_or_null("HitReactor"))
	assert_not_null(terrain_probe)
	assert_not_null(bump_area)
	assert_not_null(slipstream_cast)
	if terrain_probe != null:
		assert_eq(terrain_probe.collision_layer, 0)
		assert_eq(terrain_probe.collision_mask, 16)
	if bump_area != null:
		assert_eq(bump_area.collision_layer, 4)
		assert_eq(bump_area.collision_mask, 4)
	if slipstream_cast != null:
		assert_eq(slipstream_cast.collision_mask, 2)


func test_controller_phase2_read_api_starts_in_neutral_state() -> void:
	var floor_body: StaticBody3D = _build_floor()
	add_child_autofree(floor_body)
	var kart: KartController = KART_SCENE.instantiate() as KartController
	add_child_autofree(kart)
	kart.global_position = Vector3(0.0, 0.65, 0.0)
	await wait_physics_frames(1)

	assert_almost_eq(kart.get_lateral_speed(), 0.0, 0.001)
	assert_almost_eq(kart.get_air_time(), 0.0, 0.001)
	assert_almost_eq(kart.get_mass(), kart.kart_data.weight, 0.001)
	assert_false(kart.is_invulnerable())
	assert_eq(kart.get_terrain_id(), &"asphalt")


func test_kart_scene_contains_phase3_drift_and_boost_controllers() -> void:
	var kart: KartController = KART_SCENE.instantiate() as KartController
	add_child_autofree(kart)

	assert_not_null(kart.get_node_or_null("DriftController") as DriftController)
	assert_not_null(kart.get_node_or_null("BoostController") as BoostController)


func _build_floor() -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(10.0, 1.0, 10.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	body.add_child(shape)
	return body
