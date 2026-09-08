extends GutTest


func test_audio_content_and_presentation_seams_exist() -> void:
	for path: String in [
		"res://default_bus_layout.tres", "res://data/audio/sfx_default.tres",
		"res://data/audio/bgm_default.tres", "res://kart/kart_audio.gd",
		"res://tools/gen_placeholder_audio.gd", "res://ui/components/ui_audio.gd",
	]:
		assert_true(FileAccess.file_exists(path), path)


func test_audio_manager_exposes_bgm_control() -> void:
	for method: StringName in [&"play_bgm", &"stop_bgm", &"set_bgm_pitch_scale"]:
		assert_true(AudioManager.has_method(method), String(method))
