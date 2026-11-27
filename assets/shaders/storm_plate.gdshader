// The Stormcaller's bronze (D2): his plates, the great bell, the storm-rod and his braids, each a skinned mesh mapped in
// metres (tools/giant/kit/stormcaller.py) onto Stoneback's tileable stone normal map, read here as the metal's casting
// pits, scores and hammer marks.
//   normal_tex   the detail normal (repeated; the glTF's tangent frame); albedo_tex the stone's albedo (a faint grain
//                in the metal and the wood)
// The vertex colour: alpha 1 metal - its colour the metal's own (dark drowned bronze, green verdigris where the water
// stood, bright copper on the worn edges and the wire: stormcaller.bronze_colour); alpha 0 what is not metal (the rod's
// black bog-oak, his braids); alpha 0.35 the storm's light (the lodestone's veins, the tines' points: it glows, and
// burns brighter with `charge`).
// Metal is drawn wet: the bronze a little glossy, the verdigris dull and chalky, the copper bright; the rain's sheen
// (`wet`) over everything. `crack` (0 whole .. 1 about to break; StormcallerModel.set_plate_crack) splits the casting:
// dark cracks open across it with a hot copper edge. RigPaint's `tint` and `flash` as on every actor shader.
shader_type spatial;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 tone : source_color = vec3(1.0);
uniform float metal_amount : hint_range(0.0, 1.0) = 0.55;
uniform float roughness_metal : hint_range(0.0, 1.0) = 0.36;
uniform float roughness_green : hint_range(0.0, 1.0) = 0.74;
uniform float roughness_wood : hint_range(0.0, 1.0) = 0.58;
uniform float wet : hint_range(0.0, 1.0) = 0.6;
uniform float normal_depth : hint_range(0.0, 3.0) = 0.55;
uniform vec4 tint = vec4(1.0, 1.0, 1.0, 0.0);
uniform vec3 flash = vec3(0.0);
uniform float crack : hint_range(0.0, 1.0) = 0.0;
uniform float crack_cells = 2.4;
uniform float glow_energy : hint_range(0.0, 8.0) = 0.9;
uniform float charge : hint_range(0.0, 1.0) = 0.0;
uniform vec3 rim_color : source_color = vec3(0.62, 0.70, 0.82);

vec2 cell_hash(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

vec2 cell_edge(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 best_r = vec2(0.0);
	vec2 best_c = vec2(0.0);
	float d1 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 r = g + cell_hash(i + g) - f;
			float d = dot(r, r);
			if (d < d1) {
				d1 = d;
				best_r = r;
				best_c = i + g;
			}
		}
	}
	float edge = 8.0;
	for (int y = -2; y <= 2; y++) {
		for (int x = -2; x <= 2; x++) {
			vec2 c = i + vec2(float(x), float(y));
			vec2 r = vec2(float(x), float(y)) + cell_hash(c) - f;
			if (dot(best_r - r, best_r - r) > 1e-5) {
				edge = min(edge, dot(0.5 * (best_r + r), normalize(r - best_r)));
			}
		}
	}
	return vec2(edge, cell_hash(best_c).x);
}

void fragment() {
	float grain = dot(texture(albedo_tex, UV * 0.37 + vec2(0.21, 0.53)).rgb, vec3(0.3333));
	float is_metal = smoothstep(0.55, 0.8, COLOR.a);
	float is_glow = 1.0 - smoothstep(0.04, 0.10, abs(COLOR.a - 0.35));
	// how green (verdigris) the metal is here: its colour's green over its red
	float green = smoothstep(-0.02, 0.10, COLOR.g - COLOR.r);
	vec3 col = COLOR.rgb * tone * (0.86 + 0.28 * grain);
	// the wet sheen at grazing angles (the rain on him), a cold sky in it
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	col = mix(col, rim_color * 0.55, fres * wet * 0.45);
	float cracked = 0.0;
	if (crack > 0.001) {
		vec2 q = UV * crack_cells + (vec2(grain) - 0.5) * 0.4;
		vec2 e = cell_edge(q);
		float open = smoothstep(e.y * 0.8, e.y * 0.8 + 0.2, crack);
		float w = mix(0.025, 0.08, crack) * open;
		cracked = (1.0 - smoothstep(w * 0.3, w, e.x)) * is_metal;
		float edge = (1.0 - smoothstep(w, w * 2.2, e.x)) * open * is_metal;
		col = mix(col, vec3(0.55, 0.30, 0.15), edge * 0.6);
		col = mix(col, vec3(0.03, 0.03, 0.035), cracked);
	}
	float flick = 0.75 + 0.25 * sin(TIME * 23.0 + grain * 9.0) * sin(TIME * 7.0);
	vec3 emit = COLOR.rgb * is_glow * glow_energy * (0.35 + 2.4 * charge * flick);
	ALBEDO = col * mix(vec3(1.0), tint.rgb, clamp(tint.a, 0.0, 1.0));
	float rough_m = mix(roughness_metal, roughness_green, green);
	ROUGHNESS = clamp(mix(mix(roughness_wood, rough_m, is_metal), 0.9, cracked) - 0.18 * wet, 0.05, 1.0);
	METALLIC = metal_amount * is_metal * (1.0 - 0.65 * green) * (1.0 - cracked);
	SPECULAR = mix(0.45, 0.6, is_metal);
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = normal_depth * mix(0.5, 1.0, is_metal);
	EMISSION = flash + emit;
}
