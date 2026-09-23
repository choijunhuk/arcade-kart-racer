shader_type sky;

// Stylised theme sky: gradient, sun disk + halo, soft static clouds, optional
// stars and a warm city glow along the horizon. No TIME use, so the radiance
// cubemap is computed once instead of every frame.

#include "res://assets/shaders/world/world_noise.gdshaderinc"

uniform vec3 top_color : source_color = vec3(0.2, 0.44, 0.84);
uniform vec3 horizon_color : source_color = vec3(0.72, 0.84, 0.95);
uniform vec3 ground_color : source_color = vec3(0.62, 0.72, 0.8);
uniform float horizon_softness = 4.0;
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.85);
uniform float sun_size = 0.035;
uniform float sun_energy = 12.0;
uniform float sun_halo = 0.6;
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.45;
uniform float cloud_opacity : hint_range(0.0, 1.0) = 0.85;
uniform float cloud_scale = 1.6;
uniform vec3 cloud_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 cloud_shade : source_color = vec3(0.7, 0.76, 0.86);
uniform float stars : hint_range(0.0, 1.0) = 0.0;
uniform vec3 glow_color : source_color = vec3(0.0);
uniform float glow_falloff = 9.0;

void sky() {
	vec3 dir = normalize(EYEDIR);
	float y = dir.y;
	float above = clamp(y, 0.0, 1.0);
	vec3 col = mix(horizon_color, top_color, 1.0 - pow(1.0 - above, horizon_softness));
	col = mix(col, ground_color, smoothstep(0.0, -0.25, y));
	col += glow_color * exp(-max(y, 0.0) * glow_falloff);

	if (y > -0.02) {
		vec2 plane = dir.xz / (y + 0.18) * cloud_scale;
		float shape = wn_fbm(plane + vec2(4.0, 1.0));
		float detail = wn_fbm(plane * 3.1 + 11.0);
		float cloud = smoothstep(1.0 - cloud_coverage, 1.0 - cloud_coverage + 0.22, shape * 0.8 + detail * 0.3);
		cloud *= smoothstep(-0.02, 0.12, y) * cloud_opacity;
		vec3 lit = mix(cloud_shade, cloud_color, smoothstep(0.35, 0.8, detail + (shape - 0.5)));
		if (LIGHT0_ENABLED) {
			float toward = max(dot(dir, LIGHT0_DIRECTION), 0.0);
			lit += sun_color * pow(toward, 8.0) * 0.35;
		}
		col = mix(col, lit, cloud);
		if (stars > 0.0) {
			vec3 cell = floor(dir * 320.0);
			float star = step(0.9965, wn_hash13(cell)) * smoothstep(0.05, 0.3, y);
			col += vec3(0.9, 0.93, 1.0) * star * stars * (1.0 - cloud) * (0.5 + wn_hash13(cell + 7.0));
		}
	}

	if (LIGHT0_ENABLED && !AT_CUBEMAP_PASS) {
		float angle = acos(clamp(dot(dir, LIGHT0_DIRECTION), -1.0, 1.0));
		float disk = 1.0 - smoothstep(sun_size * 0.85, sun_size, angle);
		col += sun_color * (disk * sun_energy + exp(-angle * 7.0) * sun_halo);
	} else if (LIGHT0_ENABLED) {
		float angle = acos(clamp(dot(dir, LIGHT0_DIRECTION), -1.0, 1.0));
		col += sun_color * exp(-angle * 7.0) * sun_halo;
	}
	COLOR = col;
}
