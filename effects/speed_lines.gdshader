shader_type canvas_item;
render_mode unshaded;

// Edge-only radial speed streaks (Phase 19). Thin dashes radiate from the
// horizon focus point and live only in the left/right road bands: the centre
// (central_clear_fraction), the sky above the horizon and the bottom HUD band
// are always masked out, and HUD canvas layers draw on top of this one.

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float central_clear_fraction : hint_range(0.0, 1.0) = 0.4;
uniform vec4 line_color : source_color = vec4(0.92, 0.97, 1.0, 0.55);
uniform vec2 focus = vec2(0.5, 0.44);
uniform float spoke_count = 110.0;
uniform float horizon_y = 0.46;
uniform float bottom_hud_y = 0.84;

float hash(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 d = (uv - focus) * vec2(aspect, 1.0);
	float radius = length(d);
	float cell = (atan(d.y, d.x) / 6.2831853 + 0.5) * spoke_count;
	float id = floor(cell);
	float seed = hash(id);
	float width = mix(0.05, 0.14, seed);
	float spoke = 1.0 - smoothstep(width * 0.5, width, abs(fract(cell) - 0.5));
	float travel = fract(radius * mix(1.6, 2.6, seed) - TIME * mix(1.4, 2.4, seed) + seed * 9.0);
	float dash = smoothstep(0.0, 0.12, travel) * (1.0 - smoothstep(0.4, 0.62, travel));
	float lit = step(0.45, hash(id + 17.0 * floor(TIME * 2.0 + seed * 4.0)));
	float clear_radius = central_clear_fraction * 0.5 * aspect;
	float edge = smoothstep(clear_radius, clear_radius + 0.25, radius);
	float sides = smoothstep(0.18, 0.34, abs(uv.x - 0.5));
	float below_horizon = smoothstep(horizon_y, horizon_y + 0.1, uv.y);
	float above_hud = 1.0 - smoothstep(bottom_hud_y - 0.08, bottom_hud_y, uv.y);
	float mask = edge * sides * below_horizon * above_hud;
	COLOR = vec4(line_color.rgb, line_color.a * spoke * dash * lit * mask * intensity);
}
