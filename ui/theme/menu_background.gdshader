shader_type canvas_item;
render_mode unshaded;

// Slow animated gradient for menu backgrounds (Phase 17b item 5). Cheap: one
// fullscreen fragment pass, no textures, no per-frame CPU cost.
uniform vec4 color_top : source_color = vec4(0.012, 0.025, 0.06, 1.0);
uniform vec4 color_bottom : source_color = vec4(0.03, 0.09, 0.16, 1.0);
uniform vec4 color_drift : source_color = vec4(0.05, 0.2, 0.26, 1.0);
uniform float drift_speed : hint_range(0.0, 1.0) = 0.05;
uniform float drift_strength : hint_range(0.0, 1.0) = 0.22;

void fragment() {
	vec3 gradient = mix(color_top.rgb, color_bottom.rgb, UV.y);
	float drift = sin(TIME * drift_speed * TAU + UV.x * 2.4) * 0.5 + 0.5;
	gradient = mix(gradient, color_drift.rgb, drift * drift_strength);
	COLOR = vec4(gradient, 1.0);
}
