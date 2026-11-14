// The giant's garments (P42; plan M10 §2.8): Garment_*. Ported from the asset research's cloth shader,
// with a tileable detail map (a weave or a leather grain with mipmaps) instead of the procedural weave
// that moired at a distance. detail_tex R is the material's shading (white = the dye itself); its
// gradient gives the normal. The dye is a uniform (each garment takes its slot's dye). fade (0-1) is the
// creator's "Hidden by your clothing": a screen-door fade (pixels dropped in a fixed pattern), so the
// garment stays an opaque material. RigPaint's tint and flash as on every giant shader.
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D detail_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec3 dye_color : source_color = vec3(0.45, 0.38, 0.29);
uniform float detail_strength : hint_range(0.0, 1.0) = 0.35;
uniform float normal_strength : hint_range(0.0, 4.0) = 0.6;
uniform float detail_scale = 48.0;
uniform float roughness_base : hint_range(0.0, 1.0) = 0.85;
uniform float fade : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint = vec4(1.0, 1.0, 1.0, 0.0);
uniform vec3 flash = vec3(0.0);

void fragment() {
	if (fade > 0.0) {
		float h = fract(sin(dot(floor(FRAGCOORD.xy), vec2(12.9898, 78.233))) * 43758.5453);
		if (h < fade * 0.85) {
			discard;
		}
	}
	vec2 p = UV * detail_scale;
	float d = texture(detail_tex, p).r;
	vec2 px = vec2(1.0 / float(textureSize(detail_tex, 0).x), 1.0 / float(textureSize(detail_tex, 0).y));
	float gx = texture(detail_tex, p + vec2(px.x, 0.0)).r - texture(detail_tex, p - vec2(px.x, 0.0)).r;
	float gy = texture(detail_tex, p + vec2(0.0, px.y)).r - texture(detail_tex, p - vec2(0.0, px.y)).r;
	ALBEDO = dye_color * mix(1.0, d, detail_strength) * mix(vec3(1.0), tint.rgb, clamp(tint.a, 0.0, 1.0));
	ROUGHNESS = clamp(roughness_base - (1.0 - d) * 0.1, 0.0, 1.0);
	NORMAL_MAP = normalize(vec3(-gx * normal_strength, gy * normal_strength, 1.0)) * 0.5 + 0.5;
	EMISSION = flash;
}
