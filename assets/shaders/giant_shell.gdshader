// The giant's short hair as shells (P51; plan M11 §2.4, decision 8; probe 6): the crop and the short beard, and
// later fur trim and animal coats (P63's fur_shell starts from it). The mesh is the skin under the style's mask,
// cut by the kit with the body's own UVs and stacked by GiantLook at load time into shell_count layers in one
// surface (one draw call a style): the layer's index rides in UV2.x. Each layer stands its share of
// shell_height_m off the skin (along the normal, the tips combed by `comb`); a strand of strand_tex (a cell a
// strand: R its section, G its length, B its id) is kept in a layer while the layer is below its length and its
// section is wider than the layer's height, so strands taper to points. The style's density is the skin's own
// mask (mask_tex, the skin's masks map, read through mask_channel: G the scalp, R the beard), so a shell style
// thins out at the hairline exactly where the skin's hair tint does. The innermost layer is a solid base: it
// hides the scalp. Never casts a shadow (GiantLook sets it; the skin or the shadow proxy casts). RigPaint's tint
// and flash as on every giant shader.
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform int shell_count = 12;
uniform float shell_height_m = 0.018;
uniform sampler2D strand_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D mask_tex : hint_default_black, filter_linear_mipmap, repeat_disable;
uniform vec4 mask_channel = vec4(0.0, 1.0, 0.0, 0.0);
uniform float strand_scale = 15.0;
uniform vec3 hair_color : source_color = vec3(0.29, 0.17, 0.10);
uniform vec3 tip_color : source_color = vec3(0.43, 0.29, 0.19);
uniform float grey : hint_range(0.0, 1.0) = 0.12;
uniform float density : hint_range(0.0, 2.0) = 1.0;
// The style's cut (the hair option's length): the share of shell_height_m the strands reach.
uniform float length : hint_range(0.0, 1.0) = 1.0;
// The tips' lean in the mesh's own space (stage-1 metres a metre of height): back and down on the crop.
uniform vec3 comb = vec3(0.0, -0.35, 0.45);
uniform float spec_strength = 0.12;
uniform vec4 tint = vec4(1.0, 1.0, 1.0, 0.0);
uniform vec3 flash = vec3(0.0);

// The mask is read a few mip levels down: the skin's beard area ends in a hard line on the cheeks, and the
// shells' edge should thin out over a few centimetres instead.
const float MASK_LOD = 3.0;
// Gate A2: the strand tile's texels (kit/pack.py STRANDS), for the strands' mip level; the grey strands' colour
// (the cards'); the root's shade (the cards' root_dark); the share of the base and the strands' shadow left out
// (the cards' shadow_soft).
const float STRAND_PX = 128.0;
const vec3 GREY = vec3(0.62, 0.60, 0.57);
const float BEARD_SATURATE = 1.0;   // the fifth look lane: a short beard's colour saturation lifted
const float BEARD_STROKE = 2.6;   // the fifth look lane: a short beard's strokes, this much longer than wide
const float BEARD_GREY_SHARE = 0.55;   // the fourth look lane: a short beard reads its colour first (grey-brown at the full share)
uniform float root_dark = 0.78;
uniform float shadow_soft = 0.8;
uniform float sky_sheen = 0.02;

varying float v_h;
varying float v_layer;
varying vec3 v_comb;
varying vec3 v_up;
varying float v_vary;
varying float v_back;

void vertex() {
	v_layer = UV2.x;
	v_h = (UV2.x + 1.0) / float(max(shell_count, 1));
	v_back = smoothstep(0.1, 0.6, -NORMAL.z);   // (the fifth look lane: the back of the head; the mesh faces +Z)
	float m = dot(textureLod(mask_tex, UV, MASK_LOD), mask_channel);
	float lift = shell_height_m * length * v_h * smoothstep(0.02, 0.35, m * density);
	VERTEX += (NORMAL + comb * v_h) * lift;
	v_comb = normalize((MODELVIEW_MATRIX * vec4(comb + NORMAL * 0.2, 0.0)).xyz);
	v_up = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
}

void fragment() {
	// (the fifth look lane: on a beard the strands drawn as short strokes along the face, down the cheeks and the chin -
	// round, they read as a speckle)
	vec2 suv = vec2(UV.x * strand_scale * BEARD_STROKE, UV.y * strand_scale);   // (the crop's too: a speckled cap)
	vec4 st = texture(strand_tex, suv);
	float m = clamp(dot(textureLod(mask_tex, UV, MASK_LOD), mask_channel) * density, 0.0, 1.0);
	// the style's edge thins strand by strand: a short strand drops out first where the mask fades
	// (the fourth look lane: a beard thins out over a wider, uneven band, so its edge is ragged, not the mask's line)
	float ragged = smoothstep(0.05, 0.75, m) * (0.75 + 0.5 * texture(strand_tex, UV * strand_scale * 0.07).b);
	// (the crop thins out the same way at the nape, behind: from behind it ended in a hard line)
	float keep = mask_channel.x > 0.5 ? ragged : mix(smoothstep(0.03, 0.4, m), ragged, v_back);
	// every layer keeps the strands that reach it and are still wider than its height there (the innermost,
	// nearly all of them: with the skin's own beard or scalp shade under it, it hides the skin)
	float reach = st.g * keep;
	if (v_layer < 0.5) {
		// the base: every strand's root where the style grows, the gaps closing inside it
		if (keep < 0.05 || st.r < 0.9 - 0.9 * keep) {
			discard;
		}
	} else if (reach < v_h || st.r < 0.08 + 0.8 * v_h) {
		discard;
	}
	// clumps: a coarse read of the same strands lightens and darkens patches of the style
	float clump = texture(strand_tex, UV * strand_scale * 0.13 + vec2(0.37, 0.61)).b;
	// Gate A2: the colour as the cards take it (giant_hair.gdshader): the tips toward tip_color, grey strands by
	// their id, and where the strands are minified (several to a pixel: the ids blend in the mip chain) the grey's
	// share blended in, not stepped - a step on a blended id drew a dark crop with sparse white specks
	vec3 c = mix(hair_color, tip_color, smoothstep(0.3, 1.0, v_h) * (mask_channel.x > 0.5 ? 0.12 : 0.25));
	vec2 sdx = dFdx(UV * strand_scale * STRAND_PX);
	vec2 sdy = dFdy(UV * strand_scale * STRAND_PX);
	float mip = 0.5 * log2(max(max(dot(sdx, sdx), dot(sdy, sdy)), 1e-6));
	float gw = clamp(0.02 + 0.2 * max(mip, 0.0), 0.02, 0.5);
	float is_grey = (1.0 - smoothstep(grey - gw, grey + gw, st.b)) * step(0.001, grey);
	// the third look lane: on a beard (mask_channel R) the grey is the beard's share of it over every strand and the tips
	// lighter as the cards' (the short beard read as a grey speckled mask, not the beard's colour)
	float beard_shell = step(0.5, mask_channel.x);
	// (its share of grey everywhere, as the cards' blend reads minified: the grey strands one by one were white specks)
	// (the fourth look lane: the crop too - from behind it read as a speckled cap)
	float grey_share = mix(grey, grey * BEARD_GREY_SHARE, beard_shell);
	c = mix(c, GREY, grey_share);
	// the strands darken a little towards the skin (each other's shadow) and vary strand by strand (not by the id
	// the grey reads: the grey strands were the darkest); the mean is the cards' (about 1)
	float vary = fract(st.b * 7.31);
	v_vary = vary;
	// (the fourth look lane: strand to strand a little less: the crop and the short beard read as a speckle)
	c *= mix(root_dark, 1.1, smoothstep(0.0, 0.85, v_h)) * (0.89 + 0.22 * vary) * (0.88 + 0.24 * clump);
	// (the fifth look lane: a beard's strands keep their colour's saturation - their shade between them greyed it to a
	// grey-brown mask - and its innermost layer shades as the skin under it, which the skin shader tints the beard's)
	c = mix(c, mix(vec3(dot(c, vec3(0.2126, 0.7152, 0.0722))), c, BEARD_SATURATE), beard_shell);
	ALBEDO = c * mix(vec3(1.0), tint.rgb, clamp(tint.a, 0.0, 1.0));
	ROUGHNESS = 0.85;
	SPECULAR = 0.05;
	EMISSION = flash;
}

void light() {
	// the cards' light (giant_hair.gdshader): a wrapped diffuse, most of the shadow on each other left out, and a
	// little light through the strands' thin tips with the light behind them
	float ndl = dot(NORMAL, LIGHT);
	float att = mix(ATTENUATION, 1.0, shadow_soft);
	DIFFUSE_LIGHT += clamp(ndl * 0.75 + 0.25, 0.0, 1.0) * att * LIGHT_COLOR / PI;
	float through = pow(clamp(dot(VIEW, -LIGHT), 0.0, 1.0), 3.0) * (0.25 + 0.5 * v_h);
	DIFFUSE_LIGHT += hair_color * 0.5 * through * att * LIGHT_COLOR / PI;
	vec3 h = normalize(LIGHT + VIEW);
	float th = dot(v_comb, h);
	float s = pow(sqrt(max(1.0 - th * th, 0.0)), 24.0);
	SPECULAR_LIGHT += mix(vec3(1.0), hair_color * 2.0, 0.5) * s * spec_strength * clamp(ndl + 0.25, 0.0, 1.0) * att
		* LIGHT_COLOR * v_h;
	if (LIGHT_IS_DIRECTIONAL) {
		// the sky's sheen along the strands: the sky above lights a strand's highlight whichever side the sun is on
		// (the renderer's ambient has no highlight); scaled by the sun's light so it fades with it
		float tu = dot(v_comb, normalize(v_up + VIEW));
		float sk = pow(sqrt(max(1.0 - tu * tu, 0.0)), 6.0) * (0.6 + 0.8 * v_vary) * v_h;
		SPECULAR_LIGHT += mix(vec3(1.0), hair_color * 2.0, 0.5) * sky_sheen * sk * LIGHT_COLOR
			* clamp(dot(NORMAL, v_up) * 0.5 + 0.5, 0.0, 1.0);
	}
}
