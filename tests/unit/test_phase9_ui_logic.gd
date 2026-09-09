extends GutTest

const RESOURCE_SCANNER_PATH: String = "res://core/resource_scanner.gd"
const CONFIG_BUILDER_PATH: String = "res://race/race_config_builder.gd"
const REMAP_LOGIC_PATH: String = "res://ui/menus/remap_logic.gd"
const MINIMAP_PROJECTION_PATH: String = "res://ui/hud/minimap_projection.gd"
const RESULTS_ORDERING_PATH: String = "res://ui/results/results_ordering.gd"
const SCAN_DIRECTORY: String = "user://phase9_resource_scan"
const DIFFICULTY_DIRECTORY: String = "res://data/ai"
const FLOAT_EPSILON: float = 0.001


func before_each() -> void:
	_remove_scan_directory()


func after_each() -> void:
	_remove_scan_directory()


func test_resource_scan_returns_tres_resources_sorted_by_path() -> void:
	var script: GDScript = _load_required_script(RESOURCE_SCANNER_PATH)
	if script == null:
		return
	_create_scan_directory()
	_save_named_resource("zeta.tres", "zeta")
	_save_named_resource("alpha.tres", "alpha")

	var resources: Array = script.call("scan_tres", SCAN_DIRECTORY) as Array

	assert_eq(resources.size(), 2)
	assert_eq((resources[0] as Resource).resource_name, "alpha")
	assert_eq((resources[1] as Resource).resource_name, "zeta")


func test_resource_scan_ignores_non_tres_files() -> void:
	var script: GDScript = _load_required_script(RESOURCE_SCANNER_PATH)
	if script == null:
		return
	_create_scan_directory()
	_save_named_resource("driver.tres", "driver")
	var ignored: FileAccess = FileAccess.open(SCAN_DIRECTORY + "/notes.txt", FileAccess.WRITE)
	assert_not_null(ignored)
	ignored.store_string("not a resource")
	ignored.close()

	var resources: Array = script.call("scan_tres", SCAN_DIRECTORY) as Array

	assert_eq(resources.size(), 1)
	assert_eq((resources[0] as Resource).resource_name, "driver")


func test_resource_scan_normalizes_exported_tres_remap_listing() -> void:
	var script: GDScript = _load_required_script(RESOURCE_SCANNER_PATH)
	if script == null:
		return
	_create_scan_directory()
	_save_named_resource("driver.tres", "driver")
	var exported_listing := PackedStringArray(["driver.tres.remap"])
	var scan_argument_count: int = _script_method_argument_count(script, &"scan_tres")
	assert_eq(scan_argument_count, 2)
	if scan_argument_count != 2:
		return

	var resources: Array = script.call("scan_tres", SCAN_DIRECTORY, exported_listing) as Array

	assert_eq(resources.size(), 1)
	assert_eq((resources[0] as Resource).resource_name, "driver")
	assert_eq((resources[0] as Resource).resource_path, SCAN_DIRECTORY + "/driver.tres")


func test_resource_scan_accepts_binary_res_resources() -> void:
	var script: GDScript = _load_required_script(RESOURCE_SCANNER_PATH)
	if script == null:
		return
	_create_scan_directory()
	_save_named_resource("driver.res", "driver")

	var resources: Array = script.call("scan_tres", SCAN_DIRECTORY) as Array

	assert_eq(resources.size(), 1)
	if resources.is_empty():
		return
	assert_eq((resources[0] as Resource).resource_name, "driver")


func test_race_config_builder_uses_all_selected_resources() -> void:
	var script: GDScript = _load_required_script(CONFIG_BUILDER_PATH)
	if script == null:
		return
	var driver: DriverData = DriverData.new()
	driver.id = &"nova"
	var kart: KartData = KartData.new()
	kart.id = &"medium"
	var track: TrackData = TrackData.new()
	track.id = &"ridgeline"
	track.laps_default = 4
	var difficulty: AIDifficultyProfile = AIDifficultyProfile.new()
	difficulty.id = &"hard"

	var config: RaceConfig = script.call("build", driver, kart, track, difficulty) as RaceConfig

	assert_same(config.player_driver, driver)
	assert_same(config.player_kart, kart)
	assert_same(config.track, track)
	assert_same(config.ai_difficulty, difficulty)
	assert_eq(config.laps, 4)
	assert_eq(config.kart_count, 8)
	assert_eq(config.player_slot, 0)


func test_driver_stat_mods_apply_to_a_duplicate_kart_resource() -> void:
	var script: GDScript = _load_required_script(CONFIG_BUILDER_PATH)
	if script == null:
		return
	var kart: KartData = KartData.new()
	kart.max_speed = 28.0
	kart.handling = 1.0
	var driver: DriverData = DriverData.new()
	driver.stat_mods = {&"max_speed": 0.05, &"handling": -0.03}

	var modified: KartData = script.call("apply_driver_mods", kart, driver) as KartData

	assert_not_same(modified, kart)
	assert_almost_eq(modified.max_speed, 29.4, FLOAT_EPSILON)
	assert_almost_eq(modified.handling, 0.97, FLOAT_EPSILON)
	assert_almost_eq(kart.max_speed, 28.0, FLOAT_EPSILON)


func test_driver_stat_mods_are_clamped_to_five_percent() -> void:
	var script: GDScript = _load_required_script(CONFIG_BUILDER_PATH)
	if script == null:
		return
	var kart: KartData = KartData.new()
	kart.acceleration = 10.0
	var driver: DriverData = DriverData.new()
	driver.stat_mods = {&"acceleration": 0.2}

	var modified: KartData = script.call("apply_driver_mods", kart, driver) as KartData

	assert_almost_eq(modified.acceleration, 10.5, FLOAT_EPSILON)


func test_remap_conflict_swaps_the_previous_binding() -> void:
	var script: GDScript = _load_required_script(REMAP_LOGIC_PATH)
	if script == null:
		return
	var accept_event: Dictionary = {"type": "key", "physical_keycode": KEY_ENTER}
	var cancel_event: Dictionary = {"type": "key", "physical_keycode": KEY_ESCAPE}
	var remaps: Dictionary = {
		"ui_accept": [accept_event],
		"ui_cancel": [cancel_event],
	}

	var swapped: Dictionary = script.call("swap_conflict", remaps, &"ui_accept", cancel_event) as Dictionary

	assert_eq(swapped["ui_accept"], [cancel_event])
	assert_eq(swapped["ui_cancel"], [accept_event])
	assert_eq(remaps["ui_accept"], [accept_event], "pure helper must not mutate its input")


func test_difficulty_lookup_warns_and_falls_back_for_a_stale_id() -> void:
	var menu: DifficultySelectMenu = DifficultySelectMenu.new()
	autofree(menu)

	var fallback: Resource = menu.call("_find_resource", DIFFICULTY_DIRECTORY, &"missing_difficulty") as Resource

	assert_push_warning("missing_difficulty")
	assert_not_null(fallback)
	assert_eq(StringName(str(fallback.get("id"))), &"easy")


func test_minimap_projection_preserves_aspect_and_centers_the_short_axis() -> void:
	var script: GDScript = _load_required_script(MINIMAP_PROJECTION_PATH)
	if script == null:
		return
	var points: PackedVector3Array = PackedVector3Array([
		Vector3(0.0, 2.0, 0.0),
		Vector3(20.0, 7.0, 0.0),
		Vector3(20.0, -3.0, 10.0),
	])

	var projected: PackedVector2Array = script.call("normalize_points", points) as PackedVector2Array

	assert_eq(projected.size(), 3)
	assert_almost_eq(projected[0], Vector2(0.08, 0.29), Vector2.ONE * 0.00001)
	assert_almost_eq(projected[1], Vector2(0.92, 0.29), Vector2.ONE * 0.00001)
	assert_almost_eq(projected[2], Vector2(0.92, 0.71), Vector2.ONE * 0.00001)


func test_minimap_projection_centers_a_degenerate_line() -> void:
	var script: GDScript = _load_required_script(MINIMAP_PROJECTION_PATH)
	if script == null:
		return
	var points: PackedVector3Array = PackedVector3Array([Vector3(4.0, 9.0, -2.0)])

	var projected: PackedVector2Array = script.call("normalize_points", points) as PackedVector2Array

	assert_eq(projected, PackedVector2Array([Vector2(0.5, 0.5)]))


func test_minimap_projects_a_kart_against_the_same_track_bounds() -> void:
	var script: GDScript = _load_required_script(MINIMAP_PROJECTION_PATH)
	if script == null:
		return
	assert_true(script.has_method("project_point"))
	if not script.has_method("project_point"):
		return
	var track_points: PackedVector3Array = PackedVector3Array([
		Vector3(0.0, 0.0, 0.0),
		Vector3(20.0, 0.0, 10.0),
	])

	var projected: Vector2 = script.call("project_point", Vector3(10.0, 5.0, 5.0), track_points) as Vector2

	assert_eq(projected, Vector2(0.5, 0.5))


func test_results_ordering_sorts_entries_by_rank_without_mutating_input() -> void:
	var script: GDScript = _load_required_script(RESULTS_ORDERING_PATH)
	if script == null:
		return
	var third: RaceResults.Entry = RaceResults.Entry.new()
	third.rank = 3
	var first: RaceResults.Entry = RaceResults.Entry.new()
	first.rank = 1
	var second: RaceResults.Entry = RaceResults.Entry.new()
	second.rank = 2
	var entries: Array[RaceResults.Entry] = [third, first, second]

	var ordered: Array = script.call("by_rank", entries) as Array

	assert_eq((ordered[0] as RaceResults.Entry).rank, 1)
	assert_eq((ordered[1] as RaceResults.Entry).rank, 2)
	assert_eq((ordered[2] as RaceResults.Entry).rank, 3)
	assert_eq(entries[0].rank, 3)


func _load_required_script(path: String) -> GDScript:
	var exists: bool = ResourceLoader.exists(path)
	assert_true(exists, "%s must exist" % path)
	return load(path) as GDScript if exists else null


func _script_method_argument_count(script: GDScript, method_name: StringName) -> int:
	for method: Dictionary in script.get_script_method_list():
		if StringName(str(method.get("name", ""))) == method_name:
			var arguments: Array = method.get("args", []) as Array
			return arguments.size()
	return -1


func _create_scan_directory() -> void:
	var absolute_path: String = ProjectSettings.globalize_path(SCAN_DIRECTORY)
	assert_eq(DirAccess.make_dir_recursive_absolute(absolute_path), OK)


func _save_named_resource(file_name: String, resource_name: String) -> void:
	var resource: Resource = Resource.new()
	resource.resource_name = resource_name
	assert_eq(ResourceSaver.save(resource, SCAN_DIRECTORY + "/" + file_name), OK)


func _remove_scan_directory() -> void:
	var absolute_path: String = ProjectSettings.globalize_path(SCAN_DIRECTORY)
	if not DirAccess.dir_exists_absolute(absolute_path):
		return
	var directory: DirAccess = DirAccess.open(SCAN_DIRECTORY)
	if directory != null:
		for file_name: String in directory.get_files():
			DirAccess.remove_absolute(absolute_path.path_join(file_name))
	DirAccess.remove_absolute(absolute_path)
