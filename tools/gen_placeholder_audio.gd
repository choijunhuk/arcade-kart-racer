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
const ITEM_BASE_HZ: float = 240.0
const ITEM_STEP_HZ: float = 95.0
const HIT_PITCH_RATIO: float = 0.65

var _failed: bool = false
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _sfx_ids: Array[StringName] = []
var _loop_ids: Array[StringName] = [&"engine", &"drift_squeal"]


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
	_write_library("sfx_default", _sfx_ids)
	var bgm_ids: Array[StringName] = []
	bgm_ids.assign(BGM_TEMPOS.keys())
	_write_library("bgm_default", bgm_ids)
	print("Generated %d SFX and %d eight-bar BGM loops (mono 22050 Hz PCM16)." % [_sfx_ids.size(), bgm_ids.size()])
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
			frequency = roundf(_rng.randf_range(40.0, 700.0))
		var phase: float = _rng.randf_range(0.0, TAU)
		for index: int in range(count):
			var time: float = float(index) / SAMPLE_RATE
			samples[index] += sin(TAU * frequency * time + phase) * (0.04 if squeal else 0.008)
	if not squeal:
		for harmonic: int in range(1, SAW_PARTIALS + 1):
			for index: int in range(count):
				var time: float = float(index) / SAMPLE_RATE
				samples[index] += sin(TAU * ENGINE_HZ * harmonic * time) * 0.18 / harmonic
	_save_wav(id, samples, true)
	_sfx_ids.append(id)


func _write_tone(id: StringName, frequency: float) -> void:
	var duration: float = SHORT_SECONDS
	if id in [&"finish", &"final_lap", &"lap", &"threat_warning"]:
		duration = 0.7
	elif id == &"boost":
		duration = 0.45
	elif id in [&"menu_move", &"roulette_tick"]:
		duration = 0.06
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(int(duration * SAMPLE_RATE))
	var phase: float = 0.0
	var filtered_noise: float = 0.0
	for index: int in range(samples.size()):
		var time: float = float(index) / SAMPLE_RATE
		var progress: float = time / duration
		var sweep: float = lerpf(1.2, 0.5, progress) if frequency < 400.0 else lerpf(0.8, 1.3, progress)
		if id == &"threat_warning":
			sweep = 1.0 if fmod(time, 0.2) < 0.1 else 1.5
		phase += TAU * frequency * sweep / SAMPLE_RATE
		filtered_noise = lerpf(filtered_noise, _rng.randf_range(-1.0, 1.0), 0.3)
		var noise_gain: float = 0.8 if id == &"boost" else (0.4 if frequency < 180.0 else 0.0)
		var envelope: float = minf(1.0, time / EDGE_SECONDS) * pow(1.0 - progress, 2.0)
		samples[index] = (sin(phase) * 0.4 + filtered_noise * noise_gain) * envelope
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
		var envelope: float = minf(1.0, note_time / EDGE_SECONDS) * pow(1.0 - note_time / note_seconds, 2.0)
		var bass_hz: float = A4_HZ * pow(2.0, (root_note - SEMITONES - A4_MIDI) / SEMITONES)
		var beat_time: float = fmod(time, beat_seconds)
		var bass_envelope: float = sin(PI * beat_time / beat_seconds)
		var edge: float = minf(1.0, minf(time, float(count - 1 - index) / SAMPLE_RATE) / EDGE_SECONDS)
		samples[index] = (sin(TAU * frequency * note_time) * envelope * 0.22 + sin(TAU * bass_hz * beat_time) * bass_envelope * 0.14) * edge
	_save_wav(id, samples, true)
	_loop_ids.append(id)


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
	config.set_value("params", "edit/loop_mode", 2 if looped else 1)
	config.set_value("params", "edit/loop_begin", 0)
	config.set_value("params", "edit/loop_end", samples.size())
	config.set_value("params", "compress/mode", 0)
	config.set_value("params", "edit/trim", false)
	config.set_value("params", "edit/normalize", false)
	config.save(path + ".import")


func _write_library(file_name: String, ids: Array[StringName]) -> void:
	var text: String = '[gd_resource type="Resource" script_class="SfxLibrary" load_steps=%d format=3]\n\n' % (ids.size() + 2)
	text += '[ext_resource type="Script" path="res://data/schemas/sfx_library.gd" id="1"]\n'
	for index: int in range(ids.size()):
		text += '[ext_resource type="AudioStream" path="%s%s.wav" id="%d"]\n' % [OUTPUT_DIR, ids[index], index + 2]
	text += '\n[resource]\nscript = ExtResource("1")\nstreams = Dictionary[StringName, AudioStream]({\n'
	for index: int in range(ids.size()):
		text += '&"%s": ExtResource("%d")%s\n' % [ids[index], index + 2, ',' if index < ids.size() - 1 else '']
	text += '})\nvolume_db = Dictionary[StringName, float]({\n'
	for index: int in range(ids.size()):
		var gain: float = -12.0 if ids[index] == &"engine" else -6.0
		text += '&"%s": %s%s\n' % [ids[index], gain, ',' if index < ids.size() - 1 else '']
	text += '})\npitch_variance = Dictionary[StringName, float]({\n'
	for index: int in range(ids.size()):
		var variance: float = 0.025 if String(ids[index]).begins_with("impact_") else 0.0
		text += '&"%s": %s%s\n' % [ids[index], variance, ',' if index < ids.size() - 1 else '']
	text += '})\n'
	var file: FileAccess = FileAccess.open("res://data/audio/" + file_name + ".tres", FileAccess.WRITE)
	file.store_string(text)
