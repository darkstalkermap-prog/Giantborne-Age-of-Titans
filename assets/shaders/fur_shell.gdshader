// The wolf's fur shell (P64; plan M11 §2.10, §3.17 design 2, probe 6): P63's shell mesh (`wolf_shell`, the body
// decimated with its UVs and weights) drawn as LAYERS stacked copies in one surface (SkinnedWolfRig builds it once a
// process: each copy's layer in UV2.x, 0 at the skin, 1 at the fur's tips), so the shell is one draw call however
// many layers it has.
//   albedo_tex, band_tex  the wolf's own atlas and ORM map (the coat's colour: the albedo times the palette band's
//                         colour, read texel by texel as person.gdshader does)
//   fur_tex               wolf_fur.png (lossless): RG the fur's flow in the tangent frame (0.5 + 0.5 x), B its length
//                         over length_m (long on the ruff, the back, the thighs and the tail; none on the pads)
// A layer is pushed out along the normal by its share of the fur's length and combed along the flow (the tips
// further than the roots: f squared); a texel keeps a strand where a hash of its cell (cells of 1 / density of a
// UV unit) says one grows, thinning toward the tip, and nothing past the fur's own length there. Alpha scissor:
// no sorting, no blending. The roots are darker (the coat's own occlusion), the tips take the light.
// Off at the `low` graphics preset (the rig draws no shell there); RigPaint's `tint` and `flash` as every actor.
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D band_tex : hint_default_black, filter_nearest, repeat_disable;
uniform sampler2D fur_tex : hint_default_black, filter_linear, repeat_disable;
uniform vec3 skin_color : source_color = vec3(0.56, 0.52, 0.46);
uniform vec3 hair_color : source_color = vec3(0.23, 0.2, 0.19);
uniform vec3 cloth_color : source_color = vec3(0.85, 0.64, 0.23);
// The fur's full length (model metres: the dire wolf's node scale doubles it), its strands a UV unit, its comb.
uniform float length_m = 0.045;
uniform float density = 520.0;
uniform float comb = 0.55;
uniform float sag = 0.25;
uniform vec4 tint = vec4(1.0, 1.0, 1.0, 0.0);
uniform vec3 flash = vec3(0.0);

varying float v_len;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	float f = UV2.x;
	vec4 fur = textureLod(fur_tex, UV, 0.0);
	v_len = fur.b;
	vec2 flow = fur.rg * 2.0 - 1.0;
	vec3 along = TANGENT * flow.x + BINORMAL * flow.y;
	float l = length_m * fur.b;
	VERTEX += NORMAL * (l * f) + along * (l * comb * f * f) - vec3(0.0, l * sag * f * f, 0.0);
}

void fragment() {
	float f = UV2.x;
	if (f > v_len + 0.001) {
		discard;
	}
	vec2 cell = UV * density;
	vec2 id = floor(cell);
	float h = hash12(id);
	vec2 off = vec2(hash12(id + 17.0), hash12(id + 41.0)) - 0.5;
	vec2 d = fract(cell) - 0.5 - off * 0.35;
	float tip = clamp(f / max(v_len, 0.05), 0.0, 1.0);
	float r = mix(0.62, 0.12, tip) * (0.75 + 0.5 * h);
	float keep = step(length(d), r) * step(0.12, h);
	vec3 a = texture(albedo_tex, UV).rgb;
	ivec2 size = textureSize(band_tex, 0);
	ivec2 px = clamp(ivec2(UV * vec2(size)), ivec2(0), size - 1);
	int band = int(texelFetch(band_tex, px, 0).b * 5.0);
	if (band == 1) {
		a *= skin_color;
	} else if (band == 2) {
		a *= hair_color;
	} else if (band == 3) {
		a *= cloth_color;
	}
	a *= mix(0.8, 1.12, tip) * mix(0.94, 1.06, h);
	ALBEDO = a * mix(vec3(1.0), tint.rgb, clamp(tint.a, 0.0, 1.0));
	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
	EMISSION = flash;
	AO = mix(0.75, 1.0, tip);
	AO_LIGHT_AFFECT = 0.4;
	ALPHA = keep;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
