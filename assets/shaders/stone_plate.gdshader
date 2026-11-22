// Stoneback's stone and wood (A1): the plates, the boulder and the trunk-club, each a skinned mesh mapped in metres
// onto a small tileable detail texture (tools/giant/kit/stoneback.py: stoneback_stone_*.png, stoneback_bark_*.png).
//   albedo_tex, normal_tex  the detail texture (repeated; the normal map in the glTF's tangent frame)
//   macro_scale             a second, larger read of the albedo's own light pattern that breaks the repeat
//   tone                    the piece's colour over the texture's (a plate's weathering, the wood's)
// RigPaint's `tint` and `flash` as on every actor shader, so a later fight flashes the plates with the body.
shader_type spatial;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 tone : source_color = vec3(1.0);
uniform float macro_scale = 0.21;
uniform float macro_strength = 0.45;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.92;
uniform float normal_depth : hint_range(0.0, 3.0) = 1.0;
uniform vec4 tint = vec4(1.0, 1.0, 1.0, 0.0);
uniform vec3 flash = vec3(0.0);

void fragment() {
	vec3 a = texture(albedo_tex, UV).rgb;
	vec3 m = texture(albedo_tex, UV * macro_scale + vec2(0.37, 0.61)).rgb;
	float lm = dot(m, vec3(0.3333));
	a *= mix(1.0, 0.55 + lm * 1.1, macro_strength);
	ALBEDO = a * tone * mix(vec3(1.0), tint.rgb, clamp(tint.a, 0.0, 1.0));
	ROUGHNESS = roughness_value;
	SPECULAR = 0.3;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = normal_depth;
	EMISSION = flash;
}
