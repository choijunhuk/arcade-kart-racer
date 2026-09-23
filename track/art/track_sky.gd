class_name TrackSky
extends RefCounted

## Phase 19 per-theme atmosphere: sky shader, sun/moon light, depth fog matched
## to the horizon, tonemap/colour grade and post settings. Effects that cost GPU
## time are enabled per tier by `QualityTier.apply_scene`, not here.

const SKY_SHADER: Shader = preload("res://assets/shaders/world/sky.gdshader")
const NIGHT_THEME: int = 1
const FOG_SKY_AFFECT: float = 0.12
const FOG_AERIAL: float = 0.35
const GLOW_THRESHOLD: float = 1.05

## 0 ridgeline (sunny hills), 1 lumen (night neon), 2 glacier (bright alpine), 3 ochre (desert canyon).
const THEMES: Array[Dictionary] = [
	{
		"top": Color(0.2, 0.45, 0.86), "horizon": Color(0.7, 0.83, 0.95), "ground": Color(0.55, 0.66, 0.74),
		"sun": Color(1.0, 0.95, 0.86), "sun_energy": 1.45, "sun_rotation": Vector3(-48.0, -38.0, 0.0),
		"clouds": 0.5, "cloud_shade": Color(0.68, 0.76, 0.88), "stars": 0.0, "glow": Color(0, 0, 0),
		"fog": 0.0009, "ambient": 0.75, "exposure": 1.05, "saturation": 1.18, "contrast": 1.06,
	},
	{
		"top": Color(0.01, 0.012, 0.045), "horizon": Color(0.12, 0.07, 0.24), "ground": Color(0.05, 0.04, 0.1),
		"sun": Color(0.62, 0.72, 1.0), "sun_energy": 0.3, "sun_rotation": Vector3(-35.0, 140.0, 0.0),
		"clouds": 0.3, "cloud_shade": Color(0.05, 0.05, 0.12), "cloud_color": Color(0.22, 0.14, 0.32),
		"stars": 1.0, "glow": Color(0.5, 0.18, 0.42), "sky_sun_energy": 3.0, "sun_size": 0.02,
		"fog": 0.0028, "ambient": 0.55, "ambient_color": Color(0.25, 0.28, 0.5), "exposure": 1.1,
		"saturation": 1.25, "contrast": 1.08, "ssr": true,
	},
	{
		"top": Color(0.14, 0.36, 0.8), "horizon": Color(0.68, 0.82, 0.96), "ground": Color(0.7, 0.8, 0.9),
		"sun": Color(1.0, 0.97, 0.93), "sun_energy": 1.3, "sun_rotation": Vector3(-42.0, -150.0, 0.0),
		"clouds": 0.38, "cloud_shade": Color(0.7, 0.78, 0.9), "stars": 0.0, "glow": Color(0, 0, 0),
		"fog": 0.0011, "ambient": 0.7, "exposure": 0.92, "saturation": 1.12, "contrast": 1.08,
	},
	{
		"top": Color(0.24, 0.47, 0.8), "horizon": Color(0.93, 0.79, 0.62), "ground": Color(0.8, 0.6, 0.45),
		"sun": Color(1.0, 0.86, 0.66), "sun_energy": 1.55, "sun_rotation": Vector3(-52.0, 55.0, 0.0),
		"clouds": 0.25, "cloud_shade": Color(0.85, 0.72, 0.64), "stars": 0.0, "glow": Color(0.25, 0.1, 0.02),
		"fog": 0.0012, "ambient": 1.4, "exposure": 1.0, "saturation": 1.1, "contrast": 1.06,
	},
]


## Configures the track's (duplicated) WorldEnvironment and sun for `theme`.
static func apply(track: Node, theme: int) -> void:
	var look: Dictionary = THEMES[clampi(theme, 0, THEMES.size() - 1)]
	var environments: Array[Node] = track.find_children("*", "WorldEnvironment", true, false)
	if not environments.is_empty():
		var world: WorldEnvironment = environments[0] as WorldEnvironment
		world.environment = world.environment.duplicate() as Environment
		_environment(world.environment, look)
	for node: Node in track.find_children("*", "DirectionalLight3D", true, false):
		_sun(node as DirectionalLight3D, look)


static func horizon_color(theme: int) -> Color:
	return THEMES[clampi(theme, 0, THEMES.size() - 1)]["horizon"]


static func _environment(environment: Environment, look: Dictionary) -> void:
	var paint: ShaderMaterial = ShaderMaterial.new()
	paint.shader = SKY_SHADER
	paint.set_shader_parameter(&"top_color", look["top"])
	paint.set_shader_parameter(&"horizon_color", look["horizon"])
	paint.set_shader_parameter(&"ground_color", look["ground"])
	paint.set_shader_parameter(&"sun_color", look["sun"])
	paint.set_shader_parameter(&"cloud_coverage", look["clouds"])
	paint.set_shader_parameter(&"cloud_shade", look["cloud_shade"])
	paint.set_shader_parameter(&"cloud_color", look.get("cloud_color", Color(1, 1, 1)))
	paint.set_shader_parameter(&"stars", look["stars"])
	paint.set_shader_parameter(&"glow_color", look["glow"])
	paint.set_shader_parameter(&"sun_energy", look.get("sky_sun_energy", 12.0))
	paint.set_shader_parameter(&"sun_size", look.get("sun_size", 0.035))
	var sky: Sky = Sky.new()
	sky.sky_material = paint
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	environment.sky = sky
	environment.background_mode = Environment.BG_SKY
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = look["ambient"]
	if look.has("ambient_color"):
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.ambient_light_color = look["ambient_color"]
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	environment.tonemap_exposure = look["exposure"]
	environment.adjustment_enabled = true
	environment.adjustment_saturation = look["saturation"]
	environment.adjustment_contrast = look["contrast"]
	environment.glow_intensity = 0.7
	environment.glow_strength = 1.0
	environment.glow_bloom = 0.0
	environment.glow_hdr_threshold = GLOW_THRESHOLD
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	environment.ssao_radius = 1.2
	environment.ssao_intensity = 1.5
	environment.ssao_power = 1.4
	environment.ssao_light_affect = 0.15
	environment.ssil_radius = 4.0
	environment.ssil_intensity = 0.8
	environment.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	environment.fog_light_color = look["horizon"]
	environment.fog_light_energy = 1.0
	environment.fog_sun_scatter = 0.08
	environment.fog_density = look["fog"]
	environment.fog_sky_affect = FOG_SKY_AFFECT
	environment.fog_aerial_perspective = FOG_AERIAL
	environment.ssr_max_steps = 48
	environment.ssr_fade_out = 1.5
	environment.set_meta(QualityTier.SSR_META, bool(look.get("ssr", false)))


static func _sun(sun: DirectionalLight3D, look: Dictionary) -> void:
	sun.rotation_degrees = look["sun_rotation"]
	sun.light_color = look["sun"]
	sun.light_energy = look["sun_energy"]
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.1
	sun.shadow_blur = 1.2
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_fade_start = 0.85
