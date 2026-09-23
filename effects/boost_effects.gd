class_name BoostEffects
extends Node3D

## Boost exhaust: flickering two-layer flame cone, fire embers, a punch on
## boost start (mini-turbo burst) and a screen-reading heat shimmer (high tier).

## Heat-shimmer fade speed in intensity units per second, applied on both the
## rise (boost start) and fall (boost end) edges.
const SHIMMER_FADE_SPEED: float = 4.0
## The shimmer reads the screen texture (one extra screen copy per frame while visible), so it is
## a high-tier-only effect: below this particle quality ratio it never shows.
const SHIMMER_MIN_QUALITY_RATIO: float = 0.9
const FLAME_LENGTH: float = 0.62
const FLAME_RADIUS: float = 0.12
const CORE_SCALE: float = 0.55
const OUTER_COLOR: Color = Color(1.0, 0.45, 0.1, 0.85)
const CORE_COLOR: Color = Color(1.0, 0.95, 0.75, 1.0)
const FLICKER_SPEED: float = 40.0
const FLICKER_AMOUNT: float = 0.22
const BURST_SECONDS: float = 0.22
const BURST_SCALE: float = 1.9
const GROW_SPEED: float = 9.0

@onready var _kart: KartController = get_parent() as KartController
@onready var _exhaust: GPUParticles3D = $Exhaust
@onready var _flame_core: Node3D = $FlameCore
@onready var _heat_shimmer: MeshInstance3D = $HeatShimmer
var _shimmer_material: ShaderMaterial
var _shimmer_allowed: bool = true

var _boost_active: bool = false
var _lod_enabled: bool = true
var _shimmer_intensity: float = 0.0
var _flame_amount: float = 0.0
var _burst_remaining: float = 0.0
var _flicker_phase: float = 0.0
var _noise: FastNoiseLite = FastNoiseLite.new()


func _ready() -> void:
	# The quad + ShaderMaterial are a shared sub-resource of the scene: without a per-kart copy every
	# kart's _process overwrote the same "intensity", so one idle kart zeroed everyone's shimmer.
	_heat_shimmer.mesh = _heat_shimmer.mesh.duplicate(true)
	_shimmer_material = _heat_shimmer.mesh.material as ShaderMaterial
	_exhaust.material_override = ParticleArt.material(true)
	_flame_core.add_child(_make_cone(FLAME_RADIUS, OUTER_COLOR))
	_flame_core.add_child(_make_cone(FLAME_RADIUS * CORE_SCALE, CORE_COLOR))
	_noise.seed = get_instance_id() % 997
	_noise.frequency = 1.0
	var controller: BoostController = _kart.get_node("BoostController") as BoostController
	controller.boost_started.connect(_on_boost_started)
	controller.boost_ended.connect(_on_boost_ended)


func _process(delta: float) -> void:
	var showing: bool = _boost_active and _lod_enabled
	_exhaust.emitting = showing
	_flame_amount = move_toward(_flame_amount, 1.0 if showing else 0.0, GROW_SPEED * delta)
	_burst_remaining = maxf(0.0, _burst_remaining - delta)
	_flame_core.visible = _flame_amount > 0.0
	if _flame_core.visible:
		_flicker_phase += FLICKER_SPEED * delta
		var flicker: float = 1.0 + _noise.get_noise_1d(_flicker_phase) * FLICKER_AMOUNT * 2.0
		var burst: float = lerpf(1.0, BURST_SCALE, _burst_remaining / BURST_SECONDS)
		var width: float = _flame_amount * lerpf(1.0, 1.25, _burst_remaining / BURST_SECONDS)
		_flame_core.scale = Vector3(width, width, _flame_amount * flicker * burst)
	var target: float = 1.0 if (showing and _shimmer_allowed) else 0.0
	_shimmer_intensity = move_toward(_shimmer_intensity, target, SHIMMER_FADE_SPEED * delta)
	_heat_shimmer.visible = _shimmer_intensity > 0.0
	_shimmer_material.set_shader_parameter("intensity", _shimmer_intensity)


func _on_boost_started(_spec: BoostSpecData) -> void:
	_boost_active = true
	_burst_remaining = BURST_SECONDS
	_exhaust.emitting = _lod_enabled
	if _lod_enabled:
		_exhaust.restart()


func _on_boost_ended() -> void:
	_boost_active = false
	_exhaust.emitting = false


## Enables or disables exhaust for camera-distance LOD without losing boost state.
func set_lod_enabled(enabled: bool) -> void:
	_lod_enabled = enabled
	_exhaust.emitting = _boost_active and _lod_enabled


## Applies the user-selected visual density without restarting the exhaust.
func set_quality_ratio(ratio: float) -> void:
	_exhaust.amount_ratio = clampf(ratio, 0.0, 1.0)
	_shimmer_allowed = ratio >= SHIMMER_MIN_QUALITY_RATIO


## Additive cone pointing backwards (+Z) from the tail pipe, fading to its tip.
static func _make_cone(radius: float, color: Color) -> MeshInstance3D:
	var cone: CylinderMesh = CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = radius
	cone.height = FLAME_LENGTH
	cone.radial_segments = 10
	cone.rings = 1
	cone.cap_top = false
	cone.cap_bottom = false
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = color
	material.albedo_texture = _fade_texture()
	var node: MeshInstance3D = MeshInstance3D.new()
	node.mesh = cone
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.rotation.x = PI * 0.5
	node.position.z = FLAME_LENGTH * 0.5
	return node


static func _fade_texture() -> GradientTexture2D:
	var gradient: Gradient = Gradient.new()
	gradient.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1)])
	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 4
	texture.height = 32
	texture.fill_from = Vector2(0.0, 0.0)
	texture.fill_to = Vector2(0.0, 1.0)
	return texture
