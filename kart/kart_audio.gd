class_name KartAudio
extends Node

## Filters EventBus feedback for one kart; never writes gameplay or physics state.

const ENGINE_MIN_PITCH: float = 0.7
const ENGINE_MAX_PITCH: float = 2.1
const SQUEAL_THRESHOLD: float = 0.02
const IMPACT_COOLDOWN: float = 0.15
const HIT_IDS: Array[StringName] = [&"impact_kart", &"hit_spin", &"hit_tumble", &"hit_squash"]
const TIER_IDS: Array[StringName] = [&"drift_tier_1", &"drift_tier_2", &"drift_tier_3"]
const SECONDARY_PLAYER_GAIN: float = 0.45

@export var player_audio: bool = false

var _kart: KartController
var _engine: AudioVoice
var _squeal: AudioVoice
var _impact_remaining: float = 0.0
var _local_player_gain: float = 1.0
var _controls_engine_filter: bool = false


func _ready() -> void:
	# Children ready before KartController's @onready fields, so binding is deferred.
	_bind.call_deferred()


func _exit_tree() -> void:
	if is_instance_valid(_kart) and AudioManager.pool != null:
		AudioManager.pool.release_owner(_kart.get_instance_id())
	if player_audio:
		AudioManager.set_engine_offroad(false)


func _process(delta: float) -> void:
	if not is_instance_valid(_kart):
		return # Deferred binding has not completed yet.
	_impact_remaining = maxf(0.0, _impact_remaining - delta)
	_engine = _loop(_engine, &"engine", AudioManagerService.PRIORITY_ENGINE, &"Engine")
	if _owns(_engine, &"engine"):
		_engine.update(_local_player_gain, engine_pitch(_kart.get_engine_pitch_ratio(), _kart.is_boosting()), _kart.global_position)
	var squeal: float = _kart.get_drift_squeal_ratio() if _kart.is_grounded() else 0.0
	if squeal > SQUEAL_THRESHOLD:
		_squeal = _loop(_squeal, &"drift_squeal", AudioManagerService.PRIORITY_SQUEAL, &"SFX")
		if _owns(_squeal, &"drift_squeal"):
			_squeal.update(squeal * _local_player_gain, 1.0, _kart.global_position)
	elif _owns(_squeal, &"drift_squeal"):
		_squeal.stop()
	if _controls_engine_filter:
		AudioManager.set_engine_offroad(_kart.get_terrain_id() != &"asphalt")


## Selects non-positional playback for the local player, including injected providers.
func set_player_audio(enabled: bool) -> void:
	set_local_player_mix(1.0 if enabled else 0.0, enabled)


## Uses flat audio for a local human and attenuates non-primary engines.
func set_local_player_mix(gain: float, controls_engine_filter: bool) -> void:
	var enabled: bool = gain > 0.0
	if enabled == player_audio:
		_local_player_gain = clampf(gain, 0.0, 1.0) if enabled else 1.0
		_controls_engine_filter = controls_engine_filter and enabled
		return
	if is_instance_valid(_kart):
		AudioManager.pool.release_owner(_kart.get_instance_id())
	if _controls_engine_filter:
		AudioManager.set_engine_offroad(false)
	player_audio = enabled
	_local_player_gain = clampf(gain, 0.0, 1.0) if enabled else 1.0
	_controls_engine_filter = controls_engine_filter and enabled
	_engine = null
	_squeal = null


## Maps the existing Phase 8 ratio (which already includes boost) exactly once.
static func engine_pitch(engine_ratio: float, boosting: bool) -> float:
	var boost_add: float = KartController.ENGINE_BOOST_PITCH_ADD if boosting else 0.0
	var speed_ratio: float = clampf(engine_ratio - boost_add, 0.0, 1.0)
	return lerpf(ENGINE_MIN_PITCH, ENGINE_MAX_PITCH, speed_ratio) + boost_add


func _bind() -> void:
	_kart = get_parent() as KartController
	if _kart == null:
		push_error("KartAudio requires a KartController parent")
		return
	EventBus.drift_tier_changed.connect(_on_tier)
	EventBus.kart_hopped.connect(_on_jump)
	EventBus.boost_started.connect(_on_boost)
	EventBus.kart_launched.connect(_on_jump)
	EventBus.kart_contacted.connect(_on_contact)
	EventBus.wall_impacted.connect(_on_wall)
	EventBus.kart_landed.connect(_on_landed)
	EventBus.kart_hit.connect(_on_hit)
	EventBus.roulette_started.connect(_on_pickup)
	EventBus.roulette_ticked.connect(_on_roulette_tick)
	EventBus.roulette_stopped.connect(_on_roulette_stop)


func _loop(voice: AudioVoice, id: StringName, priority: int, bus: StringName) -> AudioVoice:
	if _owns(voice, id):
		return voice
	return AudioManager.play_kart_sfx(id, _kart, player_audio, priority, 1.0, true, bus)


func _owns(voice: AudioVoice, id: StringName) -> bool:
	return voice != null and voice.active and voice.owner_id == _kart.get_instance_id() and voice.sound_id == id


func _play(id: StringName) -> void:
	AudioManager.play_kart_sfx(id, _kart, player_audio)


func _on_tier(kart: Node, tier: int) -> void:
	if kart == _kart and tier > 0 and tier <= TIER_IDS.size():
		_play(TIER_IDS[tier - 1])


func _on_boost(kart: Node, _spec: Resource) -> void:
	if kart == _kart:
		_play(&"boost")


func _on_jump(kart: Node) -> void:
	if kart == _kart:
		_play(&"jump")


func _on_contact(kart: Node) -> void:
	if kart == _kart:
		_impact(&"impact_kart")


func _on_wall(kart: Node) -> void:
	if kart == _kart:
		_impact(&"impact_wall")


func _impact(id: StringName) -> void:
	if _impact_remaining > 0.0:
		return # Sustained contacts are rate-limited presentation, not physics changes.
	_impact_remaining = IMPACT_COOLDOWN
	_play(id)


func _on_landed(kart: Node, _vertical_speed: float) -> void:
	if kart == _kart:
		_play(&"landing")


func _on_hit(kart: Node, type: int) -> void:
	if kart == _kart and type >= 0 and type < HIT_IDS.size():
		_play(HIT_IDS[type])


func _on_pickup(kart: Node) -> void:
	if kart == _kart:
		_play(&"item_pickup")


func _on_roulette_tick(kart: Node) -> void:
	if kart == _kart and player_audio:
		_play(&"roulette_tick")


func _on_roulette_stop(kart: Node) -> void:
	if kart == _kart and player_audio:
		_play(&"roulette_stop")
