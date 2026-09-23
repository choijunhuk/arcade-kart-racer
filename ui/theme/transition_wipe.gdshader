shader_type canvas_item;

// Slanted wipe for TransitionOverlay's Fade rect: the tweened modulate alpha
// (arriving here as COLOR.a) is the wipe progress, so the overlay keeps its
// fade contract while reading as a diagonal sweep with a turbo-orange edge.
uniform vec4 base_color : source_color = vec4(0.02, 0.025, 0.06, 1.0);
uniform vec4 edge_color : source_color = vec4(1.0, 0.46, 0.08, 1.0);
uniform float edge_width = 0.035;

void fragment() {
	float progress = COLOR.a;
	float diagonal = UV.x * 0.78 + (1.0 - UV.y) * 0.22;
	float front = progress * (1.0 + edge_width * 4.0) - edge_width * 2.0;
	float coverage = smoothstep(diagonal - 0.004, diagonal + 0.004, front);
	float stripe = 1.0 - smoothstep(0.0, edge_width, abs(front - diagonal - edge_width));
	stripe *= step(0.001, progress) * step(progress, 0.999);
	vec3 rgb = mix(base_color.rgb, edge_color.rgb, stripe);
	COLOR = vec4(rgb, clamp(max(coverage, stripe), 0.0, 1.0));
}
