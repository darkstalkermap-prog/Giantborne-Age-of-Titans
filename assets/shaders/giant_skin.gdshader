// The realistic giant's skin (P42; plan M10 §2.8, decisions 11 and 12): Body_Head, Body_Torso and
// Body_Limbs. Ported from the creator lab's region-array skin shader, for the Compatibility renderer
// (desktop GL 3.3 and WebGL 2). Baked textures at a neutral tone; the look comes in as uniforms
// (GiantLook sets them from Appearance.to_look):
//   * the skin tone as a ratio to the bake's tone; the hair colour on the scalp and the brows, the
//     beard colour on the stubble and on the skin under the beard's cards;
//   * designs from ONE sampler2DArray, chosen per body region: the vertex's region id is stored in
//     COLOR.r as (id + 0.5) / 16 and decoded with int() (rounding would be wrong); region_tattoo,
//     region_paint and region_mark hold layer * 4 + channel + 1 for each of the 16 regions, 0 for none
//     (uniform arrays take no defaults in 4.6.3 shaders, so GiantLook always fills them). Tattoos are
//     ink in the skin (one ink), the ancestry mark is tinted and may glow, war paint sits on top;
//   * scars from one RGBA layer of the same array (scar_layer, scar_on): paler, glossier, raised;
//   * the regions under the shown garments sink inside (hidden_regions, one bit per region);
//   * light_model 0 Lambert, 1 per-channel wrap (red wraps furthest), 2 wrap and a thickness-driven
//     back-light (no subsurface scattering);
//   * RigPaint's status tint (tint: rgb and a strength; the albedo times white.lerp(rgb, strength))
//     and hit flash (flash: the emission).
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_disable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap, repeat_disable;   // R AO, G roughness, B thickness
uniform sampler2D mask_tex : hint_default_black, filter_linear_mipmap, repeat_disable;  // R stubble, G scalp, B brows, A lips
uniform sampler2DArray design_tex : hint_default_black, filter_linear_mipmap, repeat_disable;

uniform vec3 skin_tone : source_color = vec3(0.69, 0.53, 0.44);
uniform vec3 bake_tone : source_color = vec3(0.69, 0.53, 0.44);
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
uniform float scar_relief = 6.0;
uniform int hidden_regions = 0;
uniform float hide_shrink = 0.03;
uniform int light_model = 2;
uniform vec3 wrap = vec3(0.42, 0.20, 0.13);
uniform vec3 sss_color : source_color = vec3(0.90, 0.28, 0.16);
uniform float transmission = 0.5;
uniform float rough_scale = 1.25;
uniform vec4 tint = vec4(1.0, 1.0, 1.0, 0.0);
uniform vec3 flash = vec3(0.0);

varying float v_thin;
varying flat int v_region;

void vertex() {
	v_region = clamp(int(COLOR.r * 16.0), 0, 15);
	if (((hidden_regions >> v_region) & 1) == 1) {
		VERTEX -= NORMAL * hide_shrink;
	}
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

void fragment() {
	vec3 base = texture(albedo_tex, UV).rgb * (skin_tone / max(bake_tone, vec3(0.01)));
	vec4 orm = texture(orm_tex, UV);
	vec4 m = texture(mask_tex, UV);
	// the hair's colours on the skin: stubble and the skin under the beard (the beard's), the scalp under
	// a hairstyle and the brows (the hair's)
	base = mix(base, base * mix(vec3(1.0), beard_color * 2.2, 0.85), clamp(m.r * stubble, 0.0, 1.0) * 0.75);
	base = mix(base, hair_color * 0.55, clamp(m.g * scalp_tint, 0.0, 1.0));
	base = mix(base, beard_color * 0.55, clamp(smoothstep(0.2, 0.7, m.r) * beard_tint, 0.0, 1.0));
	base = mix(base, hair_color * 0.9, clamp(m.b * brows, 0.0, 1.0) * 0.85);
	// the designs of this texel's body region: tattoo ink in the skin, the line's mark, war paint on top
	float tattoo = design_coverage(region_tattoo[v_region], UV);
	base = mix(base, base * mix(vec3(1.0), tattoo_ink * 2.0, 0.85), tattoo * 0.92);
	float mark = design_coverage(region_mark[v_region], UV);
	base = mix(base, base * mix(vec3(1.0), mark_color * 2.0, 0.85), mark * 0.9);
	float paint = design_coverage(region_paint[v_region], UV);
	base = mix(base, paint_color, paint * 0.92);
	// scars: paler, glossier, raised (one RGBA layer of the design array)
	vec3 nm = texture(normal_tex, UV).rgb * 2.0 - 1.0;
	float sc = 0.0;
	if (dot(scar_on, scar_on) > 0.0) {
		float sl = float(scar_layer);
		sc = clamp(dot(texture(design_tex, vec3(UV, sl)), scar_on), 0.0, 1.0);
		vec2 px = vec2(1.0 / float(textureSize(design_tex, 0).x), 1.0 / float(textureSize(design_tex, 0).y));
		float hx = dot(texture(design_tex, vec3(UV + vec2(px.x, 0.0), sl)), scar_on)
			- dot(texture(design_tex, vec3(UV - vec2(px.x, 0.0), sl)), scar_on);
		float hy = dot(texture(design_tex, vec3(UV + vec2(0.0, px.y), sl)), scar_on)
			- dot(texture(design_tex, vec3(UV - vec2(0.0, px.y), sl)), scar_on);
		nm.xy -= vec2(hx, -hy) * scar_relief * 0.5;
		base = mix(base, base * vec3(1.18, 0.98, 0.95) + vec3(0.03, 0.0, 0.0), sc * 0.75);
	}
	ALBEDO = base * mix(vec3(1.0), tint.rgb, clamp(tint.a, 0.0, 1.0));
	NORMAL_MAP = normalize(nm) * 0.5 + 0.5;
	ROUGHNESS = clamp(mix(orm.g * rough_scale, 0.3, sc * 0.6), 0.0, 1.0);
	SPECULAR = 0.35;
	AO = orm.r;
	AO_LIGHT_AFFECT = 0.25;
	EMISSION = flash + mark_color * mark_glow * mark;
	v_thin = clamp(1.0 - orm.b, 0.0, 1.0);   // the bake stores inside-AO: thick parts are white
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	vec3 diff;
	if (light_model == 0) {
		diff = vec3(clamp(ndl, 0.0, 1.0));
	} else {
		diff = clamp((vec3(ndl) + wrap) / (1.0 + wrap), vec3(0.0), vec3(1.0));
	}
	DIFFUSE_LIGHT += diff * ATTENUATION * LIGHT_COLOR / PI;
	if (light_model == 2) {
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
	SPECULAR_LIGHT += vec3(d * f * 0.25) * clamp(ndl, 0.0, 1.0) * ATTENUATION * LIGHT_COLOR / PI;
}
