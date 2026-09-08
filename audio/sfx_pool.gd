class_name SfxPool
extends Node

## Fixed capacity, priority/oldest-first stealing, including kart loops and music.

const SPATIAL_CAPACITY: int = 16
const FLAT_CAPACITY: int = 8
const MUSIC_VOICES: int = 2
const KART_VOICE_LIMIT: int = 3
const MAX_DISTANCE: float = 80.0
const UNIT_SIZE: float = 12.0

var voices: Array[AudioVoice] = []
var _sequence: int = 0


## Allocates all player nodes once. Repeated preparation is a no-op.
func prepare() -> void:
	if not voices.is_empty():
		return
	for index: int in range(SPATIAL_CAPACITY + FLAT_CAPACITY):
		var voice: AudioVoice = AudioVoice.new()
		if index < SPATIAL_CAPACITY:
			voice.spatial = AudioStreamPlayer3D.new()
			voice.spatial.max_distance = MAX_DISTANCE
			voice.spatial.unit_size = UNIT_SIZE
			add_child(voice.spatial)
		else:
			voice.flat = AudioStreamPlayer.new()
			add_child(voice.flat)
		voice.reserved = index >= SPATIAL_CAPACITY and index < SPATIAL_CAPACITY + MUSIC_VOICES
		voice.pauses_with_world = not voice.reserved
		voices.append(voice)


## Acquires an idle slot or steals only an equal/lower-priority eligible lease.
func acquire(spatial: bool, priority: int, owner_id: int = 0, allow_equal_priority: bool = true) -> AudioVoice:
	var owner_at_limit: bool = owner_id != 0 and count_owner(owner_id) >= KART_VOICE_LIMIT
	var candidate: AudioVoice
	for voice: AudioVoice in voices:
		if voice.reserved or (voice.spatial != null) != spatial:
			continue
		if owner_at_limit and (not voice.active or voice.owner_id != owner_id):
			continue
		if not voice.active:
			candidate = voice
			break
		if voice.priority > priority or (not allow_equal_priority and voice.priority == priority):
			continue
		if candidate == null or voice.priority < candidate.priority or (voice.priority == candidate.priority and voice.sequence < candidate.sequence):
			candidate = voice
	if candidate == null:
		return null # Saturation deliberately drops lower-priority requests.
	candidate.stop()
	_sequence += 1
	candidate.sequence = _sequence
	candidate.owner_id = owner_id
	candidate.priority = priority
	return candidate


## Counts live leases for a kart, including loops and transient item audio.
func count_owner(owner_id: int) -> int:
	var count: int = 0
	for voice: AudioVoice in voices:
		if voice.active and voice.owner_id == owner_id and not voice.reserved:
			count += 1
	return count


## Counts active voices of one dimension, including the two reserved BGM slots.
func count_active(spatial: bool) -> int:
	var count: int = 0
	for voice: AudioVoice in voices:
		if voice.active and (voice.spatial != null) == spatial:
			count += 1
	return count


## Advances lifetime/pause state for every preallocated voice.
func step(delta: float, paused: bool) -> void:
	for voice: AudioVoice in voices:
		voice.step(delta, paused)


## Releases all leases belonging to a kart before its node leaves the tree.
func release_owner(owner_id: int) -> void:
	for voice: AudioVoice in voices:
		if voice.owner_id == owner_id and not voice.reserved:
			voice.stop()


## Clears world SFX at scene boundaries while preserving music crossfades.
func stop_sfx() -> void:
	for voice: AudioVoice in voices:
		if not voice.reserved:
			voice.stop()
