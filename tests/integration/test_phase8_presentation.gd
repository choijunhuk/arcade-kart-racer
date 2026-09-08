extends GutTest

const KART_SCENE: PackedScene = preload("res://kart/kart.tscn")
const HUD_SCENE: PackedScene = preload("res://ui/hud/hud.tscn")
const RESULTS_SCENE: PackedScene = preload("res://ui/results/results_screen.tscn")
const SPEED_LINES_PATH: String = "res://effects/speed_lines.tscn"
const PERF_PROBE_PATH: String = "res://scenes/test/perf_probe.tscn"
const EPSILON: float = 0.001


func test_kart_hit_flash_uses_shader_emission() -> void:
	var kart: KartController = KART_SCENE.instantiate() as KartController
	add_child_autofree(kart)
	await wait_process_frames(1)
	var body: MeshInstance3D = kart.get_node("Visuals/Body") as MeshInstance3D
	assert_true(body.material_override is ShaderMaterial)
	if not body.material_override is ShaderMaterial:
		return
	var material: ShaderMaterial = body.material_override as ShaderMaterial
	assert_eq(material.shader.resource_path, "res://effects/hit_flash.gdshader")
	EventBus.kart_hit.emit(kart, HitReactor.HitType.SPIN_OUT)
	(kart.get_node("Visuals") as KartVisuals)._process(0.01)
	assert_gt(float(material.get_shader_parameter("flash_strength")), 0.0)


func test_hud_position_punch_and_lap_slide_start_from_events() -> void:
	var hud: RaceHud = HUD_SCENE.instantiate() as RaceHud
	add_child_autofree(hud)
	var kart: KartController = KART_SCENE.instantiate() as KartController
	add_child_autofree(kart)
	var laps: LapTracker = LapTracker.new()
	var positions: PositionTracker = PositionTracker.new()
	add_child_autofree(laps)
	add_child_autofree(positions)
	hud.bind(kart, laps, positions, 8, 3)
	var position_label: Label = hud.get_node("PositionLabel") as Label
	var lap_label: Label = hud.get_node("LapLabel") as Label
	var lap_x: float = lap_label.position.x
	EventBus.position_changed.emit(kart, 2, 1)
	EventBus.lap_completed.emit(kart, 1, 20.0)
	assert_gt(position_label.scale.x, 1.0)
	assert_lt(lap_label.position.x, lap_x)


func test_results_rows_begin_staggered_from_transparent_offset() -> void:
	var screen: ResultsScreen = RESULTS_SCENE.instantiate() as ResultsScreen
	add_child_autofree(screen)
	var manager: RaceManager = preload("res://race/race.tscn").instantiate() as RaceManager
	autofree(manager)
	var entry: RaceResults.Entry = RaceResults.Entry.new()
	entry.rank = 1
	entry.kart_name = "PlayerKart"
	entry.total_time_seconds = 30.0
	entry.best_lap_seconds = 30.0
	screen.show_results([entry], manager)
	var row: Control = screen.get_node("Panel/VBox/Rows").get_child(0) as Control
	assert_almost_eq(row.modulate.a, 0.0, EPSILON)
	assert_gt(row.position.x, 0.0)


func test_speed_lines_scene_uses_full_rect_shader_overlay() -> void:
	assert_true(ResourceLoader.exists(SPEED_LINES_PATH))
	if not ResourceLoader.exists(SPEED_LINES_PATH):
		return
	var overlay: CanvasLayer = (load(SPEED_LINES_PATH) as PackedScene).instantiate() as CanvasLayer
	autofree(overlay)
	var rect: ColorRect = overlay.get_node("Lines") as ColorRect
	assert_eq(rect.anchors_preset, Control.PRESET_FULL_RECT)
	assert_true(rect.material is ShaderMaterial)


func test_debug_overlay_is_anchored_on_the_right_of_the_hud() -> void:
	var overlay: CanvasLayer = preload("res://core/autoload/debug_overlay.tscn").instantiate() as CanvasLayer
	autofree(overlay)
	var panel: PanelContainer = overlay.get_node("Panel") as PanelContainer
	assert_almost_eq(panel.anchor_left, 1.0, EPSILON)
	assert_almost_eq(panel.anchor_right, 1.0, EPSILON)


func test_phase_ten_pitch_hooks_expose_speed_boost_and_lateral_ratios() -> void:
	var kart: KartController = KART_SCENE.instantiate() as KartController
	add_child_autofree(kart)
	kart.apply_impulse_arcade(Vector3(3.0, 0.0, -10.0), 0.0)
	assert_almost_eq(kart.get_engine_pitch_ratio(), 10.0 / kart.get_kart_data().max_speed, EPSILON)
	assert_almost_eq(kart.get_drift_squeal_ratio(), 3.0 / kart.get_kart_data().max_speed, EPSILON)
	kart.request_boost(kart.tuning.trick_boost, &"test")
	assert_almost_eq(kart.get_engine_pitch_ratio(), 10.0 / kart.get_kart_data().max_speed + 0.3, EPSILON)


func test_windowed_performance_probe_scene_is_runnable() -> void:
	assert_true(ResourceLoader.exists(PERF_PROBE_PATH))
	if not ResourceLoader.exists(PERF_PROBE_PATH):
		return
	var probe: Node = (load(PERF_PROBE_PATH) as PackedScene).instantiate()
	autofree(probe)
	assert_true(probe.has_method("build_config"))


func test_tire_smoke_rule_covers_drift_offroad_and_hard_braking() -> void:
	var script: GDScript = load("res://effects/drift_effects.gd") as GDScript
	if not script.has_method("should_emit_smoke"):
		fail_test("DriftEffects.should_emit_smoke is missing")
		return
	assert_true(bool(script.call("should_emit_smoke", true, &"asphalt", 0.0, 0.2, 0.7, 0.35)))
	assert_true(bool(script.call("should_emit_smoke", false, &"grass", 0.0, 0.4, 0.7, 0.35)))
	assert_true(bool(script.call("should_emit_smoke", false, &"asphalt", 0.8, 0.5, 0.7, 0.35)))
	assert_false(bool(script.call("should_emit_smoke", false, &"asphalt", 0.2, 0.5, 0.7, 0.35)))
