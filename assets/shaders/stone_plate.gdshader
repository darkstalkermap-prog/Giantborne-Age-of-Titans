// Stoneback's stone and wood (A1): the plates, the boulder and the trunk-club, each a skinned mesh mapped in metres
// onto a small tileable detail texture (tools/giant/kit/stoneback.py: stoneback_stone_*.png, stoneback_bark_*.png).
//   albedo_tex, normal_tex  the detail texture (repeated; the normal map in the glTF's tangent frame)
//   macro_scale             a second, larger read of the albedo's own light pattern that breaks the repeat
//   tone                    the piece's colour over the texture's (a plate's weathering, the wood's)
// The vertex colour (A1b; white where a mesh has none): alpha 1 the detail texture tinted by the colour, alpha 0 iron
// (the plates' bands: the colour, dark and a little metallic, the texture's light only as wear), alpha 0.5 a matte
// colour (the club's earth: the colour, the texture's light as its grain).
// RigPaint's `tint` and `flash` as on every actor shader, so a later fight flashes the plates with the body.
// A3: `crack` (0 whole .. 1 about to break; StonebackRig.set_plate_crack, one material per breakable plate) opens a
// network of dark cracks across the stone (the edges of cells 1 / crack_cells of a texture repeat across, jagged, a little dust at
// their lips), wider and more of them as it rises; the iron and the matte colours never crack.
// B2: the Ogre King's wood and iron trophies on the same shader (tools/giant/kit/ogre_king.py's oak texture): with
// `crack_grain` 1 the cracks are splits along the wood's grain (the cells stretched down V), the fresh wood pale at
// their lips; `crack` on a metal piece (the bell's bronze, the crown's iron) shows dents darkening it instead.
// B3: the Rootwarden's living bark on the same shader (tools/giant/kit/rootwarden.py's bark texture): a vertex colour
// of alpha 0.35 glows (`glow_energy`: his sapwood, the sap seams of his knot, the lantern-fungi); `grow` (1 whole .. 0
// gone) shows bark regrowing over a wound - the piece eaten away in a mottled front (the texture's own light read at a
// larger scale), fresh pale-green bark at its edge; `charred` (0..1) chars a wound that fire seared (black, glowing
// embers in its cracks, its sap's glow put out). Every default leaves the earlier pieces as they were.
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
uniform float crack : hint_range(0.0, 1.0) = 0.0;
uniform float crack_cells = 3.2;
uniform float crack_grain : hint_range(0.0, 1.0) = 0.0;
// B2: how much of the detail texture's light shows as wear on the iron (1: Stoneback's bands over his stone; the
// King's oak grain would streak his bronze and iron, so his pieces take less)
uniform float metal_wear : hint_range(0.0, 1.0) = 1.0;
uniform float glow_energy : hint_range(0.0, 8.0) = 0.0;
uniform float grow : hint_range(0.0, 1.0) = 1.0;
uniform float charred : hint_range(0.0, 1.0) = 0.0;

vec2 cell_hash(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

// The distance to the nearest edge between two Voronoi cells (0 on an edge) and the nearest cell's random value.
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
	vec3 a = texture(albedo_tex, UV).rgb;
	vec3 m = texture(albedo_tex, UV * macro_scale + vec2(0.37, 0.61)).rgb;
	float lm = dot(m, vec3(0.3333));
	a *= mix(1.0, 0.55 + lm * 1.1, macro_strength);
	float la = dot(a, vec3(0.3333));
	float iron = 1.0 - smoothstep(0.2, 0.3, COLOR.a);
	float flat_col = 1.0 - smoothstep(0.7, 0.8, COLOR.a);
	vec3 textured = a * tone * COLOR.rgb;
	vec3 plain = COLOR.rgb * mix(1.0, 0.55 + 1.6 * la, mix(1.0, metal_wear, iron));
	vec3 col = mix(textured, plain, flat_col);
	float cracked = 0.0;
	if (crack > 0.001) {
		// jagged: the cells' coordinates wobbled by the texture's own light pattern
		vec2 q = UV * crack_cells * mix(vec2(1.0), vec2(2.8, 0.32), crack_grain) + (m.rg - 0.5) * 0.35;
		vec2 e = cell_edge(q);
		// a cell's edge opens once crack passes the cell's own threshold, so the network grows as the stone weakens
		float open = smoothstep(e.y * 0.8, e.y * 0.8 + 0.2, crack);
		float w = mix(0.015, 0.06, crack) * open;
		cracked = (1.0 - smoothstep(w * 0.4, w, e.x)) * (1.0 - iron) * (1.0 - flat_col);
		float lip = (1.0 - smoothstep(w, w * 2.6, e.x)) * open * (1.0 - iron) * (1.0 - flat_col);
		col = mix(col, mix(col * 1.25 + vec3(0.05), col * 1.5 + vec3(0.16, 0.12, 0.07), crack_grain),
			lip * 0.6 * (1.0 - cracked));
		col = mix(col, mix(vec3(0.035, 0.03, 0.028), vec3(0.06, 0.04, 0.025), crack_grain), cracked);
		// a metal trophy's dents: patches of its colour darkened as it is beaten
		float dent = (1.0 - smoothstep(0.0, 0.35, e.x)) * open * iron * crack_grain;
		col = mix(col, col * 0.45, dent * 0.7);
	}
	// B3: a regrowing piece eaten away in a mottled front, fresh bark at the front's edge
	float glow = 1.0 - smoothstep(0.04, 0.10, abs(COLOR.a - 0.35));
	if (grow < 0.999) {
		// (the bark texture's red spans about 0.2-0.42: stretched to 0-1 so the front's mottle covers the piece)
		float mottle = clamp((texture(albedo_tex, UV * 0.17 + vec2(0.13, 0.71)).r - 0.2) / 0.22, 0.0, 1.0);
		float front = mottle * 0.7 + clamp(lm, 0.0, 1.0) * 0.3;
		float edge = grow * 1.15 - 0.08;
		if (front > edge) {
			discard;
		}
		float fresh = 1.0 - smoothstep(0.0, 0.10, edge - front);
		col = mix(col, vec3(0.42, 0.50, 0.24) * (0.7 + 0.5 * la), fresh * 0.85);
	}
	vec3 emit = COLOR.rgb * glow * glow_energy;
	if (charred > 0.001) {
		float ember = smoothstep(0.55, 0.85, texture(albedo_tex, UV * 1.7 + vec2(0.4, 0.2)).r) * charred;
		col = mix(col, vec3(0.03, 0.025, 0.02) + col * 0.08, charred);
		emit = emit * (1.0 - charred) + vec3(1.0, 0.32, 0.05) * ember * 1.6;
	}
	ALBEDO = col * mix(vec3(1.0), tint.rgb, clamp(tint.a, 0.0, 1.0));
	ROUGHNESS = mix(mix(roughness_value, 0.58, iron), 1.0, cracked);
	METALLIC = 0.55 * iron;
	SPECULAR = mix(0.3, 0.4, iron);
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	// the metal's relief from the detail normal scales with its wear too (1: Stoneback's 0.4)
	NORMAL_MAP_DEPTH = normal_depth * mix(1.0, 0.4 * metal_wear, iron);
	EMISSION = flash + emit;
}
