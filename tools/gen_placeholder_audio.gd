extends SceneTree

## Offline deterministic CC0 synthesis; run with --headless --path . --script.
## PLACEHOLDER: Phase 13 replaces these original tones with final audio assets.

const OUTPUT_DIR: String = "res://assets/audio/placeholder/"
const SAMPLE_RATE: int = 22_050
const PCM_PEAK: float = 32767.0
const BYTES_PER_SAMPLE: int = 2
const EDGE_SECONDS: float = 0.008
const SHORT_SECONDS: float = 0.18
const LOOP_SECONDS: float = 1.0
const NOISE_SEED: int = 104729
const BARS: int = 8
const BEATS_PER_BAR: int = 4
const NOTES_PER_BEAT: int = 2
const SECONDS_PER_MINUTE: float = 60.0
const SEMITONES: float = 12.0
const A4_HZ: float = 440.0
const A4_MIDI: float = 69.0
const ARPEGGIO: Array[int] = [0, 4, 7, 12, 7, 4, 12, 7]
const ROOTS: Array[int] = [48, 53, 57, 55]
const ITEM_IDS: Array[StringName] = [
	&"rocket_dart", &"hunter_drone", &"spike_mine", &"nitro_can",
	&"aegis_bubble", &"pulse_blast", &"storm_beacon",
]
const AUDIO_ALIASES: Dictionary[StringName, StringName] = {
	&"triple_dart_fire": &"rocket_dart_fire", &"triple_dart_hit": &"rocket_dart_hit",
	&"phantom_decoy_fire": &"spike_mine_fire", &"phantom_decoy_hit": &"spike_mine_hit",
}
const TONES: Dictionary[StringName, float] = {
	&"drift_tier_1": 660.0, &"drift_tier_2": 880.0, &"drift_tier_3": 1100.0,
	&"boost": 180.0, &"impact_wall": 70.0, &"impact_kart": 100.0,
	&"hit_spin": 340.0, &"hit_tumble": 130.0, &"hit_squash": 90.0,
	&"item_pickup": 740.0, &"roulette_tick": 480.0, &"roulette_stop": 990.0,
	&"jump": 520.0, &"landing": 80.0, &"countdown": 660.0, &"go": 1320.0,
	&"lap": 790.0, &"final_lap": 940.0, &"finish": 1180.0,
	&"position_up": 1040.0, &"position_down": 390.0,
	&"menu_move": 580.0, &"menu_accept": 870.0, &"menu_back": 290.0,
	&"threat_warning": 760.0,
}
const BGM_TEMPOS: Dictionary[StringName, float] = {
	&"menu": 108.0, &"race": 144.0, &"results": 120.0,
}
const BGM_TRANSPOSE: Dictionary[StringName, int] = {&"menu": 0, &"race": 7, &"results": 12}
## Per-track theme loops (Phase 18c): distinct 32-48s bass+lead compositions
## replacing the shared "race" loop so each track has its own musical identity.
const TRACK_THEMES: Dictionary[StringName, Dictionary] = {
	&"ridgeline_circuit": {"tempo": 150.0, "bars": 20, "roots": [50, 55, 57, 53], "register": 0, "style": &"pluck"},
	&"lumen_underpass": {"tempo": 96.0, "bars": 18, "roots": [46, 41, 44, 49], "register": -12, "style": &"pad"},
	&"glacier_crown": {"tempo": 132.0, "bars": 22, "roots": [59, 62, 57, 55], "register": 12, "style": &"arpeggio"},
	&"ochre_rift": {"tempo": 120.0, "bars": 20, "roots": [45, 50, 52, 48], "register": -5, "style": &"percussive"},
}
const PAD_ATTACK_RATIO: float = 0.6
const PAD_DETUNE_RATIO: float = 1.01
const PAD_DETUNE_GAIN: float = 0.35
const COLD_ENVELOPE_POWER: float = 3.0
const COLD_OVERTONE_GAIN: float = 0.3
const PERCUSSIVE_BASS_DECAY: float = 9.0
const ITEM_BASE_HZ: float = 240.0
const ITEM_STEP_HZ: float = 95.0
const HIT_PITCH_RATIO: float = 0.65
const ENGINE_NOISE_LOW_HZ: float = 40.0
const ENGINE_NOISE_HIGH_HZ: float = 700.0
const ENGINE_NOISE_GAIN: float = 0.008
const SQUEAL_NOISE_GAIN: float = 0.04
const ENGINE_SAW_GAIN: float = 0.18
const STINGER_SECONDS: float = 0.7
const BOOST_SECONDS: float = 0.45
const CLICK_SECONDS: float = 0.06
const LOW_SWEEP_THRESHOLD_HZ: float = 400.0
const NOISY_TONE_THRESHOLD_HZ: float = 180.0
const FALLING_SWEEP_START: float = 1.2
const FALLING_SWEEP_END: float = 0.5
const RISING_SWEEP_START: float = 0.8
const RISING_SWEEP_END: float = 1.3
const ALARM_PERIOD_SECONDS: float = 0.2
const ALARM_HALF_SECONDS: float = 0.1
const ALARM_HIGH_RATIO: float = 1.5
const NOISE_SMOOTHING: float = 0.3
const WHOOSH_NOISE_GAIN: float = 0.8
const THUD_NOISE_GAIN: float = 0.4
const TONE_GAIN: float = 0.4
const ENVELOPE_POWER: float = 2.0
const ARPEGGIO_GAIN: float = 0.22
const BASS_GAIN: float = 0.14
const ENGINE_VOLUME_DB: float = -12.0
const DEFAULT_VOLUME_DB: float = -6.0
const IMPACT_PITCH_VARIANCE: float = 0.025
const IMPORT_LOOP_FORWARD: int = 2
const IMPORT_LOOP_DISABLED: int = 1

var _failed: bool = false
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _sfx_ids: Array[StringName] = []


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)
	DirAccess.make_dir_recursive_absolute("res://data/audio")
	_rng.seed = NOISE_SEED
	_write_loop(&"engine", false)
	_write_loop(&"drift_squeal", true)
	for id: StringName in TONES:
		_write_tone(id, TONES[id])
	for index: int in range(ITEM_IDS.size()):
		var frequency: float = ITEM_BASE_HZ + float(index) * ITEM_STEP_HZ
		_write_tone(StringName("%s_fire" % ITEM_IDS[index]), frequency)
		_write_tone(StringName("%s_hit" % ITEM_IDS[index]), frequency * HIT_PITCH_RATIO)
	for id: StringName in BGM_TEMPOS:
		_write_bgm(id, BGM_TEMPOS[id])
	for id: StringName in TRACK_THEMES:
		_write_track_theme(id, TRACK_THEMES[id])
	_write_library("sfx_default", _sfx_ids)
	var bgm_ids: Array[StringName] = []
	bgm_ids.assign(BGM_TEMPOS.keys())
	bgm_ids.append_array(TRACK_THEMES.keys())
	_write_library("bgm_default", bgm_ids)
	print("Generated %d SFX and %d BGM loops (mono 22050 Hz PCM16)." % [_sfx_ids.size(), bgm_ids.size()])
	quit(1 if _failed else 0)


func _write_loop(id: StringName, squeal: bool) -> void:
	var count: int = int(LOOP_SECONDS * SAMPLE_RATE)
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(count)
	# Periodic random-phase harmonics band-limit the noise and match the seam.
	const PARTIALS: int = 48
	const ENGINE_HZ: float = 55.0
	const SQUEAL_LOW_HZ: float = 1500.0
	const SQUEAL_BAND_HZ: float = 1800.0
	const SAW_PARTIALS: int = 12
	for partial: int in range(PARTIALS):
		var frequency: float = roundf(_rng.randf_range(SQUEAL_LOW_HZ, SQUEAL_LOW_HZ + SQUEAL_BAND_HZ))
		if not squeal:
			frequency = roundf(_rng.randf_range(ENGINE_NOISE_LOW_HZ, ENGINE_NOISE_HIGH_HZ))
		var phase: float = _rng.randf_range(0.0, TAU)
		for index: int in range(count):
			var time: float = float(index) / SAMPLE_RATE
			samples[index] += sin(TAU * frequency * time + phase) * (SQUEAL_NOISE_GAIN if squeal else ENGINE_NOISE_GAIN)
	if not squeal:
		for harmonic: int in range(1, SAW_PARTIALS + 1):
			for index: int in range(count):
				var time: float = float(index) / SAMPLE_RATE
				samples[index] += sin(TAU * ENGINE_HZ * harmonic * time) * ENGINE_SAW_GAIN / harmonic
	_save_wav(id, samples, true)
	_sfx_ids.append(id)


func _write_tone(id: StringName, frequency: float) -> void:
	var duration: float = SHORT_SECONDS
	if id in [&"finish", &"final_lap", &"lap", &"threat_warning"]:
		duration = STINGER_SECONDS
	elif id == &"boost":
		duration = BOOST_SECONDS
	elif id in [&"menu_move", &"roulette_tick"]:
		duration = CLICK_SECONDS
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(int(duration * SAMPLE_RATE))
	var phase: float = 0.0
	var filtered_noise: float = 0.0
	for index: int in range(samples.size()):
		var time: float = float(index) / SAMPLE_RATE
		var progress: float = time / duration
		var sweep: float = lerpf(FALLING_SWEEP_START, FALLING_SWEEP_END, progress) if frequency < LOW_SWEEP_THRESHOLD_HZ else lerpf(RISING_SWEEP_START, RISING_SWEEP_END, progress)
		if id == &"threat_warning":
			sweep = 1.0 if fmod(time, ALARM_PERIOD_SECONDS) < ALARM_HALF_SECONDS else ALARM_HIGH_RATIO
		phase += TAU * frequency * sweep / SAMPLE_RATE
		filtered_noise = lerpf(filtered_noise, _rng.randf_range(-1.0, 1.0), NOISE_SMOOTHING)
		var noise_gain: float = WHOOSH_NOISE_GAIN if id == &"boost" else (THUD_NOISE_GAIN if frequency < NOISY_TONE_THRESHOLD_HZ else 0.0)
		var envelope: float = minf(1.0, time / EDGE_SECONDS) * pow(1.0 - progress, ENVELOPE_POWER)
		samples[index] = (sin(phase) * TONE_GAIN + filtered_noise * noise_gain) * envelope
	_save_wav(id, samples, false)
	_sfx_ids.append(id)


func _write_bgm(id: StringName, tempo: float) -> void:
	var beat_seconds: float = SECONDS_PER_MINUTE / tempo
	var note_seconds: float = beat_seconds / NOTES_PER_BEAT
	var count: int = int(round(BARS * BEATS_PER_BAR * beat_seconds * SAMPLE_RATE))
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(count)
	for index: int in range(count):
		var time: float = float(index) / SAMPLE_RATE
		var note: int = int(time / note_seconds)
		var bar: int = note / (BEATS_PER_BAR * NOTES_PER_BEAT)
		var root_note: int = ROOTS[bar % ROOTS.size()] + BGM_TRANSPOSE[id]
		var note_time: float = fmod(time, note_seconds)
		var frequency: float = A4_HZ * pow(2.0, (root_note + ARPEGGIO[note % ARPEGGIO.size()] - A4_MIDI) / SEMITONES)
		var envelope: float = minf(1.0, note_time / EDGE_SECONDS) * pow(1.0 - note_time / note_seconds, ENVELOPE_POWER)
		var bass_hz: float = A4_HZ * pow(2.0, (root_note - SEMITONES - A4_MIDI) / SEMITONES)
		var beat_time: float = fmod(time, beat_seconds)
		var bass_envelope: float = sin(PI * beat_time / beat_seconds)
		var edge: float = minf(1.0, minf(time, float(count - 1 - index) / SAMPLE_RATE) / EDGE_SECONDS)
		samples[index] = (sin(TAU * frequency * note_time) * envelope * ARPEGGIO_GAIN + sin(TAU * bass_hz * beat_time) * bass_envelope * BASS_GAIN) * edge
	_save_wav(id, samples, true)


## Renders a track theme's bass+lead loop from its tuning dictionary; pure
## (no file I/O) so both generation and tests can call it deterministically.
func _render_track_theme(theme: Dictionary) -> PackedFloat32Array:
	var tempo: float = theme["tempo"]
	var bars: int = theme["bars"]
	var roots: Array = theme["roots"]
	var register: int = theme["register"]
	var style: StringName = theme["style"]
	var beat_seconds: float = SECONDS_PER_MINUTE / tempo
	var note_seconds: float = beat_seconds / NOTES_PER_BEAT
	var count: int = int(round(bars * BEATS_PER_BAR * beat_seconds * SAMPLE_RATE))
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(count)
	for index: int in range(count):
		var time: float = float(index) / SAMPLE_RATE
		var note: int = int(time / note_seconds)
		var bar: int = note / (BEATS_PER_BAR * NOTES_PER_BEAT)
		var root_note: int = int(roots[bar % roots.size()]) + register
		var note_time: float = fmod(time, note_seconds)
		var beat_time: float = fmod(time, beat_seconds)
		var bass_hz: float = A4_HZ * pow(2.0, float(root_note - SEMITONES - A4_MIDI) / SEMITONES)
		var edge: float = minf(1.0, minf(time, float(count - 1 - index) / SAMPLE_RATE) / EDGE_SECONDS)
		var lead: float = _track_lead_sample(style, root_note, note, note_time, note_seconds)
		var bass: float = _track_bass_sample(style, bass_hz, beat_time, beat_seconds)
		samples[index] = (lead * ARPEGGIO_GAIN + bass * BASS_GAIN) * edge
	return samples


## Lead layer, shaped per theme: plucky arpeggio (default), sustained
## detuned pad (Lumen), thin bell-like overtone (Glacier), matches the
## default pluck for Ochre (its identity comes from the percussive bass).
func _track_lead_sample(style: StringName, root_note: int, note: int, note_time: float, note_seconds: float) -> float:
	var semitone: int = ARPEGGIO[note % ARPEGGIO.size()]
	var frequency: float = A4_HZ * pow(2.0, float(root_note + semitone - A4_MIDI) / SEMITONES)
	match style:
		&"pad":
			var envelope: float = minf(1.0, note_time / (note_seconds * PAD_ATTACK_RATIO))
			var detune: float = sin(TAU * frequency * PAD_DETUNE_RATIO * note_time) * PAD_DETUNE_GAIN
			return (sin(TAU * frequency * note_time) + detune) * envelope
		&"arpeggio":
			var envelope: float = minf(1.0, note_time / EDGE_SECONDS) * pow(1.0 - note_time / note_seconds, COLD_ENVELOPE_POWER)
			var overtone: float = sin(TAU * frequency * 2.0 * note_time) * COLD_OVERTONE_GAIN
			return (sin(TAU * frequency * note_time) + overtone) * envelope
		_:
			var envelope: float = minf(1.0, note_time / EDGE_SECONDS) * pow(1.0 - note_time / note_seconds, ENVELOPE_POWER)
			return sin(TAU * frequency * note_time) * envelope


## Bass layer, shaped per theme: smooth beat pulse (default), sustained pad
## bass (Lumen), sharp decaying thump for the Ochre desert-percussion feel.
func _track_bass_sample(style: StringName, bass_hz: float, beat_time: float, beat_seconds: float) -> float:
	match style:
		&"percussive":
			return sin(TAU * bass_hz * beat_time) * exp(-beat_time * PERCUSSIVE_BASS_DECAY)
		&"pad":
			return sin(TAU * bass_hz * beat_time)
		_:
			return sin(TAU * bass_hz * beat_time) * sin(PI * beat_time / beat_seconds)


func _write_track_theme(id: StringName, theme: Dictionary) -> void:
	_save_wav(id, _render_track_theme(theme), true)


func _save_wav(id: StringName, samples: PackedFloat32Array, looped: bool) -> void:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(samples.size() * BYTES_PER_SAMPLE)
	for index: int in range(samples.size()):
		bytes.encode_s16(index * BYTES_PER_SAMPLE, int(clampf(samples[index], -1.0, 1.0) * PCM_PEAK))
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = bytes
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD if looped else AudioStreamWAV.LOOP_DISABLED
	stream.loop_end = samples.size()
	var path: String = OUTPUT_DIR + String(id) + ".wav"
	if stream.save_to_wav(path) != OK:
		push_error("Cannot generate audio: " + path)
		_failed = true
	# Explicit import settings survive editor reimports and retain PCM16 loops.
	var config: ConfigFile = ConfigFile.new()
	if FileAccess.file_exists(path + ".import"):
		config.load(path + ".import")
	config.set_value("remap", "importer", "wav")
	config.set_value("remap", "type", "AudioStreamWAV")
	config.set_value("params", "edit/loop_mode", IMPORT_LOOP_FORWARD if looped else IMPORT_LOOP_DISABLED)
	config.set_value("params", "edit/loop_begin", 0)
	config.set_value("params", "edit/loop_end", samples.size())
	config.set_value("params", "compress/mode", 0)
	config.set_value("params", "edit/trim", false)
	config.set_value("params", "edit/normalize", false)
	config.save(path + ".import")


func _write_library(file_name: String, ids: Array[StringName]) -> void:
	var lookup_ids: Array[StringName] = ids.duplicate()
	for alias_id: StringName in AUDIO_ALIASES:
		if ids.has(AUDIO_ALIASES[alias_id]):
			lookup_ids.append(alias_id)
	var text: String = '[gd_resource type="Resource" script_class="SfxLibrary" load_steps=%d format=3]\n\n' % (ids.size() + 2)
	text += '[ext_resource type="Script" path="res://data/schemas/sfx_library.gd" id="1"]\n'
	for index: int in range(ids.size()):
		text += '[ext_resource type="AudioStream" path="%s%s.wav" id="%d"]\n' % [OUTPUT_DIR, ids[index], index + 2]
	text += '\n[resource]\nscript = ExtResource("1")\nstreams = Dictionary[StringName, AudioStream]({\n'
	for index: int in range(lookup_ids.size()):
		var source_id: StringName = AUDIO_ALIASES.get(lookup_ids[index], lookup_ids[index])
		text += '&"%s": ExtResource("%d")%s\n' % [lookup_ids[index], ids.find(source_id) + 2, ',' if index < lookup_ids.size() - 1 else '']
	text += '})\nvolume_db = Dictionary[StringName, float]({\n'
	for index: int in range(ids.size()):
		var gain: float = ENGINE_VOLUME_DB if ids[index] == &"engine" else DEFAULT_VOLUME_DB
		text += '&"%s": %s%s\n' % [ids[index], gain, ',' if index < ids.size() - 1 else '']
	text += '})\npitch_variance = Dictionary[StringName, float]({\n'
	for index: int in range(ids.size()):
		var variance: float = IMPACT_PITCH_VARIANCE if String(ids[index]).begins_with("impact_") else 0.0
		text += '&"%s": %s%s\n' % [ids[index], variance, ',' if index < ids.size() - 1 else '']
	text += '})\n'
	var file: FileAccess = FileAccess.open("res://data/audio/" + file_name + ".tres", FileAccess.WRITE)
	file.store_string(text)
