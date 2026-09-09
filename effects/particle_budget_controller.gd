class_name ParticleBudgetController
extends Node

## Validates GPU emitter counts once and applies camera-distance LOD per frame.

class Registration extends RefCounted:
	var kart: KartController
	var drift_effects: DriftEffects
	var boost_effects: BoostEffects
	var visuals: KartVisuals

const LOW_QUALITY_RATIO: float = 0.35
const MEDIUM_QUALITY_RATIO: float = 0.65
const HIGH_QUALITY_RATIO: float = 1.0

@export var tuning: FeelTuning = preload("res://data/tuning/feel_default.tres")

var _camera: Camera3D
var _registrations: Array[Registration] = []


func _ready() -> void:
	if not SettingsManager.settings_changed.is_connected(_on_settings_changed):
		SettingsManager.settings_changed.connect(_on_settings_changed)


func _exit_tree() -> void:
	if SettingsManager.settings_changed.is_connected(_on_settings_changed):
		SettingsManager.settings_changed.disconnect(_on_settings_changed)


## Caches kart/effect references, validates hard caps, and starts LOD updates.
func configure(karts: Array[KartController], camera: Camera3D) -> void:
	_camera = camera
	_registrations.clear()
	var counts: PackedInt32Array = PackedInt32Array()
	for kart: KartController in karts:
		var registration: Registration = Registration.new()
		registration.kart = kart
		registration.visuals = kart.get_node("Visuals") as KartVisuals
		registration.drift_effects = kart.get_node_or_null("DriftEffects") as DriftEffects
		registration.boost_effects = kart.get_node_or_null("BoostEffects") as BoostEffects
		_registrations.append(registration)
		counts.append(ParticleBudget.count_gpu_particles(kart))
	if not ParticleBudget.counts_fit(
		counts, tuning.particle_nodes_per_kart, tuning.total_gpu_particle_nodes,
	):
		push_error("GPUParticles3D budget exceeded: counts=%s" % str(counts))
	_apply_particle_quality()


func _process(_delta: float) -> void:
	if _camera == null:
		return
	for registration: Registration in _registrations:
		if not is_instance_valid(registration.kart):
			continue
		registration.visuals.set_detail_tier(QualityTier.lod(_camera.global_position.distance_to(registration.kart.global_position)))
		var enabled: bool = ParticleBudget.within_lod_distance(
			_camera.global_position, registration.kart.global_position,
			tuning.particle_lod_distance,
		)
		if registration.drift_effects != null:
			registration.drift_effects.set_lod_enabled(enabled)
		if registration.boost_effects != null:
			registration.boost_effects.set_lod_enabled(enabled)


## Maps the three UI quality steps to presentation density ratios.
static func quality_ratio(quality: int) -> float:
	match clampi(quality, 0, 2):
		0:
			return LOW_QUALITY_RATIO
		1:
			return MEDIUM_QUALITY_RATIO
		_:
			return HIGH_QUALITY_RATIO


func _on_settings_changed(section: StringName) -> void:
	if section == &"video":
		_apply_particle_quality()


func _apply_particle_quality() -> void:
	var quality: int = int(SettingsManager.get_setting(&"video", &"particle_quality", 2))
	var ratio: float = quality_ratio(quality)
	for registration: Registration in _registrations:
		if registration.drift_effects != null:
			registration.drift_effects.set_quality_ratio(ratio)
		if registration.boost_effects != null:
			registration.boost_effects.set_quality_ratio(ratio)
