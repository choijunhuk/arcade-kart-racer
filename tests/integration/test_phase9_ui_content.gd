extends GutTest

const DRIVER_DIRECTORY: String = "res://data/drivers"
const THEME_PATH: String = "res://ui/theme/default_theme.tres"
const TRANSITION_PATH: String = "res://ui/components/transition_overlay.tscn"
const RACE_SCENE: PackedScene = preload("res://race/race.tscn")
const TRACK: TrackData = preload("res://data/tracks/track_01.tres")
const KART: KartData = preload("res://data/karts/medium.tres")
const DIFFICULTY: AIDifficultyProfile = preload("res://data/ai/normal.tres")
const FLOAT_EPSILON: float = 0.001


func after_each() -> void:
	get_tree().paused = false


func test_driver_directory_contains_eight_unique_colored_resources() -> void:
	var resources: Array[Resource] = ResourceScanner.scan_tres(DRIVER_DIRECTORY)
	var ids: Dictionary[StringName, bool] = {}
	assert_eq(resources.size(), 8)
	for resource: Resource in resources:
		assert_true(resource is DriverData)
		if not resource is DriverData:
			continue
		var driver: DriverData = resource as DriverData
		assert_false(ids.has(driver.id), "driver ids must be unique")
		ids[driver.id] = true
		assert_false(driver.display_name.is_empty())
		assert_true(_has_property(driver, &"driver_color"))


func test_shipped_driver_modifiers_stay_between_three_and_five_percent() -> void:
	var resources: Array[Resource] = ResourceScanner.scan_tres(DRIVER_DIRECTORY)
	assert_eq(resources.size(), 8)
	for resource: Resource in resources:
		if not resource is DriverData:
			continue
		var driver: DriverData = resource as DriverData
		assert_gt(driver.stat_mods.size(), 0)
		for modifier: float in driver.stat_mods.values():
			assert_gte(absf(modifier), 0.03)
			assert_lte(absf(modifier), 0.05)


func test_default_theme_has_a_visible_button_focus_ring() -> void:
	var exists: bool = ResourceLoader.exists(THEME_PATH, "Theme")
	assert_true(exists)
	if not exists:
		return
	var theme: Theme = load(THEME_PATH) as Theme
	var focus: StyleBox = theme.get_stylebox(&"focus", &"Button")
	assert_not_null(focus)
	assert_true(focus is StyleBoxFlat)
	if focus is StyleBoxFlat:
		var flat: StyleBoxFlat = focus as StyleBoxFlat
		assert_gt(flat.border_width_left, 0)
		assert_gt(flat.border_width_top, 0)


func test_transition_overlay_is_a_full_screen_mouse_blocking_fade() -> void:
	var exists: bool = ResourceLoader.exists(TRANSITION_PATH, "PackedScene")
	assert_true(exists)
	if not exists:
		return
	var overlay: CanvasLayer = (load(TRANSITION_PATH) as PackedScene).instantiate() as CanvasLayer
	autofree(overlay)
	var fade: ColorRect = overlay.get_node("Fade") as ColorRect
	assert_eq(fade.anchors_preset, Control.PRESET_FULL_RECT)
	assert_eq(fade.mouse_filter, Control.MOUSE_FILTER_STOP)
	assert_true(overlay.has_method("transition_to"))


func test_race_manager_applies_selected_driver_stats_and_visual_color() -> void:
	var driver: DriverData = DriverData.new()
	var has_color: bool = _has_property(driver, &"driver_color")
	assert_true(has_color, "DriverData must expose driver_color")
	if not has_color:
		return
	driver.id = &"test_driver"
	driver.display_name = "Test Driver"
	driver.stat_mods = {&"max_speed": 0.05}
	driver.set(&"driver_color", Color(0.2, 0.7, 0.4, 1.0))
	var config: RaceConfig = RaceConfigBuilder.build(driver, KART, TRACK, DIFFICULTY, 1, 1)
	config.items_enabled = false
	var manager: RaceManager = RACE_SCENE.instantiate() as RaceManager
	manager.configure(config)
	add_child_autofree(manager)
	await wait_physics_frames(1)
	var player: KartController = manager.get_karts()[0]
	var exposes_driver: bool = player.has_method("get_driver_data")
	assert_true(exposes_driver)
	if not exposes_driver:
		return
	assert_same(player.call("get_driver_data") as DriverData, driver)
	assert_almost_eq(player.get_kart_data().max_speed, KART.max_speed * 1.05, FLOAT_EPSILON)
	var driver_mesh: MeshInstance3D = player.get_node("Visuals/Driver") as MeshInstance3D
	assert_true(driver_mesh.material_override is StandardMaterial3D)
	if driver_mesh.material_override is StandardMaterial3D:
		var material: StandardMaterial3D = driver_mesh.material_override as StandardMaterial3D
		assert_eq(material.albedo_color, Color(0.2, 0.7, 0.4, 1.0))


func _has_property(object: Object, property_name: StringName) -> bool:
	for property: Dictionary in object.get_property_list():
		if StringName(str(property.get("name", ""))) == property_name:
			return true
	return false
