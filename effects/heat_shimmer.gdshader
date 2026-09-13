shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, unshaded, shadows_disabled;

// Screen-reading distortion plane for the boost exhaust (Phase 17b item 3).
// Godot 4 requires an explicit hint_screen_texture uniform; there is no
// built-in SCREEN_TEXTURE sampler as in Godot 3.
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform float distortion_strength : hint_range(0.0, 0.05) = 0.014;
uniform float scroll_speed : hint_range(0.0, 10.0) = 4.0;
uniform float intensity : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 offset = vec2(
		sin(UV.y * 18.0 + TIME * scroll_speed),
		cos(UV.x * 14.0 + TIME * scroll_speed * 1.3)
	) * distortion_strength * intensity;
	vec3 distorted = textureLod(screen_texture, SCREEN_UV + offset, 0.0).rgb;
	ALBEDO = distorted;
	ALPHA = intensity * 0.5;
}
