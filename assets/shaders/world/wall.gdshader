shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;

// Track barriers per theme. style: 0 painted concrete, 1 night concrete with
// neon strips, 2 glacier ice, 3 canyon rock strata. Vertical placement uses the
// model-space height span handed in per instance (walls are separate meshes).

#include "res://assets/shaders/world/world_noise.gdshaderinc"

uniform int style = 0;
uniform vec3 color_a : source_color = vec3(0.8, 0.8, 0.78);
uniform vec3 color_b : source_color = vec3(0.86, 0.12, 0.1);
uniform vec3 color_c : source_color = vec3(0.95, 0.95, 0.93);
uniform vec3 glow_color : source_color = vec3(0.1, 0.85, 1.0);
uniform float glow_energy = 4.0;
uniform float block_length = 2.4;
uniform float bump_strength = 1.0;
instance uniform float wall_bottom = -1.0;
instance uniform float wall_height = 2.0;
instance uniform float wall_glow = 1.0;

varying vec3 world_pos;
varying vec3 world_normal;
varying float local_y;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	local_y = VERTEX.y;
}

// Dominant-axis projection: walls are near-vertical, so one fbm lookup
// instead of a three-way triplanar blend keeps full-screen canyon walls cheap.
float projected(vec3 p, vec3 n, float scale) {
	vec3 a = abs(n);
	vec2 uv = a.y > max(a.x, a.z) ? p.xz : (a.x > a.z ? p.zy : p.xy);
	return wn_fbm(uv * scale);
}

void fragment() {
	vec3 n = normalize(world_normal);
	float along = abs(n.x) > abs(n.z) ? world_pos.z : world_pos.x;
	float h01 = clamp((local_y - wall_bottom) / max(wall_height, 0.01), 0.0, 1.0);
	float top = smoothstep(0.6, 0.8, n.y);
	float pixel = max(length(fwidth(world_pos)), 0.002);
	float detail = projected(world_pos, n, 1.3);
	vec3 col = color_a;
	float rough = 0.85;
	float spec = 0.5;
	float height = detail * 0.01;
	vec3 glow = vec3(0.0);

	if (style == 0) {
		// Painted concrete: striped upper band, panel seams, tyre scuffs.
		float stripe = step(0.5, fract(along / (block_length * 2.0)));
		float band = smoothstep(0.55, 0.57, h01) * (1.0 - top);
		col = color_a * (0.9 + detail * 0.2);
		col = mix(col, mix(color_b, color_c, stripe), band);
		float seam = wn_band(fract(along / 4.0) * 4.0, 0.0, 0.03, pixel);
		col *= 1.0 - seam * 0.35;
		float scuff = (1.0 - smoothstep(0.1, 0.35, h01)) * smoothstep(0.45, 0.7, wn_noise(vec2(along * 0.4, h01 * 3.0)));
		col = mix(col, vec3(0.12), scuff * 0.5 * (1.0 - top));
		col = mix(col, color_a * 0.8, top);
		rough = mix(0.8, 0.5, band);
	} else if (style == 1) {
		// Night underpass: dark panels, thin neon strips (emissive only there).
		col = color_a * (0.8 + detail * 0.4);
		float seam = wn_band(fract(along / 6.0) * 6.0, 0.0, 0.05, pixel);
		col = mix(col, color_a * 2.2, seam * (1.0 - top));
		float strip_y = wall_height * (1.0 - h01);
		float strip = wn_band(strip_y, 0.45, 0.07, pixel) + wn_band(h01 * wall_height, 0.35, 0.05, pixel) * 0.7;
		strip *= wall_glow * (1.0 - top);
		float pulse = 0.75 + 0.25 * step(0.5, fract(along / 18.0));
		glow = glow_color * strip * glow_energy * pulse;
		col = mix(col, glow_color * 0.5, clamp(strip, 0.0, 1.0));
		rough = 0.45;
	} else if (style == 2) {
		// Glacier ice: deep-to-pale gradient, vertical streaks, cracks, rim light.
		float streak = wn_fbm(vec2(along * 0.6, world_pos.y * 0.08));
		col = mix(color_b, color_a, smoothstep(0.0, 1.0, h01 * 0.7 + streak * 0.5));
		float crack = 1.0 - smoothstep(0.0, 0.03, abs(wn_noise(vec2(along, world_pos.y) * 0.45) - 0.5));
		col = mix(col, color_c, crack * 0.6);
		col = mix(col, color_c, top * 0.8);
		float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
		glow = color_b * 0.12 + color_c * fresnel * 0.25;
		rough = mix(0.12, 0.35, streak);
		spec = 0.65;
		height = streak * 0.05 + crack * -0.01;
	} else {
		// Canyon rock: warped horizontal strata, sandy ledges.
		float warp = wn_fbm(vec2(along * 0.05, world_pos.y * 0.02)) * 3.0;
		float strata = fract(world_pos.y * 0.33 + warp);
		float ramp = wn_noise(vec2(floor(world_pos.y * 0.33 + warp), 1.7));
		col = mix(color_a, color_b, ramp);
		col = mix(col, color_c, smoothstep(0.82, 0.95, strata) * 0.7);
		col *= 0.82 + detail * 0.36;
		col = mix(col, color_c * 1.05, top * 0.6);
		height = detail * 0.25 + smoothstep(0.8, 0.95, strata) * 0.08;
		rough = 0.95;
		spec = 0.3;
	}

	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = spec;
	EMISSION = glow;
	NORMAL = wn_bump(NORMAL, VERTEX, height * bump_strength);
}
