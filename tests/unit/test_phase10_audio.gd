extends GutTest

const EPSILON: float = 0.001
const SFX: SfxLibrary = preload("res://data/audio/sfx_default.tres")
const BGM: SfxLibrary = preload("res://data/audio/bgm_default.tres")

var _pool: SfxPool
var _music: BgmCrossfade


func before_each() -> void:
	_pool = SfxPool.new()
	add_child_autofree(_pool)
	_pool.prepare()
	_music = BgmCrossfade.new()
	_music.configure(_pool.voices[SfxPool.SPATIAL_CAPACITY], _pool.voices[SfxPool.SPATIAL_CAPACITY + 1])


func after_each() -> void:
	SettingsManager.apply_section(&"audio")
	AudioManager.set_music_ducked(false)
	AudioManager.set_engine_offroad(false)


func test_linear_volume_maps_half_to_minus_six_db_and_clamps() -> void:
	assert_almost_eq(AudioManagerService.volume_to_db(0.5), -6.0206, EPSILON)
	assert_eq(AudioManagerService.volume_to_db(1.5), 0.0)
	assert_eq(AudioManagerService.volume_to_db(-1.0), AudioManagerService.SILENCE_DB)


func test_zero_mutes_every_bus_and_positive_gain_unmutes() -> void:
	for bus: StringName in [&"Master", &"Music", &"SFX", &"Engine"]:
		var index: int = AudioServer.get_bus_index(bus)
		AudioManager.set_bus_volume(bus, 0.0)
		assert_true(AudioServer.is_bus_mute(index), String(bus))
		AudioManager.set_bus_volume(bus, 0.25)
		assert_false(AudioServer.is_bus_mute(index))
		assert_almost_eq(AudioManager.get_bus_volume(bus), 0.25, EPSILON)


func test_engine_bus_has_switchable_lowpass_and_master_send() -> void:
	var index: int = AudioServer.get_bus_index(&"Engine")
	assert_true(AudioServer.get_bus_effect(index, 0) is AudioEffectLowPassFilter)
	assert_eq(AudioServer.get_bus_send(index), &"Master")
	AudioManager.set_engine_offroad(true)
	assert_true(AudioServer.is_bus_effect_enabled(index, 0))
	AudioManager.set_engine_offroad(false)
	assert_false(AudioServer.is_bus_effect_enabled(index, 0))


func test_library_lookup_preserves_resource_and_defaults() -> void:
	var library: SfxLibrary = SfxLibrary.new()
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	library.streams[&"example"] = stream
	library.volume_db[&"example"] = -4.0
	library.pitch_variance[&"example"] = 0.1
	assert_same(library.lookup(&"example"), stream)
	assert_eq(library.get_volume_db(&"example"), -4.0)
	assert_eq(library.get_pitch_variance(&"example"), 0.1)
	assert_eq(library.get_volume_db(&"unspecified"), 0.0)


func test_missing_library_id_returns_null_and_warns_once() -> void:
	var library: SfxLibrary = SfxLibrary.new()
	assert_null(library.lookup(&"missing_phase10_test"))
	assert_null(library.lookup(&"missing_phase10_test"))
	assert_push_warning_count(1)


func test_generated_catalogue_has_all_categories_and_seven_item_pairs() -> void:
	for id: StringName in [
		&"engine", &"drift_squeal", &"drift_tier_1", &"drift_tier_2", &"drift_tier_3",
		&"boost", &"impact_wall", &"impact_kart", &"hit_spin", &"hit_tumble", &"hit_squash",
		&"item_pickup", &"roulette_tick", &"roulette_stop", &"jump", &"landing", &"countdown",
		&"go", &"lap", &"final_lap", &"finish", &"position_up", &"position_down",
		&"menu_move", &"menu_accept", &"menu_back", &"threat_warning",
	]:
		assert_not_null(SFX.lookup(id), String(id))
	for id: StringName in [&"rocket_dart", &"hunter_drone", &"spike_mine", &"nitro_can", &"aegis_bubble", &"pulse_blast", &"storm_beacon"]:
		assert_not_null(SFX.lookup(StringName("%s_fire" % id)))
		assert_not_null(SFX.lookup(StringName("%s_hit" % id)))


func test_generated_wavs_are_pcm16_mono_and_loops_survive_import() -> void:
	for library: SfxLibrary in [SFX, BGM]:
		for id: StringName in library.streams:
			var wav: AudioStreamWAV = library.lookup(id) as AudioStreamWAV
			assert_not_null(wav)
			assert_eq(wav.format, AudioStreamWAV.FORMAT_16_BITS)
			assert_eq(wav.mix_rate, 22050)
			assert_false(wav.stereo)
			assert_gt(wav.get_length(), 0.0)
	for id: StringName in [&"engine", &"drift_squeal"]:
		assert_eq((SFX.lookup(id) as AudioStreamWAV).loop_mode, AudioStreamWAV.LOOP_FORWARD)
	for id: StringName in [&"menu", &"race", &"results"]:
		var wav: AudioStreamWAV = BGM.lookup(id) as AudioStreamWAV
		assert_eq(wav.loop_mode, AudioStreamWAV.LOOP_FORWARD)
		assert_gte(wav.get_length(), 13.0, "eight bars at each authored tempo")


func test_pool_is_fixed_size_and_music_slots_are_reserved() -> void:
	_pool.prepare()
	assert_eq(_pool.get_child_count(), 24)
	for index: int in range(6):
		_start(false, index)
	assert_eq(_pool.count_active(false), 6)
	assert_null(_pool.acquire(false, -1))
	assert_false(_pool.voices[SfxPool.SPATIAL_CAPACITY].active)


func test_pool_steals_lowest_priority_before_oldest() -> void:
	var oldest: AudioVoice = _start(true, 5)
	var quietest: AudioVoice = _start(true, 1)
	for _index: int in range(14):
		_start(true, 10)
	assert_same(_pool.acquire(true, 1), quietest)
	quietest.start(SFX.lookup(&"boost"), &"SFX", 0.0, 1.0, false)
	assert_null(_pool.acquire(true, 0))
	quietest.priority = 5
	assert_same(_pool.acquire(true, 5), oldest)


func test_reacquiring_loops_cannot_steal_equal_priority_loops_each_frame() -> void:
	for _index: int in range(SfxPool.SPATIAL_CAPACITY):
		_start(true, AudioManagerService.PRIORITY_SQUEAL)
	assert_null(_pool.acquire(true, AudioManagerService.PRIORITY_SQUEAL, 0, false))
	assert_not_null(_pool.acquire(true, AudioManagerService.PRIORITY_ENGINE, 0, false))


func test_kart_limit_and_owner_release_preserve_other_karts() -> void:
	for index: int in range(3):
		_start(true, index, 101)
	var other: AudioVoice = _start(true, 20, 202)
	assert_null(_pool.acquire(true, -1, 101))
	var replacement: AudioVoice = _pool.acquire(true, 5, 101)
	replacement.start(SFX.lookup(&"boost"), &"SFX", 0.0, 1.0, false)
	assert_eq(_pool.count_owner(101), 3)
	_pool.release_owner(101)
	assert_eq(_pool.count_owner(101), 0)
	assert_true(other.active)


func test_one_shot_expiry_and_pause_do_not_depend_on_hardware() -> void:
	var voice: AudioVoice = _start(true, 0)
	_pool.step(10.0, true)
	assert_true(voice.active)
	_pool.step(10.0, false)
	assert_false(voice.active)


func test_crossfade_halfway_and_completion_stop_outgoing_track() -> void:
	_music.play(&"menu", BGM.lookup(&"menu"), 0.0, 0.0)
	_music.play(&"race", BGM.lookup(&"race"), 0.0, 2.0)
	_music.step(1.0)
	assert_almost_eq(_music.gains.x, 0.5, EPSILON)
	assert_almost_eq(_music.gains.y, 0.5, EPSILON)
	_music.step(10.0)
	assert_eq(_music.gains, Vector2(0.0, 1.0))
	assert_eq(_pool.count_active(false), 1)


func test_interrupted_reverse_crossfade_starts_at_current_gain() -> void:
	_music.play(&"menu", BGM.lookup(&"menu"), 0.0, 0.0)
	_music.play(&"race", BGM.lookup(&"race"), 0.0, 2.0)
	_music.step(0.5)
	_music.play(&"menu", BGM.lookup(&"menu"), 0.0, 1.0)
	assert_eq(_music.gains, Vector2(0.75, 0.25))
	_music.step(0.5)
	assert_eq(_music.gains, Vector2(0.875, 0.125))


func test_bgm_stop_and_duplicate_request_are_idempotent() -> void:
	_music.play(&"menu", BGM.lookup(&"menu"), 0.0, 2.0)
	_music.step(1.0)
	_music.play(&"menu", BGM.lookup(&"menu"), 0.0, 2.0)
	_music.step(1.0)
	assert_eq(_music.gains.x, 1.0)
	_music.stop(0.0)
	assert_eq(_pool.count_active(false), 0)
	assert_eq(_music.current_id, &"")


func test_music_duck_preserves_gain_changes_and_zero_mute() -> void:
	var index: int = AudioServer.get_bus_index(&"Music")
	AudioManager.set_bus_volume(&"Music", 0.5)
	AudioManager.set_music_ducked(true)
	assert_almost_eq(AudioServer.get_bus_volume_db(index), -14.0206, EPSILON)
	AudioManager.set_bus_volume(&"Music", 0.25)
	AudioManager.set_music_ducked(false)
	assert_almost_eq(AudioServer.get_bus_volume_db(index), -12.0412, EPSILON)
	AudioManager.set_bus_volume(&"Music", 0.0)
	AudioManager.set_music_ducked(true)
	assert_true(AudioServer.is_bus_mute(index))


func _start(spatial: bool, priority: int, owner_id: int = 0) -> AudioVoice:
	var voice: AudioVoice = _pool.acquire(spatial, priority, owner_id)
	voice.start(SFX.lookup(&"boost"), &"SFX", 0.0, 1.0, false)
	return voice


func test_engine_pitch_is_monotonic_clamped_and_adds_boost_once() -> void:
	var previous: float = KartAudio.engine_pitch(-1.0, false)
	assert_almost_eq(previous, 0.7, EPSILON)
	for index: int in range(11):
		var pitch: float = KartAudio.engine_pitch(float(index) / 10.0, false)
		assert_gte(pitch, previous)
		previous = pitch
	assert_almost_eq(KartAudio.engine_pitch(2.0, false), 2.1, EPSILON)
	assert_almost_eq(KartAudio.engine_pitch(1.3, true), 2.4, EPSILON)
	assert_almost_eq(KartAudio.engine_pitch(0.8, true), 1.7, EPSILON)
