shader_type canvas_item;
render_mode unshaded;

// Animated arcade backdrop shared by every menu screen (Phase 19): deep navy
// gradient, slow diagonal "speed" bands, a faint perspective grid rushing
// toward the horizon, a turbo-orange glow low-left and a vignette. One
// fullscreen fragment pass, no textures, no per-frame CPU cost.
uniform vec4 color_top : source_color = vec4(0.025, 0.03, 0.075, 1.0);
uniform vec4 color_bottom : source_color = vec4(0.05, 0.075, 0.16, 1.0);
uniform vec4 band_color : source_color = vec4(0.16, 0.85, 1.0, 1.0);
uniform vec4 glow_color : source_color = vec4(1.0, 0.42, 0.08, 1.0);
uniform float band_speed : hint_range(0.0, 2.0) = 0.12;
uniform float band_strength : hint_range(0.0, 1.0) = 0.07;
uniform float grid_strength : hint_range(0.0, 1.0) = 0.16;
uniform float glow_strength : hint_range(0.0, 1.0) = 0.32;

float band(float x, float width) {
	float f = fract(x);
	return smoothstep(0.0, width, f) * smoothstep(width * 2.0, width, f);
}

void fragment() {
	vec2 uv = UV;
	vec3 color = mix(color_top.rgb, color_bottom.rgb, uv.y);
	// Slanted speed bands drifting right.
	float slant = uv.x * 1.6 - uv.y * 0.9 - TIME * band_speed;
	float bands = band(slant * 2.2, 0.06) * 0.8 + band(slant * 5.3 + 0.37, 0.03) * 0.5;
	color += band_color.rgb * bands * band_strength;
	// Perspective floor grid below the horizon line.
	float horizon = 0.58;
	if (uv.y > horizon) {
		float depth = (uv.y - horizon) / (1.0 - horizon);
		float z = 1.0 / max(depth, 0.02);
		float rows = abs(fract(z * 0.9 - TIME * 0.9) - 0.5);
		float cols = abs(fract((uv.x - 0.5) * z * 1.4) - 0.5);
		float line_w = 0.04 * z * 0.25 + 0.01;
		float grid = (1.0 - smoothstep(0.0, line_w, rows)) + (1.0 - smoothstep(0.0, line_w * 1.2, cols));
		color += band_color.rgb * clamp(grid, 0.0, 1.0) * grid_strength * depth;
		color += glow_color.rgb * 0.05 * (1.0 - depth);
	}
	// Turbo glow low-left, cool glow top-right.
	color += glow_color.rgb * glow_strength * pow(max(0.0, 1.0 - distance(uv, vec2(0.05, 1.05)) * 1.3), 2.2);
	color += band_color.rgb * 0.08 * pow(max(0.0, 1.0 - distance(uv, vec2(0.95, 0.0)) * 1.4), 2.0);
	// Vignette.
	float vig = smoothstep(1.05, 0.35, distance(uv, vec2(0.5)));
	COLOR = vec4(color * mix(0.55, 1.0, vig), 1.0);
}
