class_name AudioManagerService
extends Node

## Content lookup, fixed voice leases, volume application and music facade.

signal sfx_played(id: StringName, spatial: bool, priority: int, pitch: float)
signal bgm_changed(id: StringName)

const MASTER_BUS: StringName = &"Master"
const MUSIC_BUS: StringName = &"Music"
const SFX_BUS: StringName = &"SFX"
const ENGINE_BUS: StringName = &"Engine"
const SILENCE_DB: float = -80.0
const PAUSE_DUCK_DB: float = -8.0
const ENGINE_FILTER_INDEX: int = 0
const OFFROAD_CUTOFF_HZ: float = 1400.0
const FINAL_LAP_PITCH: float = 1.03
const DEFAULT_CROSSFADE: float = 1.0
const PRIORITY_ENGINE: int = 30
const PRIORITY_SQUEAL: int = -10
const PRIORITY_KART: int = 20
const PRIORITY_UI: int = 50
const PRIORITY_RACE: int = 100

@export var sfx_library: SfxLibrary = preload("res://data/audio/sfx_default.tres")
@export var bgm_library: SfxLibrary = preload("res://data/audio/bgm_default.tres")

var pool: SfxPool
var bgm: BgmCrossfade = BgmCrossfade.new()
var _music_volume: float = 1.0
var _ducked: bool = false
var _final_lap: bool = false
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	ensure_audio_buses()
	prepare_sfx_pool()
	SettingsManager.apply_section(&"audio")
	SettingsManager.settings_changed.connect(_on_settings_changed)
	_rng.randomize() # Presentation-only RNG never consumes gameplay randomness.


func _process(delta: float) -> void:
	step(delta)


## Creates any missing buses/effect without replacing saved volume settings.
func ensure_audio_buses() -> void:
	for bus_name: StringName in [MUSIC_BUS, SFX_BUS, ENGINE_BUS]:
		if AudioServer.get_bus_index(bus_name) >= 0:
			continue
		AudioServer.add_bus()
		var index: int = AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, bus_name)
		AudioServer.set_bus_send(index, MASTER_BUS)
	var engine: int = AudioServer.get_bus_index(ENGINE_BUS)
	if AudioServer.get_bus_effect_count(engine) == 0:
		var filter: AudioEffectLowPassFilter = AudioEffectLowPassFilter.new()
		filter.cutoff_hz = OFFROAD_CUTOFF_HZ
		AudioServer.add_bus_effect(engine, filter)
		AudioServer.set_bus_effect_enabled(engine, ENGINE_FILTER_INDEX, false)


## Converts a clamped linear gain to finite dB; bus muting handles exact zero.
static func volume_to_db(value: float) -> float:
	var clamped: float = clampf(value, 0.0, 1.0)
	return SILENCE_DB if clamped <= 0.0 else linear_to_db(clamped)


## Applies a bus's user volume immediately, preserving additive Music ducking.
func set_bus_volume(bus_name: StringName, linear_volume: float) -> void:
	var index: int = AudioServer.get_bus_index(bus_name)
	if index < 0:
		push_error("Unknown audio bus: %s" % bus_name)
		return
	var clamped: float = clampf(linear_volume, 0.0, 1.0)
	if bus_name == MUSIC_BUS:
		_music_volume = clamped
	AudioServer.set_bus_mute(index, clamped <= 0.0)
	var duck_db: float = PAUSE_DUCK_DB if bus_name == MUSIC_BUS and _ducked else 0.0
	AudioServer.set_bus_volume_db(index, volume_to_db(clamped) + duck_db)


## Returns the user's gain, excluding temporary Music ducking.
func get_bus_volume(bus_name: StringName) -> float:
	var index: int = AudioServer.get_bus_index(bus_name)
	if index < 0 or AudioServer.is_bus_mute(index):
		return 0.0
	if bus_name == MUSIC_BUS:
		return _music_volume
	return clampf(db_to_linear(AudioServer.get_bus_volume_db(index)), 0.0, 1.0)


## Preallocates the complete fixed pool and lends its reserved slots to BGM.
func prepare_sfx_pool() -> void:
	if pool != null:
		return
	pool = SfxPool.new()
	add_child(pool)
	pool.prepare()
	bgm.configure(pool.voices[SfxPool.SPATIAL_CAPACITY], pool.voices[SfxPool.SPATIAL_CAPACITY + 1])


## Plays a named 2D sound, or a 3D sound when position is Vector3; never allocates nodes.
func play_sfx(id: StringName, position: Variant = null, priority: int = 0, pitch: float = 1.0) -> AudioVoice:
	if position != null and not position is Vector3:
		push_warning("Audio position must be Vector3 or null")
		return null
	var world_position: Vector3 = position if position is Vector3 else Vector3.ZERO
	return _play(id, position != null, world_position, priority, pitch, 0, SFX_BUS, false)


## Plays a kart-owned sound subject to its three-voice cap and the shared pool.
func play_kart_sfx(id: StringName, kart: Node3D, player: bool, priority: int = PRIORITY_KART, pitch: float = 1.0, looped: bool = false, bus: StringName = SFX_BUS) -> AudioVoice:
	return _play(id, not player, kart.global_position, priority, pitch, kart.get_instance_id(), bus, looped)


## Requests one of the three BGM tracks; repeated ids preserve playback position.
func play_bgm(id: StringName, crossfade: float = DEFAULT_CROSSFADE) -> void:
	var stream: AudioStream = bgm_library.lookup(id)
	if stream == null or id == bgm.current_id:
		return # Missing content was diagnosed by the library; duplicates are expected.
	bgm.play(id, stream, bgm_library.get_volume_db(id), crossfade)
	bgm_changed.emit(id)


## Stops music using the same deterministic crossfade timeline.
func stop_bgm(crossfade: float = DEFAULT_CROSSFADE) -> void:
	bgm.stop(crossfade)
	bgm_changed.emit(&"")


## Updates both incoming and outgoing track pitch without replacing streams.
func set_bgm_pitch_scale(pitch: float) -> void:
	bgm.set_pitch(pitch)


## Applies the optional final-lap speed-up, restoring normal pitch when cleared.
func set_final_lap(active: bool) -> void:
	_final_lap = active
	var enabled: bool = bool(SettingsManager.get_setting(&"audio", &"final_lap_pitch", true))
	set_bgm_pitch_scale(FINAL_LAP_PITCH if active and enabled else 1.0)


## Ducks music additively while keeping the persisted slider value intact.
func set_music_ducked(ducked: bool) -> void:
	_ducked = ducked
	set_bus_volume(MUSIC_BUS, _music_volume)


## Toggles the shared Engine low-pass from the local player's terrain state.
func set_engine_offroad(offroad: bool) -> void:
	AudioServer.set_bus_effect_enabled(AudioServer.get_bus_index(ENGINE_BUS), ENGINE_FILTER_INDEX, offroad)


## Advances music and SFX bookkeeping with an explicit delta, including in headless.
func step(delta: float) -> void:
	if pool == null:
		return # Unit callers may exercise the volume facade outside the scene tree.
	pool.step(delta, get_tree().paused if is_inside_tree() else false)
	bgm.step(delta)


func _play(id: StringName, spatial: bool, position: Vector3, priority: int, pitch: float, owner_id: int, bus: StringName, looped: bool) -> AudioVoice:
	var stream: AudioStream = sfx_library.lookup(id)
	if stream == null:
		return # Warn-once lookup owns the missing-id diagnostic.
	var voice: AudioVoice = pool.acquire(spatial, priority, owner_id, not looped)
	if voice == null:
		return # Priority saturation is deliberate load shedding, never an error.
	var variance: float = sfx_library.get_pitch_variance(id)
	var varied_pitch: float = maxf(AudioVoice.MIN_PITCH, pitch + _rng.randf_range(-variance, variance))
	voice.sound_id = id
	voice.pauses_with_world = spatial or owner_id != 0
	voice.start(stream, bus, sfx_library.get_volume_db(id), varied_pitch, looped)
	voice.update(1.0, varied_pitch, position)
	voice.set_paused(get_tree().paused)
	sfx_played.emit(id, spatial, priority, varied_pitch)
	return voice


func _on_settings_changed(section: StringName) -> void:
	if section == &"audio":
		set_final_lap(_final_lap)
