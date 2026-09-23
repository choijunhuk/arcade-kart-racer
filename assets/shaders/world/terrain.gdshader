shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;

// Off-road ground in world space (grass / snow / sand / city lot): low-frequency
// colour variation so large areas never read as a flat fill.

#include "res://assets/shaders/world/world_noise.gdshaderinc"

uniform vec3 color_a : source_color = vec3(0.24, 0.5, 0.2);
uniform vec3 color_b : source_color = vec3(0.34, 0.58, 0.22);
uniform vec3 color_accent : source_color = vec3(0.45, 0.52, 0.22);
uniform float accent_amount : hint_range(0.0, 1.0) = 0.5;
uniform float detail : hint_range(0.0, 1.0) = 0.25;
uniform float ripple : hint_range(0.0, 1.0) = 0.0;
uniform float sparkle : hint_range(0.0, 1.0) = 0.0;
uniform float mow_stripes : hint_range(0.0, 1.0) = 0.0;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.92;
uniform float bump_strength = 1.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	float pixel = max(length(fwidth(p)), 0.002);
	float fine_fade = 1.0 - smoothstep(0.05, 0.3, pixel);
	float big = wn_fbm(p * 0.011);
	float mid = wn_fbm(p * 0.07 + 5.0);
	float fine = wn_noise(p * 2.3);
	vec3 col = mix(color_a, color_b, smoothstep(0.3, 0.7, big));
	col = mix(col, color_accent, smoothstep(0.58, 0.78, mid) * accent_amount);
	col *= 1.0 + (fine - 0.5) * detail * 2.0 * fine_fade;
	col *= 1.0 + mow_stripes * 0.07 * sign(sin(p.x * 0.25 + p.y * 0.25));
	float height = (mid * 0.12 + fine * 0.01 * fine_fade) * bump_strength;
	float wave = sin(dot(p, vec2(0.9, 0.45)) + wn_fbm(p * 0.03) * 9.0);
	height += wave * 0.035 * ripple;
	col *= 1.0 + wave * 0.05 * ripple;
	float glint = step(0.992, wn_hash12(floor(p * 18.0))) * fine_fade * sparkle;
	ALBEDO = col;
	ROUGHNESS = mix(roughness_value, 0.2, glint);
	SPECULAR = 0.5 + glint * 0.5;
	EMISSION = vec3(0.8, 0.9, 1.0) * glint * 0.6;
	NORMAL = wn_bump(NORMAL, VERTEX, height);
}
