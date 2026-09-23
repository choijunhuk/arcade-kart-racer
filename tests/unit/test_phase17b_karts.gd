extends GutTest

## Phase 17b item 3: per-driver paint pattern must be a deterministic function
## of driver id (same id -> same pattern every call), and the roster should
## not all collapse onto a single pattern.

func test_paint_pattern_deterministic_for_same_driver() -> void:
	var driver: DriverData = load("res://data/drivers/aurora_vale.tres") as DriverData
	var body_a: MeshInstance3D = MeshInstance3D.new()
	var body_b: MeshInstance3D = MeshInstance3D.new()
	KartMeshBuilder.apply_paint_pattern(body_a, driver)
	KartMeshBuilder.apply_paint_pattern(body_b, driver)
	assert_eq(body_a.get_child_count(), body_b.get_child_count())
	body_a.free()
	body_b.free()

func test_paint_pattern_varies_across_roster() -> void:
	# Phase 19: livery patterns are shader styles (KartLivery.pattern_for), not
	# per-pattern decal child counts, so variety is checked on the pattern index.
	var patterns: Dictionary[int, bool] = {}
	for resource: Resource in ResourceScanner.scan_tres("res://data/drivers"):
		patterns[KartLivery.pattern_for(resource as DriverData)] = true
	assert_gt(patterns.size(), 1, "expected more than one distinct pattern across the driver roster")

func test_apply_paint_pattern_replaces_previous_decals() -> void:
	var drivers: Array[Resource] = ResourceScanner.scan_tres("res://data/drivers")
	var body: MeshInstance3D = MeshInstance3D.new()
	KartMeshBuilder.apply_paint_pattern(body, drivers[0] as DriverData)
	var first_count: int = body.get_child_count()
	KartMeshBuilder.apply_paint_pattern(body, drivers[1] as DriverData)
	# Re-applying should not accumulate decals from the previous driver.
	assert_true(body.get_child_count() <= 6, "decal count should stay bounded, not accumulate")
	body.free()

func test_apply_paint_pattern_handles_null_driver() -> void:
	var body: MeshInstance3D = MeshInstance3D.new()
	KartMeshBuilder.apply_paint_pattern(body, null)
	assert_eq(body.get_child_count(), 0)
	body.free()

func test_headlight_material_only_emits_on_night_theme() -> void:
	var data: KartData = load("res://data/karts/medium.tres") as KartData
	var day_visuals: Node3D = _build_visuals()
	KartMeshBuilder.decorate(day_visuals, data, false)
	var night_visuals: Node3D = _build_visuals()
	KartMeshBuilder.decorate(night_visuals, data, true)
	var day_emits: bool = _any_child_emissive(day_visuals.get_node("Body"))
	var night_emits: bool = _any_child_emissive(night_visuals.get_node("Body"))
	assert_false(day_emits, "headlights must not emit on a day-themed track")
	assert_true(night_emits, "headlights must emit on a night-themed track")
	day_visuals.free()
	night_visuals.free()

func _any_child_emissive(body: Node3D) -> bool:
	for child: Node in body.get_children():
		var mesh_child: MeshInstance3D = child as MeshInstance3D
		if mesh_child == null:
			continue
		var material: StandardMaterial3D = mesh_child.material_override as StandardMaterial3D
		if material != null and material.emission_enabled:
			return true
	return false

func _build_visuals() -> Node3D:
	var visuals: Node3D = Node3D.new()
	for child_name: String in ["Body", "Driver", "WheelFL", "WheelFR", "WheelRL", "WheelRR"]:
		var child: Node3D = MeshInstance3D.new() if child_name in ["Body", "Driver"] else Node3D.new()
		child.name = child_name
		visuals.add_child(child)
	return visuals


## Phase 19 kart-soft budget gate: one fully decorated kart (body, 4 wheels,
## driver) stays within 16k triangles at LOD0; far LODs are generated.
func test_decorated_kart_triangle_budget_per_class() -> void:
	for kart_id: String in ["light", "medium", "heavy"]:
		var data: KartData = load("res://data/karts/%s.tres" % kart_id) as KartData
		var triangles: int = KartMeshBuilder.triangle_count(data)
		assert_gt(triangles, 0, kart_id)
		assert_lte(triangles, 16000, "%s LOD0 triangles %d" % [kart_id, triangles])
