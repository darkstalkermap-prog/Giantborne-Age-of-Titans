// The realistic giant's skin (P42; plan M10 §2.8, decisions 11 and 12): Body_Head, Body_Torso and
// Body_Limbs. Ported from the creator lab's region-array skin shader, for the Compatibility renderer
// (desktop GL 3.3 and WebGL 2). Baked textures at a neutral tone; the look comes in as uniforms
// (GiantLook sets them from Appearance.to_look):
//   * the skin tone as a ratio to the tone the bake is drawn at (bake_tone: the default tone, so the
//     default look draws the albedo as baked); the hair colour on the scalp and the brows, the
//     beard colour on the stubble and on the skin under the beard's cards;
//   * designs from ONE sampler2DArray, chosen per body region: the vertex's region id is stored in
//     COLOR.r as (id + 0.5) / 16 and decoded with int() (rounding would be wrong); region_tattoo,
//     region_paint and region_mark hold layer * 4 + channel + 1 for each of the 16 regions, 0 for none
//     (uniform arrays take no defaults in 4.6.3 shaders, so GiantLook always fills them). Tattoos are
//     ink in the skin (one ink), the ancestry mark is tinted and may glow, war paint sits on top;
//   * scars from one RGBA layer of the same array (scar_layer, scar_on): paler, glossier, raised;
//   * the regions under the shown garments sink inside (hidden_regions, one bit per region);
//   * light_model 0 Lambert, 1 per-channel wrap (red wraps furthest), 2 wrap and a thickness-driven
//     back-light, 3 (P51, plan M11 decision 9; the default) a pre-integrated subsurface term: skin_lut, 64 x 64,
//     is the light a ring of the skin gathers through a skin's diffusion profile, of a light wrapped a little round
//     the terminator per channel (Gate A: the giant's skin is nearly flat at the profile's scale), by N.L (u) and the curvature
//     (v; curvature_tex, scaled by curvature_scale), blended over Lambert by sss_strength, with model 2's
//     back-light on the thin parts; the terminator softens and reddens where the skin curves (nose, ears,
//     lips, fingers) and the lit side keeps the albedo's colour (no screen-space scattering in this renderer);
//   * RigPaint's status tint (tint: rgb and a strength; the albedo times white.lerp(rgb, strength))
//     and hit flash (flash: the emission).
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_disable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap, repeat_disable;   // R AO, G roughness, B thickness
uniform sampler2D mask_tex : hint_default_black, filter_linear_mipmap, repeat_disable;  // R stubble, G scalp, B brows, A lips
uniform sampler2D curvature_tex : hint_default_black, filter_linear_mipmap, repeat_disable;   // P51: R curvature
uniform sampler2D skin_lut : source_color, filter_linear, repeat_disable;   // P51: the pre-integrated term
uniform sampler2DArray design_tex : hint_default_black, filter_linear_mipmap, repeat_disable;

uniform vec3 skin_tone : source_color = vec3(0.69, 0.53, 0.44);
uniform vec3 bake_tone : source_color = vec3(0.690196, 0.478431, 0.384314);   // GiantLook.BAKE_TONE: the default tone
uniform vec3 hair_color : source_color = vec3(0.29, 0.17, 0.10);
uniform vec3 beard_color : source_color = vec3(0.29, 0.17, 0.10);
uniform float stubble : hint_range(0.0, 1.0) = 0.8;
uniform float scalp_tint : hint_range(0.0, 1.0) = 1.0;
uniform float beard_tint : hint_range(0.0, 1.0) = 1.0;
uniform float brows : hint_range(0.0, 1.0) = 1.0;
uniform int region_tattoo[16];
uniform int region_paint[16];
uniform int region_mark[16];
uniform vec3 tattoo_ink : source_color = vec3(0.10, 0.18, 0.40);
uniform vec3 paint_color : source_color = vec3(0.86, 0.84, 0.78);
uniform vec3 mark_color : source_color = vec3(0.44, 0.49, 0.55);
uniform float mark_glow : hint_range(0.0, 1.0) = 0.0;
uniform int scar_layer = 0;
uniform vec4 scar_on = vec4(0.0);
uniform int scar_layer_b = 0;
uniform vec4 scar_on_b = vec4(0.0);
// P56 (plan M11 §2.6): ten scars in the two scar layers, a channel shared by scars of other regions (the packer keeps
// them apart); each channel is on only in the body regions of the worn scars on it (a bit a region; all by default).
uniform ivec4 scar_regions = ivec4(65535);
uniform ivec4 scar_regions_b = ivec4(65535);
uniform float scar_relief = 6.0;
uniform int hidden_regions = 0;
uniform float hide_shrink = 0.03;
// P53 (plan M11 §2.4, decision 7): the build sliders (brawn, girth; each -1 to 1) push the surface along its
// normal by the mesh's build weights (COLOR.g brawn, COLOR.b girth, stored as 0.5 + 0.5 w) times the index's
// build_max_m (stage-1 metres). No joint moves; at (0, 0) nothing does.
uniform vec2 build = vec2(0.0);
uniform float build_max_m = 0.0;
uniform int light_model = 3;
uniform float curvature_scale = 1.0;
uniform float tone_shoulder : hint_range(0.0, 1.0) = 0.4;
uniform float tone_chroma : hint_range(0.0, 1.5) = 1.0;
uniform float tone_resat : hint_range(0.0, 1.0) = 1.0;
const float TONE_RESAT_MAX = 1.25;   // 1 / SKIN_GRADE's saturation (0.8): the bake's own saturation back
uniform float sss_strength : hint_range(0.0, 1.0) = 1.0;
// How far the light wraps round, per channel (red scatters furthest). The M10 gate (OR-1) eased the tint from
// (0.42, 0.20, 0.13): a surface 90 degrees from a white light took 0.30 / 0.17 / 0.12 of it, a red band along
// every terminator; now 0.26 / 0.20 / 0.17.
uniform vec3 wrap = vec3(0.36, 0.25, 0.20);
uniform vec3 sss_color : source_color = vec3(0.90, 0.28, 0.16);
uniform float transmission = 0.5;
uniform float rough_scale = 1.25;
uniform float normal_detail = 0.6;
const float TSIGN_FLIP = 1.0;
uniform vec4 tint = vec4(1.0, 1.0, 1.0, 0.0);
uniform vec3 flash = vec3(0.0);

varying float v_thin;
varying float v_curv;
varying flat int v_region;
varying float v_tsign;
varying float v_down;

#include "res://assets/shaders/giant_first_person.gdshaderinc"
varying vec3 v_fp_pos;
varying flat float v_fp_on;

void vertex() {
	v_region = clamp(int(COLOR.r * 16.0), 0, 15);
	v_tsign = COLOR.a * 2.0 - 1.0;
	v_down = -(MODEL_MATRIX * vec4(NORMAL, 0.0)).y;
	v_fp_pos = VERTEX;
	VERTEX += NORMAL * dot(COLOR.gb * 2.0 - 1.0, build) * build_max_m;   // P53: the build sliders
	v_fp_on = fp_in_head(fp_camera_mesh(MODEL_MATRIX, CAMERA_POSITION_WORLD)) * fp_region_shown(v_region);
	if (((hidden_regions >> v_region) & 1) == 1) {
		VERTEX -= NORMAL * hide_shrink;
	}
}

const vec2 SCAR_CORE = vec2(0.34, 0.72);   // the third look lane: the scar's coverage drawn as healed tissue
const float SCAR_RIM_DARK = 0.12;           // ... and its rim's darkening
const float BEARD_SKIN_TINT = 1.6;          // the fifth look lane: the beard's shade on the skin under it, this much fuller
const float SCALP_SHADE = 0.9;              // the fourth look lane: the scalp under a style as its hair (0.8 drew the gaps between the locks dark)
const float NECK_SHADOW_SOFT = 0.6;         // the third look lane: the share of a shadow on the neck left out
const float PAINT_SMEAR_UV = 0.014;         // the third look lane: how far war paint's border wanders (UV)

// Smooth 3D value noise in [0, 1] (the third look lane: war paint's strokes, pores and edges, in the rest position).
float hash3(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}
float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

vec4 channel_mask(int ch) {
	return vec4(ch == 0 ? 1.0 : 0.0, ch == 1 ? 1.0 : 0.0, ch == 2 ? 1.0 : 0.0, ch == 3 ? 1.0 : 0.0);
}

// The coverage of the design `code` (layer * 4 + channel + 1; 0 = none) at `uv`.
float design_coverage(int code, vec2 uv) {
	if (code <= 0) {
		return 0.0;
	}
	int d = code - 1;
	int layer = d / 4;
	return clamp(dot(texture(design_tex, vec3(uv, float(layer))), channel_mask(d - layer * 4)), 0.0, 1.0);
}

// A scar layer's channels on in this texel's region (P56): `on` gated by each channel's region bits.
vec4 scar_gate(vec4 on, ivec4 regions) {
	return on * vec4(float((regions.x >> v_region) & 1), float((regions.y >> v_region) & 1),
		float((regions.z >> v_region) & 1), float((regions.w >> v_region) & 1));
}

// The scars of one RGBA layer that `on` picks: their coverage, and the slope of their height for the relief.
float scar_coverage(float layer, vec4 on, vec2 uv, out vec2 slope) {
	vec2 px = vec2(1.0 / float(textureSize(design_tex, 0).x), 1.0 / float(textureSize(design_tex, 0).y));
	float hx = dot(texture(design_tex, vec3(uv + vec2(px.x, 0.0), layer)), on)
		- dot(texture(design_tex, vec3(uv - vec2(px.x, 0.0), layer)), on);
	float hy = dot(texture(design_tex, vec3(uv + vec2(0.0, px.y), layer)), on)
		- dot(texture(design_tex, vec3(uv - vec2(0.0, px.y), layer)), on);
	slope = vec2(hx, -hy);
	return clamp(dot(texture(design_tex, vec3(uv, layer)), on), 0.0, 1.0);
}

// A tone on the baked albedo (P51): the albedo is graded to the approved renders' pale default (tools/giant/kit/
// pack.py SKIN_GRADE: less saturated, lighter), so the tones' ratios to the default, made for the M10 bake, would
// draw the pale tones near white and the deep ones grey. The ratio's lightness is eased above the default
// (tone_shoulder), its hue kept at tone_chroma, and a darker tone takes back the albedo's saturation the grade took
// (tone_resat x its darkness). The default tone (ratio 1) draws the albedo exactly. GiantLook.drawn_tone mirrors it.
vec3 tone_scaled(vec3 albedo, vec3 ratio) {
	vec3 w = vec3(0.2126, 0.7152, 0.0722);
	float lr = max(dot(ratio, w), 1e-4);
	vec3 hue = mix(vec3(1.0), ratio / lr, tone_chroma);
	float lr2 = lr > 1.0 ? 1.0 + (lr - 1.0) * tone_shoulder : lr;
	float la = dot(albedo, w);
	vec3 a = la + (albedo - la) * mix(1.0, TONE_RESAT_MAX, clamp(abs(1.0 - lr) * 2.0, 0.0, 1.0) * tone_resat);
	return max(a, vec3(0.0)) * lr2 * hue;
}

void fragment() {
	if (fp_shoulders_hidden(v_fp_pos, v_fp_on, FRAGCOORD.xy)) {
		discard;   // first person: the limbs fade out towards the shoulders (the include's header)
	}
	// P56: the binormal from the normal, the tangent and the tangent's sign the mesh carries in COLOR.a: the renderer's
	// blend shapes (the face keys) lose the sign (the binormal went to zero at a key's +1: a black quad between the brows)
	BINORMAL = normalize(cross(NORMAL, TANGENT)) * (v_tsign < 0.0 ? -1.0 : 1.0) * TSIGN_FLIP;
	vec3 base = tone_scaled(texture(albedo_tex, UV).rgb, skin_tone / max(bake_tone, vec3(0.01)));
	vec4 orm = texture(orm_tex, UV);
	vec4 m = texture(mask_tex, UV);
	// the hair's colours on the skin: stubble and the skin under the beard (the beard's), the scalp under
	// a hairstyle and the brows (the hair's)
	// the third look lane: stubble is the beard's hair cut at the skin - fine dark points of its colour over the skin,
	// not a tint (the skin times the beard's colour read as an orange-red stain)
	float stub = clamp(m.r * stubble, 0.0, 1.0);
	if (stub > 0.0) {
		float dots = smoothstep(0.35, 0.8, vnoise(v_fp_pos * 1400.0)) * 0.6 + smoothstep(0.3, 0.7, vnoise(v_fp_pos * 380.0)) * 0.4;
		vec3 cut = mix(beard_color * 0.7, base * 0.5, 0.35);
		// (under a beard's cards the skin keeps the beard's shade, so no skin shows between them)
		float under = clamp(beard_tint, 0.0, 1.0);
		base = mix(base, cut, stub * mix(0.18 + 0.5 * dots, 0.75, under));
	}
	base = mix(base, hair_color * SCALP_SHADE, clamp(m.g * scalp_tint, 0.0, 1.0));
	// (the fifth look lane: as the scalp's shade, and fuller - the skin between a short beard's strands read grey-pink)
	base = mix(base, beard_color * SCALP_SHADE, clamp(smoothstep(0.2, 0.7, m.r) * beard_tint * BEARD_SKIN_TINT, 0.0, 1.0));
	base = mix(base, hair_color * 0.9, clamp(m.b * brows, 0.0, 1.0) * 0.85);
	// the designs of this texel's body region: tattoo ink in the skin, the line's mark, war paint on top
	float tattoo = design_coverage(region_tattoo[v_region], UV);
	base = mix(base, base * mix(vec3(1.0), tattoo_ink * 2.0, 0.85), tattoo * 0.92);
	float mark = design_coverage(region_mark[v_region], UV);
	base = mix(base, base * mix(vec3(1.0), mark_color * 2.0, 0.85), mark * 0.9);
	// the third look lane: war paint is a pigment smeared on by hand, not a flat mask - semi-opaque, the skin showing
	// through at the pores and along the strokes, its borders uneven and smeared (the design's soft edge cut at a
	// noisy level), its tone varying along the strokes; matte (below)
	float paint = 0.0;
	vec3 q = v_fp_pos;
	// (sampled a little off its place by a smooth noise: the border wanders as a hand smears it)
	vec2 smear = (vec2(vnoise(q * 20.0), vnoise(q * 20.0 + 7.31)) - 0.5) * PAINT_SMEAR_UV;
	float paint_raw = design_coverage(region_paint[v_region], UV + smear);
	if (paint_raw > 0.0) {
		float edge_n = vnoise(q * 34.0) * 0.6 + vnoise(q * 105.0) * 0.4;
		float streak = vnoise(vec3(q.x * 12.0, q.y * 150.0, q.z * 28.0));
		float pores = vnoise(q * 480.0);
		float cover = smoothstep(0.08 + 0.55 * edge_n, 0.38 + 0.55 * edge_n, paint_raw);
		paint = cover * mix(0.5, 0.84, smoothstep(0.2, 0.8, streak)) * mix(0.6, 1.0, smoothstep(0.25, 0.6, pores));
		vec3 pigment = paint_color * mix(0.84, 1.04, streak);
		base = mix(base, pigment, paint);
	}
	// scars: paler, glossier, raised (one RGBA layer of the design array)
	vec3 nm = texture(normal_tex, UV).rgb * 2.0 - 1.0;
	nm.xy *= normal_detail;   // the baked relief, eased: the low sun drew the forehead's lines as ridges
	float sc = 0.0;
	vec2 relief = vec2(0.0);
	vec4 on_a = scar_gate(scar_on, scar_regions);
	vec4 on_b = scar_gate(scar_on_b, scar_regions_b);
	if (dot(on_a, on_a) > 0.0) {
		sc = scar_coverage(float(scar_layer), on_a, UV, relief);
	}
	if (dot(on_b, on_b) > 0.0) {   // the fifth and sixth scars: a second layer (P46)
		vec2 relief_b = vec2(0.0);
		float sb = scar_coverage(float(scar_layer_b), on_b, UV, relief_b);
		sc = max(sc, sb);
		relief += relief_b;
	}
	if (sc > 0.0 || dot(relief, relief) > 0.0) {
		// the second look lane: a healed scar is raised a little, not gouged (at half the relief its feathered edges
		// still cut dark grooves beside every scar); the slope is limited so a steep edge cannot turn the normal over
		nm.xy -= clamp(relief * scar_relief * 0.16, vec2(-0.35), vec2(0.35));
		// healed tissue: paler and pinker than the skin around it, whatever the tone (P46: the floor's
		// scars did not read at the game camera); the second look lane: less saturated, not oranger (the skin's
		// own colour times 1.5 in red read as an orange stripe), and lighter on dark skin than on pale
		// the third look lane: narrower (the feathered coverage's middle) and gentler - a little paler and pinker than
		// the skin round it, with a thin darker rim where the tissue puckers (it read as a white paint smear)
		float lum = dot(base, vec3(0.2126, 0.7152, 0.0722));
		vec3 healed = mix(base, vec3(lum), 0.3) * vec3(1.2, 1.06, 1.09) + vec3(0.035, 0.012, 0.02);
		float scar_core = smoothstep(SCAR_CORE.x, SCAR_CORE.y, sc);
		float scar_rim = smoothstep(0.12, 0.32, sc) * (1.0 - smoothstep(SCAR_CORE.x, SCAR_CORE.y, sc));
		base = mix(base, healed, scar_core) * (1.0 - SCAR_RIM_DARK * scar_rim);
		sc = scar_core;
	}
	ALBEDO = base * mix(vec3(1.0), tint.rgb, clamp(tint.a, 0.0, 1.0));
	NORMAL_MAP = normalize(nm) * 0.5 + 0.5;
	ROUGHNESS = clamp(mix(mix(orm.g * rough_scale, 0.3, sc * 0.6), 0.9, paint), 0.0, 1.0);
	SPECULAR = mix(0.35, 0.2, paint);
	AO = orm.r;
	AO_LIGHT_AFFECT = 0.25;
	EMISSION = flash + mark_color * mark_glow * mark;
	v_thin = clamp(1.0 - orm.b, 0.0, 1.0);   // the bake stores inside-AO: thick parts are white
	v_curv = clamp(texture(curvature_tex, UV).r * curvature_scale, 0.0, 1.0);
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	// the third look lane: the neck and the jaw's underside take the jaw's shadow softly (the shadow proxy has no face keys and a coarse jaw:
	// its hard shadow read as a dark patch under every bare jaw, a wedge at the chin key's -1)
	float soft = v_region == 2 ? NECK_SHADOW_SOFT : (v_region == 1 ? NECK_SHADOW_SOFT * smoothstep(0.0, 0.5, v_down) : 0.0);
	float att = mix(ATTENUATION, 1.0, soft);
	vec3 diff;
	if (light_model == 0) {
		diff = vec3(clamp(ndl, 0.0, 1.0));
	} else if (light_model == 3) {
		vec3 pre = texture(skin_lut, vec2(clamp(ndl * 0.5 + 0.5, 0.0, 1.0), v_curv)).rgb;
		diff = mix(vec3(clamp(ndl, 0.0, 1.0)), pre, sss_strength);
	} else {
		diff = clamp((vec3(ndl) + wrap) / (1.0 + wrap), vec3(0.0), vec3(1.0));
	}
	DIFFUSE_LIGHT += diff * att * LIGHT_COLOR / PI;
	if (light_model >= 2) {
		float back = pow(clamp(dot(VIEW, -LIGHT), 0.0, 1.0), 4.0);
		float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
		DIFFUSE_LIGHT += sss_color * transmission * v_thin * (back * 0.8 + rim * back * 0.6) * LIGHT_COLOR / PI;
	}
	vec3 h = normalize(VIEW + LIGHT);
	float ndh = clamp(dot(NORMAL, h), 0.0, 1.0);
	float r = max(ROUGHNESS, 0.08);
	float a2 = r * r * r * r;
	float d = a2 / (PI * pow(ndh * ndh * (a2 - 1.0) + 1.0, 2.0));
	float f = 0.028 + 0.972 * pow(1.0 - clamp(dot(h, VIEW), 0.0, 1.0), 5.0);
	SPECULAR_LIGHT += vec3(d * f * 0.25) * clamp(ndl, 0.0, 1.0) * att * LIGHT_COLOR / PI;
}
