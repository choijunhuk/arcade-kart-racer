class_name DriftEffects
extends Node3D

@export var tuning: FeelTuning = preload("res://data/tuning/feel_default.tres")

@onready var _kart: KartController = get_parent() as KartController
@onready var _sparks: Array[GPUParticles3D] = [$SparkLeft, $SparkRight]
@onready var _smoke: Array[GPUParticles3D] = [$SmokeLeft, $SmokeRight]

var _cached_terrain_id: StringName = &""
var _cached_terrain_color: Color = Color(0.65, 0.65, 0.65, 0.7)


func _ready() -> void:
	var controller: DriftController = _kart.get_node("DriftController") as DriftController
	controller.drift_started.connect(_on_drift_started)
	controller.drift_tier_changed.connect(_on_tier_changed)
	controller.drift_ended.connect(_on_drift_ended)


func _process(_delta: float) -> void:
	var active: bool = _kart.get_drift_state() == DriftController.DriftState.HOLD
	for particles: GPUParticles3D in _smoke:
		particles.emitting = active
	if active:
		_set_smoke_color(_terrain_particle_color())


func _on_drift_started(_direction: int) -> void:
	for particles: GPUParticles3D in _sparks:
		particles.emitting = true


func _on_tier_changed(tier: int) -> void:
	var color: Color = _tier_color(tier)
	for particles: GPUParticles3D in _sparks:
		_set_particle_color(particles, color)
		particles.restart()


func _on_drift_ended(_released_tier: int) -> void:
	for particles: GPUParticles3D in _sparks:
		particles.emitting = false
	for particles: GPUParticles3D in _smoke:
		particles.emitting = false


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
