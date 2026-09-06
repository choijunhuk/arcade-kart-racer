class_name AudioManagerService
extends Node

const MASTER_BUS: StringName = &"Master"
const MUSIC_BUS: StringName = &"Music"
const SFX_BUS: StringName = &"SFX"
const ENGINE_BUS: StringName = &"Engine"
const DEFAULT_POOL_SIZE: int = 16
const MIN_LINEAR_VOLUME: float = 0.0
const MAX_LINEAR_VOLUME: float = 1.0
const SILENCE_DB: float = -80.0

var _sfx_players: Array[AudioStreamPlayer3D] = []


func _ready() -> void:
	ensure_audio_buses()
	prepare_sfx_pool()


## Creates the required audio bus hierarchy without duplicating existing buses.
func ensure_audio_buses() -> void:
	for bus_name: StringName in [MUSIC_BUS, SFX_BUS, ENGINE_BUS]:
		if AudioServer.get_bus_index(bus_name) >= 0:
			continue
		AudioServer.add_bus()
		var bus_index: int = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus_index, bus_name)
		AudioServer.set_bus_send(bus_index, MASTER_BUS)


## Sets a named bus volume from a clamped linear 0–1 value.
func set_bus_volume(bus_name: StringName, linear_volume: float) -> void:
	var bus_index: int = AudioServer.get_bus_index(bus_name)
	if bus_index < 0:
		push_error("Unknown audio bus: %s" % String(bus_name))
		return
	var clamped: float = clampf(linear_volume, MIN_LINEAR_VOLUME, MAX_LINEAR_VOLUME)
	AudioServer.set_bus_mute(bus_index, is_zero_approx(clamped))
	AudioServer.set_bus_volume_db(bus_index, SILENCE_DB if is_zero_approx(clamped) else linear_to_db(clamped))


## Returns a named bus volume as a linear 0–1 value.
func get_bus_volume(bus_name: StringName) -> float:
	var bus_index: int = AudioServer.get_bus_index(bus_name)
	if bus_index < 0:
		push_error("Unknown audio bus: %s" % String(bus_name))
		return MIN_LINEAR_VOLUME
	if AudioServer.is_bus_mute(bus_index):
		return MIN_LINEAR_VOLUME
	return clampf(db_to_linear(AudioServer.get_bus_volume_db(bus_index)), MIN_LINEAR_VOLUME, MAX_LINEAR_VOLUME)


## Ensures the reusable positional SFX player pool contains the requested size.
func prepare_sfx_pool(pool_size: int = DEFAULT_POOL_SIZE) -> void:
	while _sfx_players.size() < pool_size:
		var player: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
		player.bus = String(SFX_BUS)
		add_child(player)
		_sfx_players.append(player)


## Plays a positional sound using the first idle pooled player.
func play_sfx(stream: AudioStream, world_position: Vector3 = Vector3.ZERO) -> AudioStreamPlayer3D:
	if stream == null:
		push_warning("Cannot play a null SFX stream.")
		return null
	var player: AudioStreamPlayer3D = _find_available_player()
	player.stream = stream
	player.global_position = world_position
	player.play()
	return player


func _find_available_player() -> AudioStreamPlayer3D:
	for player: AudioStreamPlayer3D in _sfx_players:
		if not player.playing:
			return player
	return _sfx_players[0]
