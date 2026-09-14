extends GutTest

## Verifies the functional item-icon silhouettes added in Phase 18c:
## generation is deterministic, distinct items render distinct shapes, and
## icon colors are grouped by function category (attack/defense/boost/deploy).

const GENERATOR_PATH: String = "res://tools/generate_ui_art.gd"
const ATTACK_COLOR: Color = Color(0.92, 0.16, 0.16)


func test_same_item_id_produces_identical_pixels() -> void:
	var generator: Object = _new_generator()
	var image_a: Image = generator.call("_draw", "items", ATTACK_COLOR, 42, StringName("rocket_dart"))
	var image_b: Image = generator.call("_draw", "items", ATTACK_COLOR, 42, StringName("rocket_dart"))
	assert_eq(image_a.get_data(), image_b.get_data())


func test_known_item_silhouettes_are_distinct_from_each_other() -> void:
	var generator: Object = _new_generator()
	var ids: PackedStringArray = PackedStringArray([
		"rocket_dart", "triple_dart", "hunter_drone", "spike_mine", "nitro_can",
		"aegis_bubble", "pulse_blast", "storm_beacon", "phantom_decoy",
	])
	var seen: Array[PackedByteArray] = []
	for id: String in ids:
		var image: Image = generator.call("_draw", "items", ATTACK_COLOR, 1, StringName(id))
		var data: PackedByteArray = image.get_data()
		for other: PackedByteArray in seen:
			assert_ne(data, other, "silhouette for '%s' should differ from earlier items" % id)
		seen.append(data)


func test_unknown_item_id_falls_back_to_deterministic_radial_shape() -> void:
	var generator: Object = _new_generator()
	var image_a: Image = generator.call("_draw", "items", ATTACK_COLOR, 99, StringName("future_item"))
	var image_b: Image = generator.call("_draw", "items", ATTACK_COLOR, 99, StringName("future_item"))
	assert_eq(image_a.get_data(), image_b.get_data())


func test_item_category_colors_are_grouped_by_function() -> void:
	var generator: Object = _new_generator()
	var attack: Color = generator.call("_item_category_color", ItemData.ItemCategory.PROJECTILE)
	var defense: Color = generator.call("_item_category_color", ItemData.ItemCategory.SHIELD)
	var boost: Color = generator.call("_item_category_color", ItemData.ItemCategory.BOOST)
	var deploy: Color = generator.call("_item_category_color", ItemData.ItemCategory.TRAP)

	assert_true(attack.r > attack.g and attack.r > attack.b, "attack color should read as red")
	assert_true(defense.b > defense.r and defense.b > defense.g, "defense color should read as blue")
	assert_true(boost.r > 0.5 and boost.g > 0.5 and boost.b < boost.r, "boost color should read as yellow")
	assert_true(deploy.r > deploy.g and deploy.b > deploy.g, "deploy color should read as purple")


func _new_generator() -> Object:
	var script: GDScript = load(GENERATOR_PATH) as GDScript
	return script.new()
