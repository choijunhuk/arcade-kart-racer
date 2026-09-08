shader_type canvas_item;
render_mode unshaded;

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float central_clear_fraction : hint_range(0.0, 1.0) = 0.4;
uniform vec4 line_color : source_color = vec4(0.55, 0.85, 1.0, 0.5);

void fragment() {
	vec2 centered = SCREEN_UV * 2.0 - 1.0;
	float central_square = max(abs(centered.x), abs(centered.y));
	if (central_square < central_clear_fraction) {
		COLOR = vec4(0.0);
	} else {
		float radius = length(centered);
		float angle = atan(centered.y, centered.x);
		float spoke = sin(angle * 42.0 + radius * 9.0 - TIME * 9.0) * 0.5 + 0.5;
		spoke = smoothstep(0.9, 1.0, spoke);
		float edge = smoothstep(central_clear_fraction, 1.1, central_square);
		float pulse = smoothstep(0.25, 1.0, fract(radius * 7.0 - TIME * 2.5));
		COLOR = vec4(line_color.rgb, line_color.a * spoke * edge * pulse * intensity);
	}
}
