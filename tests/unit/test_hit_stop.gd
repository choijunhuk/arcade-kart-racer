extends GutTest

const HIT_STOP_PATH: String = "res://effects/hit_stop.gd"
const EPSILON: float = 0.001


func before_each() -> void:
	Engine.time_scale = 1.0


func after_each() -> void:
	Engine.time_scale = 1.0


func test_duration_rounds_up_to_three_sixty_hz_ticks() -> void:
	var script: GDScript = _require_script()
	if script == null:
		return
	assert_eq(int(script.call("ticks_for_duration", 0.05, 60)), 3)


func test_tick_restore_returns_previous_time_scale_on_boundary() -> void:
	var hit_stop: Node = _make_hit_stop(true)
	if hit_stop == null:
		return
	assert_true(bool(hit_stop.call("request", false)))
	assert_almost_eq(Engine.time_scale, 0.3, EPSILON)
	hit_stop.call("step_tick")
	hit_stop.call("step_tick")
	assert_almost_eq(Engine.time_scale, 0.3, EPSILON)
	hit_stop.call("step_tick")
	assert_almost_eq(Engine.time_scale, 1.0, EPSILON)


func test_disabled_flag_skips_time_scale_change() -> void:
	var hit_stop: Node = _make_hit_stop(false)
	if hit_stop == null:
		return
	assert_false(bool(hit_stop.call("request", false)))
	assert_almost_eq(Engine.time_scale, 1.0, EPSILON)


func test_network_mode_skips_time_scale_change() -> void:
	var hit_stop: Node = _make_hit_stop(true)
	if hit_stop == null:
		return
	assert_false(bool(hit_stop.call("request", true)))
	assert_almost_eq(Engine.time_scale, 1.0, EPSILON)


func test_headless_item_event_does_not_change_simulation_time_scale() -> void:
	var hit_stop: Node = _make_hit_stop(true)
	if hit_stop == null:
		return
	EventBus.item_hit.emit(null, null, &"test_item")
	assert_almost_eq(Engine.time_scale, 1.0, EPSILON)


func _make_hit_stop(enabled: bool) -> Node:
	var script: GDScript = _require_script()
	if script == null:
		return null
	var tuning: FeelTuning = (load("res://data/tuning/feel_default.tres") as FeelTuning).duplicate(true) as FeelTuning
	tuning.set("hit_stop_enabled", enabled)
	var hit_stop: Node = script.new() as Node
	add_child_autofree(hit_stop)
	hit_stop.call("configure", tuning)
	return hit_stop


func _require_script() -> GDScript:
	if ResourceLoader.exists(HIT_STOP_PATH):
		return load(HIT_STOP_PATH) as GDScript
	fail_test("HitStop script is missing")
	return null
