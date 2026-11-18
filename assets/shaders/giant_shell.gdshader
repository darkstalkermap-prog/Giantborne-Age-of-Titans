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

varying float v_h;
varying float v_layer;
varying vec3 v_comb;

void vertex() {
	v_layer = UV2.x;
	v_h = (UV2.x + 1.0) / float(max(shell_count, 1));
	float m = dot(textureLod(mask_tex, UV, MASK_LOD), mask_channel);
	float lift = shell_height_m * length * v_h * smoothstep(0.02, 0.35, m * density);
	VERTEX += (NORMAL + comb * v_h) * lift;
	v_comb = normalize((MODELVIEW_MATRIX * vec4(comb + NORMAL * 0.2, 0.0)).xyz);
}

void fragment() {
	vec4 st = texture(strand_tex, UV * strand_scale);
	float m = clamp(dot(textureLod(mask_tex, UV, MASK_LOD), mask_channel) * density, 0.0, 1.0);
	// the style's edge thins strand by strand: a short strand drops out first where the mask fades
	float keep = smoothstep(0.03, 0.4, m);
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
	vec3 c = mix(hair_color, tip_color, smoothstep(0.3, 1.0, v_h) * 0.5);
	float is_grey = step(st.b, grey);
	c = mix(c, vec3(0.62, 0.60, 0.57), is_grey);
	// the strands darken towards the skin (each other's shadow) and vary strand by strand
	c *= mix(0.5, 1.1, smoothstep(0.0, 0.85, v_h)) * (0.8 + 0.4 * st.b) * (0.85 + 0.3 * clump);
	ALBEDO = c * mix(vec3(1.0), tint.rgb, clamp(tint.a, 0.0, 1.0));
	ROUGHNESS = 0.85;
	SPECULAR = 0.05;
	EMISSION = flash;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	DIFFUSE_LIGHT += clamp(ndl * 0.6 + 0.4, 0.0, 1.0) * clamp(ndl * 0.6 + 0.4, 0.0, 1.0) * ATTENUATION * LIGHT_COLOR / PI;
	vec3 h = normalize(LIGHT + VIEW);
	float th = dot(v_comb, h);
	float s = pow(sqrt(max(1.0 - th * th, 0.0)), 24.0);
	SPECULAR_LIGHT += mix(vec3(1.0), hair_color * 2.0, 0.5) * s * spec_strength * clamp(ndl + 0.2, 0.0, 1.0) * ATTENUATION
		* LIGHT_COLOR * v_h;
}
