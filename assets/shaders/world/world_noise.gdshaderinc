// Shared procedural helpers for the world shaders (original, no textures).

float wn_hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float wn_hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float wn_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(wn_hash12(i), wn_hash12(i + vec2(1.0, 0.0)), u.x),
		mix(wn_hash12(i + vec2(0.0, 1.0)), wn_hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

float wn_fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int octave = 0; octave < 4; octave++) {
		value += amplitude * wn_noise(p);
		p = p * 2.03 + vec2(17.1, 9.2);
		amplitude *= 0.5;
	}
	return value;
}

// Anti-aliased band: 1 inside |x - centre| < half_width, softened by one pixel.
float wn_band(float x, float centre, float half_width, float pixel) {
	return 1.0 - smoothstep(half_width - pixel, half_width + pixel, abs(x - centre));
}

// Screen-space bump (Mikkelsen, unparametrized surfaces): no tangents needed.
// `height` is in metres, `pos` is VERTEX (view space), `normal` the view normal.
vec3 wn_bump(vec3 normal, vec3 pos, float height) {
	vec3 dpdx = dFdx(pos);
	vec3 dpdy = dFdy(pos);
	vec3 r1 = cross(dpdy, normal);
	vec3 r2 = cross(normal, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dFdx(height) * r1 + dFdy(height) * r2);
	return normalize(abs(det) * normal - grad);
}
