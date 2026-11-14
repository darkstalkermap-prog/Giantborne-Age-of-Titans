// The giant's hair and beard cards (P42; plan M10 §2.8, decision 12): Hair_* and Beard_*. Ported from
// the asset research's card shader. Cards drawn with a depth pre-pass and a blended fringe (no alpha to
// coverage in the Compatibility renderer). The colour is a uniform: the hair's (or the beard's) colour,
// sun-bleached tips, a fraction of grey strands (the atlas's G is a per-strand id), darker roots, a
// Kajiya-Kay highlight along the strands, and an alpha boost with the mip level so far cards do not thin
// out. RigPaint's tint and flash as on every giant shader.
shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha;

uniform sampler2D hair_atlas : filter_linear_mipmap, repeat_disable;   // A coverage, R brightness, G strand id
uniform vec3 hair_color : source_color = vec3(0.29, 0.17, 0.10);
uniform vec3 tip_color : source_color = vec3(0.43, 0.29, 0.19);
uniform float grey : hint_range(0.0, 1.0) = 0.12;
uniform float spec_shift = -0.12;
uniform float alpha_boost = 0.25;
uniform float atlas_px = 512.0;
uniform float spec_strength = 0.05;
uniform float spec_power = 48.0;
uniform vec4 tint = vec4(1.0, 1.0, 1.0, 0.0);
uniform vec3 flash = vec3(0.0);

varying vec3 v_strand;

void fragment() {
	vec4 t = texture(hair_atlas, UV);
	vec2 dx = dFdx(UV * atlas_px);
	vec2 dy = dFdy(UV * atlas_px);
	float mip = 0.5 * log2(max(max(dot(dx, dx), dot(dy, dy)), 1e-6));
	ALPHA = clamp(t.a * (1.0 + max(mip, 0.0) * alpha_boost), 0.0, 1.0) * (1.0 - smoothstep(0.82, 1.0, UV.y) * 0.6);
	vec3 c = mix(hair_color, tip_color, smoothstep(0.35, 1.0, UV.y));
	c = mix(c, vec3(0.62, 0.60, 0.57), step(t.g, grey));
	c *= 0.55 + 0.6 * t.r;
	c *= mix(0.45, 1.0, smoothstep(0.0, 0.3, UV.y));   // darker at the roots
	ALBEDO = c * mix(vec3(1.0), tint.rgb, clamp(tint.a, 0.0, 1.0));
	ROUGHNESS = 0.55;
	SPECULAR = 0.3;
	EMISSION = flash;
	v_strand = normalize(BINORMAL);
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	DIFFUSE_LIGHT += clamp(ndl * 0.65 + 0.35, 0.0, 1.0) * ATTENUATION * LIGHT_COLOR / PI;
	vec3 h = normalize(LIGHT + VIEW);
	vec3 ts = normalize(v_strand + NORMAL * spec_shift);
	float th = dot(ts, h);
	float s = pow(sqrt(max(1.0 - th * th, 0.0)), spec_power);
	SPECULAR_LIGHT += mix(vec3(1.0), hair_color * 3.0, 0.5) * s * spec_strength * clamp(ndl + 0.25, 0.0, 1.0) * ATTENUATION * LIGHT_COLOR;
}
