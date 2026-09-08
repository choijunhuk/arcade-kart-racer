extends GutTest

const HUD_SCENE: PackedScene = preload("res://ui/hud/hud.tscn")
const MINIMAP_PATH: String = "res://ui/hud/minimap.tscn"
const KART_SCENE: PackedScene = preload("res://kart/kart.tscn")

var _speedometer_before: Variant


func before_each() -> void:
	_speedometer_before = SettingsManager.get_setting(&"gameplay", &"speedometer", true)


func after_each() -> void:
	SettingsManager.set_setting(&"gameplay", &"speedometer", _speedometer_before)


func test_final_hud_has_all_regions_and_stays_below_debug_overlay_on_the_right() -> void:
	var hud: RaceHud = HUD_SCENE.instantiate() as RaceHud
	autofree(hud)
	assert_not_null(hud.get_node_or_null("PositionCountLabel"))
	assert_not_null(hud.get_node_or_null("Minimap"))
	assert_not_null(hud.get_node_or_null("Speedometer"))
	assert_not_null(hud.get_node_or_null("ItemPanel/CooldownBar"))
	var item_panel: Control = hud.get_node("ItemPanel") as Control
	assert_gte(item_panel.offset_top, 220.0)
	assert_eq(item_panel.anchor_right, 1.0)
	assert_not_null(item_panel.theme)


func test_minimap_draws_baked_line_and_one_dot_per_kart() -> void:
	var exists: bool = ResourceLoader.exists(MINIMAP_PATH, "PackedScene")
	assert_true(exists)
	if not exists:
		return
	var minimap: Control = (load(MINIMAP_PATH) as PackedScene).instantiate() as Control
	add_child_autofree(minimap)
	var line: RacingLine = RacingLine.new()
	var curve: Curve3D = Curve3D.new()
	curve.add_point(Vector3(0.0, 0.0, 0.0))
	curve.add_point(Vector3(20.0, 0.0, 0.0))
	curve.add_point(Vector3(20.0, 0.0, 10.0))
	line.curve = curve
	add_child_autofree(line)
	var player: KartController = KART_SCENE.instantiate() as KartController
	var rival: KartController = KART_SCENE.instantiate() as KartController
	add_child_autofree(player)
	add_child_autofree(rival)
	player.global_position = Vector3(10.0, 0.0, 0.0)
	rival.global_position = Vector3(20.0, 0.0, 5.0)
	await wait_process_frames(1)
	assert_true(minimap.has_method("bind"))
	if not minimap.has_method("bind"):
		return
	var karts: Array[KartController] = [player, rival]
	minimap.call("bind", line, karts, player)
	minimap.call("force_update")

	assert_gt((minimap.get_node("TrackLine") as Line2D).points.size(), 2)
	assert_eq(minimap.get_node("Dots").get_child_count(), 2)
	assert_gt((minimap.get_node("Dots").get_child(0) as Polygon2D).scale.x, 1.0)


func test_speedometer_setting_hides_and_restores_the_readout() -> void:
	var hud: RaceHud = HUD_SCENE.instantiate() as RaceHud
	add_child_autofree(hud)
	var kart: KartController = KART_SCENE.instantiate() as KartController
	add_child_autofree(kart)
	var laps: LapTracker = LapTracker.new()
	var positions: PositionTracker = PositionTracker.new()
	add_child_autofree(laps)
	add_child_autofree(positions)
	hud.bind(kart, laps, positions, 1, 1)
	SettingsManager.set_setting(&"gameplay", &"speedometer", false)
	hud._process(0.0)
	var speedometer: Control = hud.get_node_or_null("Speedometer") as Control
	assert_not_null(speedometer)
	if speedometer == null:
		return
	assert_false(speedometer.visible)
	SettingsManager.set_setting(&"gameplay", &"speedometer", true)
	hud._process(0.0)
	assert_true(speedometer.visible)


func test_item_cooldown_progress_reads_the_item_manager_api() -> void:
	var hud: RaceHud = HUD_SCENE.instantiate() as RaceHud
	add_child_autofree(hud)
	var kart: KartController = KART_SCENE.instantiate() as KartController
	add_child_autofree(kart)
	var manager: ItemManager = ItemManager.new()
	add_child_autofree(manager)
	manager.setup(null, null, null, 17)
	manager.register_kart(kart)
	var item: ItemData = preload("res://data/items/nitro_can.tres")
	manager.give_item(kart, item)
	manager.use_item(kart, InputFrame.zero())
	var laps: LapTracker = LapTracker.new()
	var positions: PositionTracker = PositionTracker.new()
	add_child_autofree(laps)
	add_child_autofree(positions)
	hud.bind(kart, laps, positions, 1, 1, manager)
	hud._process(0.0)

	var cooldown: ProgressBar = hud.get_node_or_null("ItemPanel/CooldownBar") as ProgressBar
	assert_not_null(cooldown)
	if cooldown != null:
		assert_almost_eq(cooldown.value, 100.0, 0.001)
