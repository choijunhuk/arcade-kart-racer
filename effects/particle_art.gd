class_name ParticleArt
extends RefCounted

const TEXTURE_SIZE: int = 32

## Soft radial alpha eliminates opaque square particle silhouettes.
static func material(additive: bool = false) -> StandardMaterial3D:
	var gradient: Gradient = Gradient.new()
	gradient.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0)])
	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = TEXTURE_SIZE
	texture.height = TEXTURE_SIZE
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1, 0.5)
	var result: StandardMaterial3D = StandardMaterial3D.new()
	result.albedo_texture = texture
	result.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	result.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	result.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	result.vertex_color_use_as_albedo = true
	result.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	return result
