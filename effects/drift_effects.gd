class_name DriftEffects
extends Node3D

@export var tuning: FeelTuning = preload("res://data/tuning/feel_default.tres")

@onready var _kart: KartController = get_parent() as KartController
@onready var _sparks: Array[GPUParticles3D] = [$SparkLeft, $SparkRight]
@onready var _smoke: Array[GPUParticles3D] = [$SmokeLeft, $SmokeRight]

var _cached_terrain_id: StringName = &""
var _cached_terrain_color: Color = Color(0.65, 0.65, 0.65, 0.7)
var _lod_enabled: bool = true


func _ready() -> void:
	var controller: DriftController = _kart.get_node("DriftController") as DriftController
	controller.drift_started.connect(_on_drift_started)
	controller.drift_tier_changed.connect(_on_tier_changed)
	controller.drift_ended.connect(_on_drift_ended)


func _process(_delta: float) -> void:
	var drifting: bool = _kart.get_drift_state() == DriftController.DriftState.HOLD
	var active: bool = should_emit_smoke(
		drifting, _kart.get_terrain_id(), _kart.get_brake_input(),
		_kart.get_speed_ratio(), tuning.smoke_brake_threshold,
		tuning.smoke_min_speed_ratio,
	)
	for particles: GPUParticles3D in _smoke:
		particles.emitting = active and _lod_enabled
	for particles: GPUParticles3D in _sparks:
		particles.emitting = drifting and _lod_enabled
	if active:
		_set_smoke_color(_terrain_particle_color())


## Pure smoke rule covering drift, off-road travel, and hard braking.
static func should_emit_smoke(
	drifting: bool, terrain_id: StringName, brake: float, speed_ratio: float,
	brake_threshold: float, minimum_speed_ratio: float,
) -> bool:
	if drifting:
		return true
	if speed_ratio < minimum_speed_ratio:
		return false
	return terrain_id != &"asphalt" or brake >= brake_threshold


func _on_drift_started(_direction: int) -> void:
	for particles: GPUParticles3D in _sparks:
		particles.emitting = _lod_enabled


func _on_tier_changed(tier: int) -> void:
	var color: Color = _tier_color(tier)
	for particles: GPUParticles3D in _sparks:
		_set_particle_color(particles, color)
		particles.restart()


func _on_drift_ended(_released_tier: int) -> void:
	for particles: GPUParticles3D in _sparks:
		particles.emitting = false


## Enables or disables every kart-local emitter for camera-distance LOD.
func set_lod_enabled(enabled: bool) -> void:
	_lod_enabled = enabled
	if not enabled:
		for particles: GPUParticles3D in _sparks:
			particles.emitting = false
		for particles: GPUParticles3D in _smoke:
			particles.emitting = false


## Applies the user-selected visual density without restarting emitters.
func set_quality_ratio(ratio: float) -> void:
	for particles: GPUParticles3D in _sparks:
		particles.amount_ratio = clampf(ratio, 0.0, 1.0)
	for particles: GPUParticles3D in _smoke:
		particles.amount_ratio = clampf(ratio, 0.0, 1.0)


func _tier_color(tier: int) -> Color:
	match tier:
		2:
			return tuning.drift_tier_amber
		3:
			return tuning.drift_tier_magenta
		_:
			return tuning.drift_tier_cyan


func _terrain_particle_color() -> Color:
	var terrain_id: StringName = _kart.get_terrain_id()
	if terrain_id == _cached_terrain_id:
		return _cached_terrain_color
	_cached_terrain_id = terrain_id
	var path: String = "res://data/terrain/%s.tres" % String(terrain_id)
	if ResourceLoader.exists(path):
		_cached_terrain_color = (load(path) as TerrainData).particle_color
	else:
		_cached_terrain_color = Color(0.65, 0.65, 0.65, 0.7)
	return _cached_terrain_color


func _set_smoke_color(color: Color) -> void:
	for particles: GPUParticles3D in _smoke:
		_set_particle_color(particles, color)


func _set_particle_color(particles: GPUParticles3D, color: Color) -> void:
	var material: ParticleProcessMaterial = particles.process_material as ParticleProcessMaterial
	if material != null:
		material.color = color
