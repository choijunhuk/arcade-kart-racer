extends GutTest

const PROBE: Script = preload("res://scenes/test/collision_probe.gd")


func test_flat_wall_flag_selects_seam_free_probe_geometry() -> void:
	var defaults: Dictionary = PROBE.parse_options(PackedStringArray())
	var selected: Dictionary = PROBE.parse_options(PackedStringArray(["--flat-wall"]))

	assert_false(bool(defaults["flat_wall"]))
	assert_true(bool(selected["flat_wall"]))
