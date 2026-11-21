// The people as a crowd (P60; plan M11 §2.9, probe 8): P59's crowd-pose and far meshes (and the gear) drawn as
// MultiMesh instances, one draw call per role, pose and level. Per instance (CrowdRenderer):
//   INSTANCE_CUSTOM.x  the palette row of the skin, hair and cloth (palette_tex's columns 0-2)
//   INSTANCE_CUSTOM.y  the hit flash's strength (0-1; the emission flash_color x strength x FLASH, in the
//                      albedo's space as RigPaint's)
//   INSTANCE_CUSTOM.z  the faction's row (palette_tex's column 3)
//   COLOR (the instance colour)  the status tint's albedo multiplier (rgb; white: none); alpha 1
// palette_tex: 4 x N texels, sRGB, read texel by texel. The ORM map's band as person.gdshader reads it; no normal
// map (a crowd member is a few dozen pixels tall) and the same lighting rules (metal, skin, roughness).
// gear: a piece of gear.glb (its vertex colours; alpha 1 where the faction's colour tints it).
// P62: the plate metal as person.gdshader's (METAL_ROUGH_MIN, PLATE_METAL, PLATE_DARKEN) and its `strands` (the
// albedo's alpha cut at STRAND_CUT, for a creature's cards drawn as a crowd).
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap, repeat_disable;
uniform sampler2D band_tex : hint_default_black, filter_nearest, repeat_disable;
uniform sampler2D palette_tex : source_color, filter_nearest, repeat_disable;
uniform bool gear = false;
uniform bool strands = false;
uniform vec3 flash_color = vec3(1.0, 0.95, 0.85);

const float FLASH = 0.85;
const float METAL_BELOW = 0.35;
const float METAL_ROUGH_MIN = 0.38;
const float PLATE_METAL = 0.7;
const float PLATE_DARKEN = 0.92;
const float STRAND_CUT = 0.5;
const float SKIN_ROUGH_MIN = 0.58;
const float AO_LIGHT = 0.35;

varying flat vec4 v_custom;
varying vec3 v_tint;
varying vec4 v_color;

void vertex() {
	v_custom = INSTANCE_CUSTOM;
	v_tint = COLOR.rgb;
	v_color = COLOR;
}

vec3 palette(int column, int row) {
	ivec2 size = textureSize(palette_tex, 0);
	return texelFetch(palette_tex, ivec2(column, clamp(row, 0, size.y - 1)), 0).rgb;
}

void fragment() {
	int row = int(v_custom.x + 0.5);
	int frow = int(v_custom.z + 0.5);
	vec3 a;
	float rough;
	float metal = 0.0;
	float spec = 0.35;
	float alpha = 1.0;
	if (gear) {
		// the vertex colour already carries the instance's tint (COLOR = vertex x instance)
		a = mix(v_color.rgb, palette(3, frow) * v_tint, step(0.5, v_color.a));
		float grey = 1.0 - smoothstep(0.02, 0.12, max(max(a.r, a.g), a.b) - min(min(a.r, a.g), a.b));
		metal = grey * step(0.18, a.g) * 0.75;
		rough = mix(0.62, METAL_ROUGH_MIN, metal);
	} else {
		vec4 at = texture(albedo_tex, UV);
		a = at.rgb;
		alpha = strands ? at.a : 1.0;
		vec4 orm = texture(orm_tex, UV);
		ivec2 size = textureSize(band_tex, 0);
		ivec2 px = clamp(ivec2(UV * vec2(size)), ivec2(0), size - 1);
		int band = int(texelFetch(band_tex, px, 0).b * 5.0);
		if (band >= 1 && band <= 3) {
			a *= palette(band - 1, row);
		} else if (band == 4) {
			a *= palette(3, frow);
		}
		a *= v_tint;
		rough = orm.g;
		if (band == 0 && rough < 0.5 && UV.x > 0.5 && UV.y > 0.5 && UV.y < 0.875) {
			metal = 0.8;                       // the mail (person.gdshader's MAIL_RECT), its rings too small here
			rough = 0.5;
			a *= 0.85;
		} else if (band == 0 && rough < METAL_BELOW) {
			metal = PLATE_METAL;
			rough = max(rough, METAL_ROUGH_MIN);
			a *= PLATE_DARKEN;
			spec = 0.25;
		} else if (band == 1) {
			rough = max(rough, SKIN_ROUGH_MIN);
			spec = 0.28;
		}
		AO = orm.r;
		AO_LIGHT_AFFECT = AO_LIGHT;
	}
	ALBEDO = a;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = spec;
	EMISSION = flash_color * clamp(v_custom.y, 0.0, 1.0) * FLASH;
	ALPHA = alpha;
	ALPHA_SCISSOR_THRESHOLD = STRAND_CUT;
}
