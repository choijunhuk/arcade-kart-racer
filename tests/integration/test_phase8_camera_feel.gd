extends GutTest

const RACE_SCENE: PackedScene = preload("res://race/race.tscn")
const KART_SCENE: PackedScene = preload("res://kart/kart.tscn")
const CAMERA_SCENE: PackedScene = preload("res://camera/race_camera.tscn")
const PARTICLE_BUDGET_PATH: String = "res://effects/particle_budget.gd"

var _shake_strength_before: Variant


func before_each() -> void:
	_shake_strength_before = SettingsManager.get_setting(&"gameplay", &"shake_strength", 100.0)
	Engine.time_scale = 1.0


func after_each() -> void:
	SettingsManager.set_setting(&"gameplay", &"shake_strength", _shake_strength_before)
	Engine.time_scale = 1.0


func test_target_kart_hit_adds_camera_trauma_then_decay_reaches_zero() -> void:
	var kart: KartController = KART_SCENE.instantiate() as KartController
	add_child_autofree(kart)
	var camera: Node = CAMERA_SCENE.instantiate()
	add_child_autofree(camera)
	if not camera.has_method("get_trauma"):
		fail_test("RaceCamera trauma API is missing")
		return
	camera.call("set_target", kart)
	assert_true(kart.apply_hit(HitReactor.HitType.SPIN_OUT, null, true))
	assert_gt(float(camera.call("get_trauma")), 0.0)
	for _frame: int in range(120):
		camera.call("_process", 1.0 / 60.0)
	assert_almost_eq(float(camera.call("get_trauma")), 0.0, 0.001)


func test_zero_shake_setting_keeps_camera_transform_unchanged_after_hit() -> void:
	SettingsManager.set_setting(&"gameplay", &"shake_strength", 0.0)
	var kart: KartController = KART_SCENE.instantiate() as KartController
	add_child_autofree(kart)
	var camera: Node3D = CAMERA_SCENE.instantiate() as Node3D
	add_child_autofree(camera)
	if not camera.has_method("get_trauma"):
		fail_test("RaceCamera trauma API is missing")
		return
	camera.call("set_target", kart)
	var before_hit: Transform3D = camera.global_transform
	assert_true(kart.apply_hit(HitReactor.HitType.SPIN_OUT, null, true))
	camera.call("_process", 1.0 / 60.0)
	assert_eq(camera.global_transform, before_hit)


func test_eight_kart_race_stays_inside_particle_node_budgets() -> void:
	var race: RaceManager = RACE_SCENE.instantiate() as RaceManager
	add_child_autofree(race)
	var budget_script: GDScript = load(PARTICLE_BUDGET_PATH) as GDScript if ResourceLoader.exists(PARTICLE_BUDGET_PATH) else null
	if budget_script == null:
		fail_test("ParticleBudget script is missing")
		return
	var counts: PackedInt32Array = PackedInt32Array()
	for kart: KartController in race.get_karts():
		counts.append(int(budget_script.call("count_gpu_particles", kart)))
	assert_eq(counts.size(), 8)
	assert_true(bool(budget_script.call("counts_fit", counts, 6, 60)))
	assert_not_null(race.get_node_or_null("ParticleBudgetController"))
	assert_not_null(race.get_node_or_null("FeedbackEffects"))
	assert_not_null(race.get_node_or_null("HitStop"))
	assert_not_null(race.get_node_or_null("SpeedLines"))
