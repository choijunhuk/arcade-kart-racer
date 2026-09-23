shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Kart car-paint body material with the hit-flash overlay (Phase 19).
// Vertex COLOR marks the baked surface role: r = paint, g = glass, b = accent
// paint, else trim.
// Livery patterns are resolved in normalised body space (0..1 per axis,
// front of the kart = low z): 0 centre stripe, 1 two-tone lower band,
// 2 contrasting nose + wing.

uniform vec4 albedo_color : source_color = vec4(1.0);
uniform vec4 accent_color : source_color = vec4(1.0);
uniform vec4 trim_color : source_color = vec4(0.07, 0.075, 0.085, 1.0);
uniform vec4 glass_color : source_color = vec4(0.04, 0.06, 0.09, 1.0);
uniform float metallic : hint_range(0.0, 1.0) = 0.25;
uniform float roughness : hint_range(0.0, 1.0) = 0.3;
uniform float clearcoat_amount : hint_range(0.0, 1.0) = 0.9;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.35;
uniform int livery_pattern = 0;
uniform vec3 body_min = vec3(-0.8, 0.0, -1.1);
uniform vec3 body_size = vec3(1.6, 0.5, 2.2);
uniform bool use_vertex_roles = false;
uniform float flash_strength : hint_range(0.0, 1.0) = 0.0;

varying vec3 body_uvw;
varying float up_facing;

void vertex() {
	body_uvw = (VERTEX - body_min) / max(body_size, vec3(0.001));
	up_facing = NORMAL.y;
}

float accent_mask() {
	vec3 p = body_uvw;
	if (livery_pattern == 0) {
		float stripe = 1.0 - smoothstep(0.075, 0.09, abs(p.x - 0.5));
		return stripe * smoothstep(0.2, 0.45, up_facing);
	} else if (livery_pattern == 1) {
		return 1.0 - smoothstep(0.34, 0.37, p.y);
	}
	return 1.0 - smoothstep(0.24, 0.27, p.z);
}

void fragment() {
	float paint = use_vertex_roles ? COLOR.r : 1.0;
	float glass = use_vertex_roles ? COLOR.g : 0.0;
	float accent_part = use_vertex_roles ? COLOR.b : 0.0;
	vec3 livery = mix(albedo_color.rgb, accent_color.rgb, max(accent_mask() * paint, accent_part));
	paint = max(paint, accent_part);
	vec3 base = mix(trim_color.rgb, livery, paint);
	base = mix(base, glass_color.rgb, glass);
	ALBEDO = mix(base, vec3(1.0), flash_strength);
	METALLIC = mix(0.1, metallic, paint) + glass * 0.3;
	ROUGHNESS = mix(mix(0.55, roughness, paint), 0.05, glass);
	CLEARCOAT = clearcoat_amount * max(paint, glass);
	CLEARCOAT_ROUGHNESS = 0.12;
	RIM = rim_strength * paint;
	RIM_TINT = 0.6;
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	EMISSION = livery * fresnel * 0.18 * paint + vec3(1.0) * flash_strength * 2.0;
}
