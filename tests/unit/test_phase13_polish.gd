extends GutTest

func test_chassis_has_closed_triangle_faces() -> void:
	var data: KartData = load("res://data/karts/light.tres") as KartData
	assert_eq(KartMeshBuilder.chassis(data).surface_get_array_len(0), 96)

func test_mesh_bounds_follow_weight_class() -> void:
	var light: KartData = load("res://data/karts/light.tres") as KartData
	var heavy: KartData = load("res://data/karts/heavy.tres") as KartData
	assert_gt(KartMeshBuilder.chassis(heavy).get_aabb().size.x, KartMeshBuilder.chassis(light).get_aabb().size.x)

func test_six_unique_silhouettes() -> void:
	var sizes: Array[Vector3] = []
	for resource: Resource in ResourceScanner.scan_tres("res://data/karts"):
		var size: Vector3 = KartMeshBuilder.chassis(resource as KartData).get_aabb().size
		assert_false(sizes.has(size))
		sizes.append(size)
	assert_eq(sizes.size(), 6)

func test_lod_boundaries() -> void:
	assert_eq(QualityTier.lod(0.0), 0)
	assert_eq(QualityTier.lod(45.0), 1)
	assert_eq(QualityTier.lod(100.0), 2)

func test_low_quality_disables_expensive_features() -> void:
	var values: Dictionary = QualityTier.settings(0)
	assert_false(values.shadows)
	assert_false(values.fog)
	assert_eq(values.msaa, 0)
	assert_eq(values.render_scale, 0.65)

func test_quality_clamps() -> void:
	assert_eq(QualityTier.settings(-1), QualityTier.settings(0))
	assert_eq(QualityTier.settings(9), QualityTier.settings(2))

func test_loading_progress_never_regresses() -> void:
	var model: LoadingProgress = LoadingProgress.new()
	model.begin()
	model.update(ResourceLoader.THREAD_LOAD_IN_PROGRESS, 0.7)
	model.update(ResourceLoader.THREAD_LOAD_IN_PROGRESS, 0.2)
	assert_eq(model.progress, 0.7)

func test_loaded_is_terminal() -> void:
	var model: LoadingProgress = LoadingProgress.new()
	model.begin()
	model.update(ResourceLoader.THREAD_LOAD_LOADED, 0.8)
	model.update(ResourceLoader.THREAD_LOAD_FAILED, 0.0)
	assert_eq(model.state, LoadingProgress.State.READY)
	assert_eq(model.progress, 1.0)

func test_failure_can_restart() -> void:
	var model: LoadingProgress = LoadingProgress.new()
	model.begin()
	model.update(ResourceLoader.THREAD_LOAD_FAILED, 0.2)
	assert_eq(model.state, LoadingProgress.State.FAILED)
	model.begin()
	assert_eq(model.state, LoadingProgress.State.LOADING)
	assert_eq(model.progress, 0.0)

func test_minimap_thin_track_has_readable_depth() -> void:
	var points: PackedVector3Array = PackedVector3Array([Vector3(0, 0, 0), Vector3(1000, 0, 10)])
	var projected: PackedVector2Array = MinimapProjection.normalize_points(points)
	assert_gte(projected[1].y - projected[0].y, 0.3)
	assert_gt(projected[0].x, 0.0)
	assert_lt(projected[1].x, 1.0)

func test_hills_ramp_leading_top_edge_is_buried() -> void:
	var scene: PackedScene = load("res://track/tracks/test_loop_hills/test_loop_hills.tscn") as PackedScene
	var track: Node3D = scene.instantiate() as Node3D
	var ramp: CollisionShape3D = track.get_node("Geometry/RampUpCollision") as CollisionShape3D
	var box: BoxShape3D = ramp.shape as BoxShape3D
	var leading_top: Vector3 = ramp.transform * Vector3(-box.size.x * 0.5, box.size.y * 0.5, 0.0)
	assert_lte(leading_top.y, 0.0, "a protruding end cap traps low-speed AI karts")
	track.free()

func test_track_art_has_no_kart_dependencies() -> void:
	var sources: Array[String] = []
	_collect_track_sources("res://track", sources)
	for file: String in DirAccess.get_files_at("res://tools"):
		if file.begins_with("track_") and file.ends_with(".gd"):
			sources.append("res://tools/" + file)
	assert_gt(sources.size(), 0)
	for path: String in sources:
		var source: String = FileAccess.get_file_as_string(path)
		assert_false(source.contains("KartMeshBuilder"), path)
		assert_false(source.contains("res://kart/"), path)

func _collect_track_sources(directory: String, sources: Array[String]) -> void:
	for file: String in DirAccess.get_files_at(directory):
		if file.ends_with(".gd"):
			sources.append(directory.path_join(file))
	for child: String in DirAccess.get_directories_at(directory):
		_collect_track_sources(directory.path_join(child), sources)

func test_road_builder_preserves_supplied_color() -> void:
	var body: StaticBody3D = StaticBody3D.new()
	add_child_autofree(body)
	var path: Path3D = Path3D.new()
	path.curve = Curve3D.new()
	path.curve.add_point(Vector3.ZERO)
	path.curve.add_point(Vector3(0, 0, 16))
	body.add_child(path)
	var paint: StandardMaterial3D = TrackArt.surface(Color(0.2, 0.3, 0.4).lightened(0.25))
	TrackBuilder.build_road_segments(body, path, 14.0, 0.4, paint)
	var visual: MeshInstance3D = body.get_child(body.get_child_count() - 1) as MeshInstance3D
	assert_eq((visual.mesh.surface_get_material(0) as StandardMaterial3D).albedo_color, paint.albedo_color)

func test_chassis_palette_preserved() -> void:
	var data: KartData = load("res://data/karts/light.tres") as KartData
	var paint: StandardMaterial3D = KartMeshBuilder.chassis(data).surface_get_material(0) as StandardMaterial3D
	assert_eq(paint.albedo_color, data.body_color)
	assert_almost_eq(paint.metallic, 0.28, 0.00001)
	assert_almost_eq(paint.roughness, 0.38, 0.00001)

func test_transition_failure_reveals_scene_and_keeps_recovery() -> void:
	var overlay: TransitionOverlay = preload("res://ui/components/transition_overlay.tscn").instantiate() as TransitionOverlay
	add_child_autofree(overlay)
	overlay.visible = true
	var fade: ColorRect = overlay.get_node("Fade") as ColorRect
	fade.modulate.a = 1.0
	var loading: Control = preload("res://ui/components/loading_screen.tscn").instantiate() as Control
	overlay.add_child(loading)
	await overlay._show_failure(loading, "Expected scene load failure")
	assert_push_error("Expected scene load failure")
	assert_false(overlay.is_queued_for_deletion())
	assert_true(overlay.visible)
	assert_almost_eq(fade.modulate.a, 0.0, 0.001)
	assert_false(is_instance_valid(loading))
	var panel: PanelContainer = overlay.get_node("LoadError") as PanelContainer
	var label: Label = panel.find_children("*", "Label", true, false)[0] as Label
	assert_eq(label.text, "Unable to load this scene.")
	var back: Button = panel.find_children("*", "Button", true, false)[0] as Button
	assert_eq(back.text, "Back to menu")
	assert_true(back.pressed.is_connected(overlay._back_to_menu))
	assert_true(back.has_focus())
