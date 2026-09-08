extends GutTest

const BUDGET_PATH: String = "res://effects/particle_budget.gd"


func test_twelve_karts_with_five_gpu_emitters_each_fit_total_budget() -> void:
	var script: GDScript = _require_script()
	if script == null:
		return
	var counts: PackedInt32Array = PackedInt32Array()
	for _kart: int in range(12):
		counts.append(5)
	assert_true(bool(script.call("counts_fit", counts, 6, 60)))


func test_budget_rejects_per_kart_or_total_overflow() -> void:
	var script: GDScript = _require_script()
	if script == null:
		return
	assert_false(bool(script.call("counts_fit", PackedInt32Array([7]), 6, 60)))
	assert_false(bool(script.call("counts_fit", PackedInt32Array([6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 1]), 6, 60)))


func test_particle_lod_disables_only_beyond_eighty_metres() -> void:
	var script: GDScript = _require_script()
	if script == null:
		return
	assert_true(bool(script.call("within_lod_distance", Vector3.ZERO, Vector3(0.0, 0.0, 80.0), 80.0)))
	assert_false(bool(script.call("within_lod_distance", Vector3.ZERO, Vector3(0.0, 0.0, 80.01), 80.0)))


func test_particle_quality_maps_low_medium_and_high_to_density_ratios() -> void:
	var script: GDScript = load("res://effects/particle_budget_controller.gd") as GDScript
	assert_true(script.has_method("quality_ratio"))
	if not script.has_method("quality_ratio"):
		return
	assert_almost_eq(float(script.call("quality_ratio", 0)), 0.35, 0.001)
	assert_almost_eq(float(script.call("quality_ratio", 1)), 0.65, 0.001)
	assert_almost_eq(float(script.call("quality_ratio", 2)), 1.0, 0.001)


func _require_script() -> GDScript:
	if ResourceLoader.exists(BUDGET_PATH):
		return load(BUDGET_PATH) as GDScript
	fail_test("ParticleBudget script is missing")
	return null
