// The Frostbound Titan's ice (D1): his plates and gear, each a skinned mesh mapped in metres (tools/giant/kit/
// frostbound.py) onto Stoneback's tileable stone normal map, read here as the ice's chips, fractures and flow lines.
//   normal_tex   the detail normal (repeated; the glTF's tangent frame); albedo_tex the stone's albedo (only the cairn's
//                capstones and a faint grain in the ice read it)
// The vertex colour: alpha 1 ice - its colour the ice's own (clear blue-white to deep blue, rime white on the upper
// faces and the shards' tips: frostbound.ice_colour); alpha 0 the old cairn's stone (the stone texture tinted by the
// colour); alpha 0.35 the heart's core (it glows: `glow_energy`, and pulses with `pulse`).
// Ice is drawn as ice: smooth and glossy where it is clear, dull and white where rime crusts it, its edges brighter
// toward grazing angles (a fresnel rim of sky-white), a cold light held inside it (a faint blue emission, deeper in
// the thick ice), and the detail map's fractures as pale lines under the surface.
// `crack` (0 whole .. 1 about to break; FrostboundModel.set_plate_crack) opens white fracture planes across the ice
// (the cells of stone_plate.gdshader's cracks, drawn pale and wide: ice whitens where it breaks), the gloss gone off it.
// RigPaint's `tint` and `flash` as on every actor shader.
shader_type spatial;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 tone : source_color = vec3(1.0);
uniform vec3 rim_color : source_color = vec3(0.86, 0.93, 1.0);
uniform vec3 deep_glow : source_color = vec3(0.10, 0.22, 0.38);
uniform float inner_light : hint_range(0.0, 2.0) = 0.22;
uniform float roughness_ice : hint_range(0.0, 1.0) = 0.16;
uniform float roughness_rime : hint_range(0.0, 1.0) = 0.72;
uniform float normal_depth : hint_range(0.0, 3.0) = 0.7;
uniform vec4 tint = vec4(1.0, 1.0, 1.0, 0.0);
uniform vec3 flash = vec3(0.0);
uniform float crack : hint_range(0.0, 1.0) = 0.0;
uniform float crack_cells = 2.6;
uniform float glow_energy : hint_range(0.0, 8.0) = 0.7;
uniform float pulse : hint_range(0.0, 1.0) = 0.0;

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
	vec3 stone = texture(albedo_tex, UV).rgb;
	float grain = dot(texture(albedo_tex, UV * 0.37 + vec2(0.21, 0.53)).rgb, vec3(0.3333));
	float is_stone = 1.0 - smoothstep(0.15, 0.25, COLOR.a);
	float is_glow = 1.0 - smoothstep(0.04, 0.10, abs(COLOR.a - 0.35));
	// how white (rimed) the ice is here: the vertex colour's own lightness (frostbound.ice_colour puts rime there)
	float rime = smoothstep(0.62, 0.84, dot(COLOR.rgb, vec3(0.3333)));
	vec3 ice = COLOR.rgb * tone * (0.92 + 0.16 * grain);
	// the fresnel rim: sky-white at grazing angles, more on clear ice
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ice = mix(ice, rim_color, fres * mix(0.55, 0.25, rime));
	vec3 col = mix(ice, stone * COLOR.rgb * tone, is_stone);
	float cracked = 0.0;
	if (crack > 0.001) {
		vec2 q = UV * crack_cells + (vec2(grain) - 0.5) * 0.4;
		vec2 e = cell_edge(q);
		float open = smoothstep(e.y * 0.8, e.y * 0.8 + 0.2, crack);
		float w = mix(0.03, 0.10, crack) * open;
		cracked = (1.0 - smoothstep(w * 0.3, w, e.x)) * (1.0 - is_stone);
		float halo = (1.0 - smoothstep(w, w * 3.0, e.x)) * open * (1.0 - is_stone);
		col = mix(col, vec3(0.92, 0.95, 0.98), clamp(cracked + halo * 0.35, 0.0, 1.0));
	}
	vec3 emit = deep_glow * inner_light * (1.0 - rime) * (1.0 - is_stone) * (1.0 - cracked);
	emit += COLOR.rgb * is_glow * glow_energy * (0.8 + 0.4 * pulse);
	ALBEDO = col * mix(vec3(1.0), tint.rgb, clamp(tint.a, 0.0, 1.0));
	ROUGHNESS = mix(mix(roughness_ice, roughness_rime, rime), 0.9, max(is_stone, cracked));
	METALLIC = 0.0;
	SPECULAR = mix(0.62, 0.3, max(is_stone, rime));
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = normal_depth * mix(0.6, 1.0, max(rime, is_stone));
	EMISSION = flash + emit;
}
