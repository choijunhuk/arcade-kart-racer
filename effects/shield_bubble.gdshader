shader_type spatial;
render_mode blend_add, depth_draw_never, cull_back;
uniform vec4 shield_color : source_color = vec4(0.12, 0.8, 1.0, 0.55);
uniform float rim_power = 2.5;
void fragment() {
	float rim = pow(1.0 - max(dot(NORMAL, VIEW), 0.0), rim_power);
	ALBEDO = shield_color.rgb;
	EMISSION = shield_color.rgb * rim;
	ALPHA = shield_color.a * (0.08 + rim);
}
