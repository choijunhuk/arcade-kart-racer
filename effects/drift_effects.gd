class_name DriftEffects
extends Node3D

## Rear-wheel drift sparks (tier-coloured), tier-up / mini-turbo flashes, and
## terrain-aware tyre smoke or dust kick-up. Presentation only.

## Charging (tier 0) sparks: sparse hot-metal yellow until the first tier is reached.
const CHARGING_SPARK_COLOR: Color = Color(1.0, 0.78, 0.32)
const CHARGING_SPARK_RATIO: float = 0.3
const FLASH_SIZE: float = 0.9
const TIER_FLASH_SECONDS: float = 0.18
const TIER_FLASH_SCALE: float = 1.3
const RELEASE_FLASH_SECONDS: float = 0.3
const RELEASE_FLASH_SCALE: float = 2.4
const ASPHALT_SMOKE_COLOR: Color = Color(0.9, 0.9, 0.92, 0.45)
const SNOW_TERRAINS: Array[StringName] = [&"ice", &"snow"]

@export var tuning: FeelTuning = preload("res://data/tuning/feel_default.tres")

@onready var _kart: KartController = get_parent() as KartController
@onready var _sparks: Array[GPUParticles3D] = [$SparkLeft, $SparkRight]
@onready var _smoke: Array[GPUParticles3D] = [$SmokeLeft, $SmokeRight]

var _cached_terrain_id: StringName = &""
var _cached_terrain_color: Color = Color(0.65, 0.65, 0.65, 0.7)
var _lod_enabled: bool = true
var _quality_ratio: float = 1.0
var _tier: int = 0
var _flashes: Array[MeshInstance3D] = []
var _flash_material: StandardMaterial3D
var _flash_remaining: float = 0.0
var _flash_duration: float = 1.0
var _flash_scale: float = 1.0


func _ready() -> void:
	# Process materials are scene sub-resources shared by every kart instance;
	# give each kart its own copy (left/right still share it) so one kart's
	# tier or terrain colour never recolours the whole field.
	var spark_process: ParticleProcessMaterial = _sparks[0].process_material.duplicate() as ParticleProcessMaterial
	var smoke_process: ParticleProcessMaterial = _smoke[0].process_material.duplicate() as ParticleProcessMaterial
	var spark_material: StandardMaterial3D = ParticleArt.material(true)
	var smoke_material: StandardMaterial3D = ParticleArt.material()
	for particles: GPUParticles3D in _sparks:
		particles.process_material = spark_process
		particles.material_override = spark_material
	for particles: GPUParticles3D in _smoke:
		particles.process_material = smoke_process
		particles.material_override = smoke_material
	_build_flashes()
	var controller: DriftController = _kart.get_node("DriftController") as DriftController
	controller.drift_started.connect(_on_drift_started)
	controller.drift_tier_changed.connect(_on_tier_changed)
	controller.drift_ended.connect(_on_drift_ended)


func _process(delta: float) -> void:
	var drifting: bool = _kart.get_drift_state() == DriftController.DriftState.HOLD
	var active: bool = should_emit_smoke(
		drifting, _kart.get_terrain_id(), _kart.get_brake_input(),
		_kart.get_speed_ratio(), tuning.smoke_brake_threshold,
		tuning.smoke_min_speed_ratio,
	)
	for particles: GPUParticles3D in _smoke:
		particles.emitting = active and _lod_enabled
	for particles: GPUParticles3D in _sparks:
		particles.emitting = drifting and _lod_enabled and _kart.is_grounded()
	if active:
		_apply_terrain_profile(_kart.get_terrain_id())
	_update_flash(delta)


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
	_tier = 0
	for particles: GPUParticles3D in _sparks:
		_set_particle_color(particles, CHARGING_SPARK_COLOR)
		particles.emitting = _lod_enabled
	_apply_spark_ratio()


func _on_tier_changed(tier: int) -> void:
	_tier = tier
	var color: Color = _tier_color(tier)
	for particles: GPUParticles3D in _sparks:
		_set_particle_color(particles, color)
		particles.restart()
	_apply_spark_ratio()
	if tier > 0:
		_start_flash(color, TIER_FLASH_SECONDS, TIER_FLASH_SCALE)


func _on_drift_ended(released_tier: int) -> void:
	for particles: GPUParticles3D in _sparks:
		particles.emitting = false
	if released_tier > 0:
		_start_flash(_tier_color(released_tier), RELEASE_FLASH_SECONDS, RELEASE_FLASH_SCALE)
	_tier = 0


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
	_quality_ratio = clampf(ratio, 0.0, 1.0)
	_apply_spark_ratio()
	for particles: GPUParticles3D in _smoke:
		particles.amount_ratio = _quality_ratio


func _apply_spark_ratio() -> void:
	var ratio: float = _quality_ratio * (CHARGING_SPARK_RATIO if _tier == 0 else 1.0)
	for particles: GPUParticles3D in _sparks:
		particles.amount_ratio = ratio


func _tier_color(tier: int) -> Color:
	match tier:
		2:
			return tuning.drift_tier_amber
		3:
			return tuning.drift_tier_magenta
		_:
			return tuning.drift_tier_cyan


## Asphalt gives light rising tyre smoke; loose terrain throws heavier dust or
## powder in its own colour that arcs back down.
func _apply_terrain_profile(terrain_id: StringName) -> void:
	if terrain_id == _cached_terrain_id:
		return
	_cached_terrain_id = terrain_id
	var path: String = "res://data/terrain/%s.tres" % String(terrain_id)
	_cached_terrain_color = (load(path) as TerrainData).particle_color if ResourceLoader.exists(path) else Color(0.65, 0.65, 0.65)
	var process: ParticleProcessMaterial = _smoke[0].process_material as ParticleProcessMaterial
	if terrain_id == &"asphalt":
		process.color = ASPHALT_SMOKE_COLOR
		process.gravity = Vector3(0.0, 0.4, 0.0)
		process.initial_velocity_min = 0.8
		process.initial_velocity_max = 1.8
	else:
		var powder: bool = SNOW_TERRAINS.has(terrain_id)
		process.color = Color(_cached_terrain_color.lightened(0.35 if powder else 0.1), 0.85)
		process.gravity = Vector3(0.0, -3.0 if powder else -6.0, 0.0)
		process.initial_velocity_min = 1.8
		process.initial_velocity_max = 3.4


func _build_flashes() -> void:
	_flash_material = ParticleArt.material(true)
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2.ONE * FLASH_SIZE
	for spark: GPUParticles3D in _sparks:
		var flash: MeshInstance3D = MeshInstance3D.new()
		flash.mesh = quad
		flash.material_override = _flash_material
		flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		flash.position = spark.position + Vector3(0.0, 0.1, 0.0)
		flash.visible = false
		add_child(flash)
		_flashes.append(flash)


func _start_flash(color: Color, seconds: float, peak_scale: float) -> void:
	if not _lod_enabled:
		return
	_flash_material.albedo_color = color
	_flash_duration = seconds
	_flash_remaining = seconds
	_flash_scale = peak_scale


func _update_flash(delta: float) -> void:
	if _flash_remaining <= 0.0:
		return
	_flash_remaining = maxf(0.0, _flash_remaining - delta)
	var progress: float = 1.0 - _flash_remaining / _flash_duration
	var size: float = lerpf(0.4, _flash_scale, sqrt(progress))
	_flash_material.albedo_color.a = 1.0 - progress
	for flash: MeshInstance3D in _flashes:
		flash.visible = _flash_remaining > 0.0
		flash.scale = Vector3.ONE * size


func _set_particle_color(particles: GPUParticles3D, color: Color) -> void:
	var material: ParticleProcessMaterial = particles.process_material as ParticleProcessMaterial
	if material != null:
		material.color = color
