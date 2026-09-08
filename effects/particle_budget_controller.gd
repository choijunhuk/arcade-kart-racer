class_name ParticleBudgetController
extends Node

## Validates GPU emitter counts once and applies camera-distance LOD per frame.

class Registration extends RefCounted:
	var kart: KartController
	var drift_effects: DriftEffects
	var boost_effects: BoostEffects

@export var tuning: FeelTuning = preload("res://data/tuning/feel_default.tres")

var _camera: Camera3D
var _registrations: Array[Registration] = []


## Caches kart/effect references, validates hard caps, and starts LOD updates.
func configure(karts: Array[KartController], camera: Camera3D) -> void:
	_camera = camera
	_registrations.clear()
	var counts: PackedInt32Array = PackedInt32Array()
	for kart: KartController in karts:
		var registration: Registration = Registration.new()
		registration.kart = kart
		registration.drift_effects = kart.get_node_or_null("DriftEffects") as DriftEffects
		registration.boost_effects = kart.get_node_or_null("BoostEffects") as BoostEffects
		_registrations.append(registration)
		counts.append(ParticleBudget.count_gpu_particles(kart))
	if not ParticleBudget.counts_fit(
		counts, tuning.particle_nodes_per_kart, tuning.total_gpu_particle_nodes,
	):
		push_error("GPUParticles3D budget exceeded: counts=%s" % str(counts))


func _process(_delta: float) -> void:
	if _camera == null:
		return
	for registration: Registration in _registrations:
		if not is_instance_valid(registration.kart):
			continue
		var enabled: bool = ParticleBudget.within_lod_distance(
			_camera.global_position, registration.kart.global_position,
			tuning.particle_lod_distance,
		)
		if registration.drift_effects != null:
			registration.drift_effects.set_lod_enabled(enabled)
		if registration.boost_effects != null:
			registration.boost_effects.set_lod_enabled(enabled)
