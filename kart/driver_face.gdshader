shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Driver head with a painted SDF face (Phase 19 kart-soft). The face is
// projected onto the front (-Z) of the head in head-radius units, so it needs
// no UVs: big glossy eyes with highlights, brows, a hair fringe under the
// helmet brow, blush and one of four mouths. Eyes blink on TIME with a
// per-driver offset. Far away (view distance) the small details fade out.

uniform vec4 skin_tone : source_color = vec4(0.96, 0.78, 0.64, 1.0);
uniform vec4 eye_color : source_color = vec4(0.28, 0.48, 0.9, 1.0);
uniform vec4 hair_color : source_color = vec4(0.32, 0.2, 0.12, 1.0);
// 0 cheerful, 1 confident, 2 fierce, 3 calm.
uniform int expression = 0;
uniform float blink_offset = 0.0;
uniform float head_radius = 0.19;
uniform float detail_distance = 40.0;

varying vec3 face_p;

void vertex() {
	face_p = VERTEX / head_radius;
}

float sd_ellipse(vec2 p, vec2 r) {
	float k0 = length(p / r);
	float k1 = length(p / (r * r));
	return k0 * (k0 - 1.0) / max(k1, 1e-4);
}

float sd_segment(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

// Distance to y = y0 + k * (x - x0)^2 for x in [x_min, x_max] (curved strokes).
float sd_curve(vec2 p, float y0, float k, float x0, float x_min, float x_max) {
	float x = clamp(p.x, x_min, x_max);
	vec2 a = vec2(x, y0 + k * (x - x0) * (x - x0));
	float slope = 2.0 * k * (x - x0);
	vec2 n = normalize(vec2(-slope, 1.0));
	float along = abs(p.x - x) > 0.0 ? length(p - a) : abs(dot(p - a, n));
	return along;
}

float cover(float d) {
	float w = max(fwidth(d), 1e-4) * 0.8;
	return 1.0 - smoothstep(-w, w, d);
}

vec2 brow_heights(float side) {
	if (expression == 1) {
		return side < 0.0 ? vec2(0.05, 0.07) : vec2(0.0, -0.01);
	} else if (expression == 2) {
		return vec2(-0.05, 0.05);
	} else if (expression == 3) {
		return vec2(0.0, -0.025);
	}
	return vec2(0.03, 0.01);
}

// Eye layer: returns rgb in .rgb and coverage in .a; `glint` gets highlights.
vec4 eye(vec2 p, float side, float open, float detail, out float glint) {
	glint = 0.0;
	vec2 q = p - vec2(side * 0.36, 0.02);
	float height = 0.2 * max(open, 0.05);
	float d = sd_ellipse(q, vec2(0.14, height));
	if (expression == 2) {
		d = max(d, q.y - (0.07 - 0.35 * (q.x * side) * -1.0 - 0.06));
	} else if (expression == 3) {
		d = max(d, q.y - 0.06);
	}
	vec3 color = vec3(0.98);
	vec2 iris_c = vec2(-side * 0.014, -0.025);
	float iris = max(length(q - iris_c) - 0.118, d);
	vec3 iris_rgb = mix(eye_color.rgb * 0.35, eye_color.rgb * 1.15, smoothstep(0.08, -0.1, q.y));
	color = mix(color, iris_rgb, cover(iris));
	color = mix(color, vec3(0.03, 0.03, 0.05), cover(max(length(q - iris_c) - 0.058, d)));
	float big = max(length(q - vec2(-0.04, 0.06)) - 0.04, d);
	float small = max(length(q - vec2(0.04, -0.07)) - 0.02, d);
	glint = max(cover(big), cover(small) * detail);
	color = mix(color, vec3(1.0), glint);
	float lash = abs(d) - mix(0.006, 0.022, smoothstep(-0.04, 0.08, q.y));
	color = mix(color, vec3(0.06, 0.04, 0.05), cover(lash));
	float coverage = cover(d - 0.02);
	if (open < 0.2) {
		float closed = sd_curve(q, 0.0, -2.0, 0.0, -0.13, 0.13) - 0.02;
		return vec4(vec3(0.08, 0.05, 0.06), cover(closed));
	}
	return vec4(color, coverage);
}

vec4 mouth(vec2 p) {
	vec3 line_rgb = vec3(0.3, 0.1, 0.1);
	if (expression == 0) {
		float d = max(sd_ellipse(p - vec2(0.0, -0.3), vec2(0.17, 0.15)), p.y + 0.3);
		float tongue = max(sd_ellipse(p - vec2(0.0, -0.44), vec2(0.09, 0.05)), d);
		vec3 rgb = mix(vec3(0.36, 0.07, 0.1), vec3(0.95, 0.45, 0.5), cover(tongue));
		rgb = mix(rgb, line_rgb * 0.6, cover(abs(d) - 0.012));
		return vec4(rgb, cover(d - 0.012));
	} else if (expression == 1) {
		float d = sd_curve(p, -0.37, 2.4, -0.04, -0.13, 0.16) - 0.022;
		return vec4(line_rgb, cover(d));
	} else if (expression == 2) {
		vec2 q = abs(p - vec2(0.0, -0.36)) - vec2(0.12, 0.02);
		float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - 0.045;
		vec3 rgb = mix(vec3(1.0), line_rgb, cover(abs(p.y + 0.36) - 0.008));
		rgb = mix(rgb, line_rgb * 0.6, cover(abs(d) - 0.014));
		return vec4(rgb, cover(d - 0.014));
	}
	float d = sd_curve(p, -0.37, 3.0, 0.0, -0.09, 0.09) - 0.02;
	return vec4(line_rgb, cover(d));
}

void fragment() {
	vec2 p = face_p.xy;
	float facing = smoothstep(0.15, 0.45, -face_p.z);
	float detail = 1.0 - smoothstep(detail_distance, detail_distance * 1.5, length(VERTEX));
	float cycle = mod(TIME + blink_offset, 4.3);
	float open = smoothstep(0.02, 0.09, abs(cycle - 0.1));
	vec3 color = skin_tone.rgb;
	float blush = 1.0 - smoothstep(-0.02, 0.05, sd_ellipse(vec2(abs(p.x), p.y) - vec2(0.54, -0.17), vec2(0.12, 0.07)));
	color = mix(color, vec3(1.0, 0.45, 0.5), blush * 0.35 * facing * detail);
	float nose = 1.0 - smoothstep(-0.01, 0.03, sd_ellipse(p - vec2(0.0, -0.13), vec2(0.035, 0.025)));
	color = mix(color, skin_tone.rgb * 0.78, nose * facing * detail);
	float fringe = p.y - (0.33 + 0.09 * abs(sin(p.x * 7.0 + 0.6)));
	vec3 hair = hair_color.rgb * mix(0.8, 1.15, smoothstep(0.35, 0.6, p.y));
	color = mix(color, hair, cover(-fringe) * smoothstep(-0.1, 0.2, -face_p.z));
	float glint_sum = 0.0;
	for (int i = 0; i < 2; i++) {
		float side = i == 0 ? -1.0 : 1.0;
		vec2 hb = brow_heights(side);
		float brow = sd_segment(p, vec2(side * 0.22, 0.26 + hb.x), vec2(side * 0.48, 0.27 + hb.y)) - 0.026;
		color = mix(color, hair_color.rgb * 0.5, cover(brow) * facing);
		float glint;
		vec4 e = eye(p, side, open * (expression == 3 ? 0.75 : 1.0), detail, glint);
		color = mix(color, e.rgb, e.a * facing);
		glint_sum += glint * e.a * facing;
	}
	vec4 m = mouth(p);
	color = mix(color, m.rgb, m.a * facing);
	ALBEDO = color;
	ROUGHNESS = mix(0.6, 0.12, glint_sum);
	SPECULAR = 0.35;
	RIM = 0.25;
	RIM_TINT = 0.5;
	EMISSION = vec3(glint_sum * 0.35) + skin_tone.rgb * 0.05;
}
