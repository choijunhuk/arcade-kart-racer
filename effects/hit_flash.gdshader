shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.5;
uniform float flash_strength : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	ALBEDO = mix(albedo_color.rgb, vec3(1.0), flash_strength);
	METALLIC = metallic;
	ROUGHNESS = roughness;
	EMISSION = vec3(1.0) * flash_strength * 2.0;
}
