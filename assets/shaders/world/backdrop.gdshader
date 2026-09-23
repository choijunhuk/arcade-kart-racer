shader_type spatial;
render_mode blend_mix, cull_disabled, diffuse_lambert, specular_disabled, shadows_disabled;

// Distant horizon silhouettes (mountains, skyline, ice ridges, mesas).
// UV.x = arc length in metres, UV.y = height above the ring base in metres.
// Scene fog blends them into the sky's horizon colour.

#include "res://assets/shaders/world/world_noise.gdshaderinc"

uniform vec3 base_color : source_color = vec3(0.25, 0.4, 0.3);
uniform vec3 peak_color : source_color = vec3(0.45, 0.55, 0.6);
uniform vec3 cap_color : source_color = vec3(0.95, 0.97, 1.0);
uniform float peak_height = 160.0;
uniform float cap_line = 2.0;
uniform float strata = 0.0;
uniform float windows = 0.0;
uniform vec3 window_color : source_color = vec3(1.0, 0.75, 0.4);
uniform vec3 window_color_b : source_color = vec3(0.3, 0.85, 1.0);
uniform float window_energy = 2.5;

void fragment() {
	vec2 p = UV;
	float t = clamp(p.y / peak_height, 0.0, 1.0);
	vec3 col = mix(base_color, peak_color, smoothstep(0.0, 1.0, t));
	float n = wn_fbm(p * vec2(0.02, 0.05));
	col *= 0.88 + n * 0.24;
	col = mix(col, cap_color, smoothstep(cap_line - 0.05, cap_line + 0.05, t + (n - 0.5) * 0.25));
	if (strata > 0.0) {
		float band = fract(p.y * 0.045 + n * 1.5);
		col *= 1.0 - strata * 0.18 * step(0.7, band);
	}
	vec3 glow = vec3(0.0);
	if (windows > 0.0) {
		vec2 cell = floor(p / vec2(4.0, 5.0));
		vec2 local = fract(p / vec2(4.0, 5.0));
		float lit = step(0.62, wn_hash12(cell)) * step(0.25, local.x) * step(local.x, 0.75) * step(0.3, local.y) * step(local.y, 0.7);
		vec3 tint = mix(window_color, window_color_b, step(0.5, wn_hash12(cell + 3.0)));
		glow = tint * lit * windows * window_energy * step(8.0, p.y);
	}
	ALBEDO = col;
	ROUGHNESS = 1.0;
	EMISSION = glow;
}
