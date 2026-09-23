shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

// Stylised race surface. Mesh contract (RoadRibbon / TrackBuilder):
//   UV.x  = lateral metres from the centre line (negative = left)
//   UV.y  = distance along the lap in metres
//   UV2.x = road half width in metres, UV2.y = corner mask (1 = kerbs on)

#include "res://assets/shaders/world/world_noise.gdshaderinc"

uniform vec3 base_color : source_color = vec3(0.23, 0.24, 0.26);
uniform vec3 patch_color : source_color = vec3(0.3, 0.3, 0.32);
uniform vec3 wear_color : source_color = vec3(0.13, 0.13, 0.14);
uniform float wear_amount : hint_range(0.0, 1.0) = 0.45;
uniform float grain : hint_range(0.0, 1.0) = 0.22;
uniform float speckle : hint_range(0.0, 1.0) = 0.4;
// >1 stretches the detail along the lap (packed dirt / snow tyre ruts).
uniform float streak_stretch = 1.0;
uniform vec3 line_color : source_color = vec3(0.94, 0.94, 0.92);
uniform float line_emission = 0.0;
uniform vec3 kerb_color_a : source_color = vec3(0.86, 0.1, 0.08);
uniform vec3 kerb_color_b : source_color = vec3(0.95, 0.95, 0.93);
uniform float kerb_width = 1.1;
uniform float kerb_block = 1.6;
uniform float edge_inset = 0.5;
uniform float edge_width = 0.24;
uniform float dash_width = 0.2;
uniform float dash_length = 3.0;
uniform float dash_period = 7.5;
uniform float centre_line : hint_range(0.0, 1.0) = 1.0;
uniform float paint_fade : hint_range(0.0, 1.0) = 0.25;
uniform float roughness_base : hint_range(0.0, 1.0) = 0.86;
uniform float wetness : hint_range(0.0, 1.0) = 0.0;
uniform float ice_sheen : hint_range(0.0, 1.0) = 0.0;
uniform float bump_strength = 1.0;
// Start/finish checker + grid boxes; 0 on shortcut ribbons.
instance uniform float track_length = 0.0;
uniform float grid_first = 3.0;
uniform float grid_spacing = 3.5;
uniform float grid_lateral = 1.4;
uniform int grid_rows = 4;

void fragment() {
	vec2 p = UV;
	float half_w = max(UV2.x, 1.0);
	float au = abs(p.x);
	float pixel = max(length(fwidth(p)), 0.002);
	float fine_fade = 1.0 - smoothstep(0.03, 0.12, pixel);
	vec2 stretch = vec2(1.0, 1.0 / max(streak_stretch, 0.01));

	float n_big = wn_noise(p * 0.06 + 3.1);
	float n_mid = wn_fbm(p * 0.7 * stretch);
	float n_fine = wn_noise(p * 11.0 * stretch);
	vec3 col = mix(base_color, patch_color, smoothstep(0.35, 0.75, n_big * 0.55 + n_mid * 0.45));
	col *= 1.0 + (n_fine - 0.5) * grain * 2.0 * fine_fade;
	float speck = smoothstep(0.74, 0.82, wn_noise(p * 21.0 + 5.3)) * fine_fade * speckle;
	col *= 1.0 + speck * 0.6;
	// Darker rubbered-in racing line and lengthwise tyre streaks.
	float wear = exp(-pow(p.x / (half_w * 0.42), 2.0)) * (0.55 + 0.45 * wn_noise(vec2(p.x * 0.4, p.y * 0.02)));
	col = mix(col, wear_color, wear * wear_amount);
	float streak = wn_noise(vec2(p.x * 2.6, p.y * 0.06));
	col *= 1.0 - 0.1 * smoothstep(0.55, 0.9, streak);

	float rough = roughness_base - speck * 0.1;
	float height = (n_mid * 0.004 + n_fine * 0.0025 * fine_fade) * bump_strength;

	// Painted markings.
	float kerb_on = step(0.5, UV2.y);
	float kerb_zone = kerb_on * kerb_width;
	float paint = wn_band(au, half_w - edge_inset - kerb_zone, edge_width * 0.5, pixel);
	float dash = wn_band(fract(p.y / dash_period) * dash_period, dash_length * 0.5, dash_length * 0.5, pixel);
	paint = max(paint, wn_band(au, 0.0, dash_width * 0.5, pixel) * dash * centre_line);
	vec3 paint_color = line_color;
	float paint_glow = line_emission;

	// Start/finish checker band and grid slot brackets.
	if (track_length > 0.0) {
		float wrapped = p.y > track_length * 0.5 ? p.y - track_length : p.y;
		float checker_mask = wn_band(wrapped, 0.0, 1.2, pixel) * step(au, half_w - 0.05);
		float cells = mod(floor((p.x + half_w) / 0.8) + floor((wrapped + 1.2) / 0.8), 2.0);
		col = mix(col, mix(vec3(0.05), vec3(0.93), cells), checker_mask);
		paint *= 1.0 - checker_mask;
		float grid = 0.0;
		for (int row = 0; row < grid_rows; row++) {
			float front = grid_first + grid_spacing * float(row) + 1.3;
			float in_row = wn_band(wrapped, front, 0.09, pixel);
			grid = max(grid, in_row * wn_band(au, grid_lateral, 0.9, pixel));
			float tick = step(front - 1.0, wrapped) * step(wrapped, front);
			grid = max(grid, tick * wn_band(au, grid_lateral + 0.9, 0.07, pixel));
		}
		paint = max(paint, grid);
	}

	// Corner kerbs replace the outer strip of asphalt.
	float kerb = kerb_on * smoothstep(half_w - kerb_width - pixel, half_w - kerb_width + pixel, au);
	float stripe = step(0.5, fract(p.y / (kerb_block * 2.0)));
	vec3 kerb_col = mix(kerb_color_a, kerb_color_b, stripe);
	paint *= 1.0 - kerb;

	float fade = 1.0 - paint_fade * smoothstep(0.4, 0.8, n_mid) * fine_fade;
	col = mix(col, paint_color, paint * fade);
	col = mix(col, kerb_col, kerb);
	rough = mix(rough, 0.55, max(paint, kerb));
	height += kerb * 0.012 * (0.5 + 0.5 * sin(p.y / kerb_block * 3.14159));

	// Theme finishes: wet asphalt puddles, glazed ice.
	float puddle = wetness * smoothstep(0.42, 0.62, wn_fbm(p * 0.18 + 7.0));
	float wet = clamp(wetness * 0.55 + puddle, 0.0, 1.0);
	col *= 1.0 - wet * 0.45;
	rough = mix(rough, 0.05, wet);
	height *= 1.0 - puddle;
	float glaze = ice_sheen * smoothstep(0.45, 0.7, n_mid + (n_big - 0.5) * 0.4);
	rough = mix(rough, 0.12, glaze);
	col = mix(col, col * vec3(0.86, 0.95, 1.08), glaze);

	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.5 + wet * 0.3 + glaze * 0.2;
	EMISSION = paint_color * paint * paint_glow;
	NORMAL = wn_bump(NORMAL, VERTEX, height);
}
