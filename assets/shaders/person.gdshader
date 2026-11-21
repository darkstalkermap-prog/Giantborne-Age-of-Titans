// A skinned person (P60; plan M11 §2.9): one of P59's role atlases on a variant's one surface, or a piece of gear.
//   albedo_tex  the role's albedo (512 px); a texel of a palette band holds the band's light pattern, the band's
//               colour multiplies it (P59: skin, hair, cloth and the faction's colour; "none" keeps its own:
//               leather, metal, wood, the eyes)
//   normal_tex  the tangent-space normal (256 px, the exported tangents' frame)
//   orm_tex     R the ambient occlusion, G the roughness, B the palette band (none, skin, hair, cloth, faction:
//               int(B * 5)); lossless, so the band is read texel by texel (texelFetch), the rest filtered
// The garments are single shells: culling is off (Godot turns a back face's normal toward the eye).
// Lighting: the roughness from the map; a band-less texel the map calls smooth is metal (mail, a helm, a buckle):
// metallic, its roughness held to METAL_ROUGH_MIN and its specular low, so mail under a strong sun reads as worn
// iron and not as wet plastic. The skin's specular is low and its roughness held to SKIN_ROUGH_MIN (dry skin).
// gear: a piece of gear.glb (vertex colours; alpha 1 where the faction's colour tints it), no maps.
// RigPaint's `tint` (rgb, strength in a) and `flash` (the emission) as on every actor shader (plan §2.9).
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_disable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap, repeat_disable;
uniform sampler2D band_tex : hint_default_black, filter_nearest, repeat_disable;
uniform vec3 skin_color : source_color = vec3(0.78, 0.6, 0.5);
uniform vec3 hair_color : source_color = vec3(0.17, 0.13, 0.1);
uniform vec3 cloth_color : source_color = vec3(0.43, 0.41, 0.36);
uniform vec3 faction_color : source_color = vec3(0.48, 0.16, 0.13);
uniform bool gear = false;
uniform float normal_depth : hint_range(0.0, 2.0) = 1.0;
uniform vec4 tint = vec4(1.0, 1.0, 1.0, 0.0);
uniform vec3 flash = vec3(0.0);

const float METAL_BELOW = 0.35;      // a band-less texel smoother than this is metal
const float METAL_ROUGH_MIN = 0.46;
const float SKIN_ROUGH_MIN = 0.58;
const float AO_LIGHT = 0.35;

void fragment() {
	vec3 a;
	float rough;
	float metal = 0.0;
	float spec = 0.35;
	if (gear) {
		a = mix(COLOR.rgb, faction_color, step(0.5, COLOR.a));
		rough = 0.62;
		float grey = 1.0 - smoothstep(0.02, 0.12, max(max(a.r, a.g), a.b) - min(min(a.r, a.g), a.b));
		metal = grey * step(0.18, a.g) * 0.75;   // the steel of a blade or a boss: grey and not dark
		rough = mix(rough, METAL_ROUGH_MIN, metal);
		AO = 1.0;
	} else {
		a = texture(albedo_tex, UV).rgb;
		vec4 orm = texture(orm_tex, UV);
		ivec2 size = textureSize(band_tex, 0);
		ivec2 px = clamp(ivec2(UV * vec2(size)), ivec2(0), size - 1);
		int band = int(texelFetch(band_tex, px, 0).b * 5.0);
		vec3 mul = vec3(1.0);
		if (band == 1) {
			mul = skin_color;
		} else if (band == 2) {
			mul = hair_color;
		} else if (band == 3) {
			mul = cloth_color;
		} else if (band == 4) {
			mul = faction_color;
		}
		a *= mul;
		rough = orm.g;
		if (band == 0 && rough < METAL_BELOW) {
			metal = 0.8;
			rough = max(rough, METAL_ROUGH_MIN);
			spec = 0.25;
		} else if (band == 1) {
			rough = max(rough, SKIN_ROUGH_MIN);
			spec = 0.28;
		} else if (band == 2) {
			spec = 0.3;
		}
		AO = orm.r;
		AO_LIGHT_AFFECT = AO_LIGHT;
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = normal_depth;
	}
	ALBEDO = a * mix(vec3(1.0), tint.rgb, clamp(tint.a, 0.0, 1.0));
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = spec;
	EMISSION = flash;
}
