shader_type spatial;
render_mode blend_add, depth_draw_never, cull_back, unshaded, shadows_disabled;

// Aegis shield: fresnel rim, slow scan bands, and a hit ripple ring that
// sweeps across the sphere from `ripple_dir` as `ripple` runs 1 -> 0.
uniform vec4 shield_color : source_color = vec4(0.12, 0.8, 1.0, 0.55);
uniform float rim_power = 2.5;
uniform float ripple : hint_range(0.0, 1.0) = 0.0;
uniform vec3 ripple_dir = vec3(0.0, 0.0, -1.0);

varying vec3 sphere_normal;

void vertex() {
	sphere_normal = normalize(VERTEX);
}

void fragment() {
	float rim = pow(1.0 - max(dot(NORMAL, VIEW), 0.0), rim_power);
	float bands = smoothstep(0.82, 1.0, sin(sphere_normal.y * 16.0 - TIME * 2.5) * 0.5 + 0.5);
	float angle = acos(clamp(dot(sphere_normal, normalize(ripple_dir)), -1.0, 1.0));
	float front = (1.0 - ripple) * 3.14159;
	float wave = ripple * (1.0 - smoothstep(0.0, 0.35, abs(angle - front)));
	ALBEDO = mix(shield_color.rgb, vec3(1.0), wave * 0.6);
	ALPHA = clamp(shield_color.a * (0.05 + rim + bands * (0.12 + rim * 0.5) + wave * 1.6), 0.0, 1.0);
}
