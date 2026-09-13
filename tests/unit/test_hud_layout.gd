extends GutTest

const LAYOUT_PATH: String = "res://ui/hud/hud.gd"
const MAJOR_REGIONS: Array[String] = ["position", "minimap", "drift", "speedometer", "item"]


func test_major_regions_stay_in_bounds_and_do_not_overlap_at_supported_sizes() -> void:
	assert_true(ResourceLoader.exists(LAYOUT_PATH), "HUD layout policy must exist")
	if not ResourceLoader.exists(LAYOUT_PATH):
		return
	var layout_script: GDScript = load(LAYOUT_PATH) as GDScript
	for viewport_size: Vector2 in [Vector2(800.0, 450.0), Vector2(1600.0, 900.0)]:
		var layout: Dictionary = layout_script.call("layout_for_viewport", viewport_size)
		var regions: Dictionary = layout["regions"]
		var bounds: Rect2 = Rect2(Vector2.ZERO, viewport_size)
		var visible_regions: Array[String] = MAJOR_REGIONS.duplicate()
		if not bool(layout["speedometer_visible"]):
			visible_regions.erase("speedometer")
		for name: String in visible_regions:
			assert_true(bounds.encloses(regions[name]), "%s stays inside %s" % [name, viewport_size])
		for first: int in range(visible_regions.size()):
			for second: int in range(first + 1, visible_regions.size()):
				var first_name: String = visible_regions[first]
				var second_name: String = visible_regions[second]
				assert_false(
					(regions[first_name] as Rect2).intersects(regions[second_name]),
					"%s and %s do not overlap at %s" % [first_name, second_name, viewport_size],
				)
