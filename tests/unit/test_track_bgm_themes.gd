extends GutTest

## Verifies the per-track BGM themes added in Phase 18c: each of the four
## tracks gets its own deterministic bass+lead loop (32-48s) instead of all
## four sharing the same 13.3s "race" loop.

const GENERATOR_PATH: String = "res://tools/gen_placeholder_audio.gd"
const SAMPLE_RATE: int = 22_050
const EXPECTED_TRACK_IDS: PackedStringArray = [
	"ridgeline_circuit", "lumen_underpass", "glacier_crown", "ochre_rift",
]


func test_all_four_tracks_have_an_authored_theme() -> void:
	var generator: Object = _new_generator()
	var themes: Dictionary = generator.get("TRACK_THEMES")
	for id: String in EXPECTED_TRACK_IDS:
		assert_true(themes.has(StringName(id)), "missing theme for '%s'" % id)


func test_track_themes_render_between_32_and_48_seconds() -> void:
	var generator: Object = _new_generator()
	var themes: Dictionary = generator.get("TRACK_THEMES")
	for id: String in EXPECTED_TRACK_IDS:
		var samples: PackedFloat32Array = generator.call("_render_track_theme", themes[StringName(id)])
		var seconds: float = float(samples.size()) / SAMPLE_RATE
		assert_between(seconds, 32.0, 48.0, "'%s' loop should be 32-48s, was %.2fs" % [id, seconds])


func test_same_theme_renders_identical_samples() -> void:
	var generator: Object = _new_generator()
	var theme: Dictionary = (generator.get("TRACK_THEMES") as Dictionary)[&"ridgeline_circuit"]
	var samples_a: PackedFloat32Array = generator.call("_render_track_theme", theme)
	var samples_b: PackedFloat32Array = generator.call("_render_track_theme", theme)
	assert_eq(samples_a, samples_b)


func test_each_track_theme_sounds_distinct_from_the_others() -> void:
	var generator: Object = _new_generator()
	var themes: Dictionary = generator.get("TRACK_THEMES")
	var seen: Array[PackedFloat32Array] = []
	for id: String in EXPECTED_TRACK_IDS:
		var samples: PackedFloat32Array = generator.call("_render_track_theme", themes[StringName(id)])
		for other: PackedFloat32Array in seen:
			var length: int = mini(samples.size(), other.size())
			assert_ne(samples.slice(0, length), other.slice(0, length), "'%s' should differ from an earlier theme" % id)
		seen.append(samples)


func _new_generator() -> Object:
	var script: GDScript = load(GENERATOR_PATH) as GDScript
	return script.new()
