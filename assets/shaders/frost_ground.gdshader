// C1b: the streamed terrain's material (ChunkStreamer.terrain_material) where a level names a frost band (its world
// block's "frost": {"from_z", "full_z"}: the z where the frost begins and where it is whole; the world's land beyond the rim and the rim's
// faces above the Stonehold). South of the band the ground is the vertex colours alone, exactly as the plain
// material it stands in for (albedo = the colour, roughness 1). In the band the ground is built in world space from
// the height, the slope and a few octaves of value noise (no texture, no UV; the region tints are kept as a cast):
//   - frost-bitten scree and earth, broken by tussock and lichen on the flatter ground below the snow line;
//   - snow lying where the ground is flat enough to hold it, in drifts on the upland and whole high on the rim;
//   - bare rock on the steep faces: broad tones, streaks run down the fall line (gullies and stains, the face's
//     relief ribbed along them), short ledges with their shadow under them, and snow caught on the ledges and
//     down the gullies high up;
//   - near the eye, the scree's own stones (a cell pattern a hand to a stride across), the detail fading with
//     distance; the normal roughened by the same pattern and by the beds' ledges.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform float roughness : hint_range(0.0, 1.0) = 1.0;
// x: the world z where the frost begins (none south of it), y: where it is whole. Equal: no frost anywhere.
uniform vec2 frost_z = vec2(0.0, 0.0);
// The height (m) above which snow holds on most flat ground, and the band over which it thickens.
uniform float snow_line_m = 300.0;
uniform float snow_band_m = 220.0;

varying vec3 world_pos;
varying vec3 world_nrm;

const vec3 SCREE_A = vec3(0.42, 0.41, 0.39);
const vec3 SCREE_B = vec3(0.46, 0.465, 0.47);
const vec3 EARTH = vec3(0.37, 0.35, 0.32);
const vec3 TUSSOCK = vec3(0.5, 0.46, 0.37);
const vec3 MOSS = vec3(0.39, 0.4, 0.34);
const vec3 ROCK_A = vec3(0.31, 0.305, 0.3);
const vec3 ROCK_B = vec3(0.4, 0.39, 0.37);
const vec3 ROCK_SEAM = vec3(0.2, 0.19, 0.19);
const vec3 SNOW = vec3(0.83, 0.85, 0.89);
const vec3 SNOW_SHADE = vec3(0.68, 0.73, 0.82);

vec3 to_linear(vec3 c, bool srgb_out) {
	if (srgb_out) {
		return c;
	}
	return mix(pow((c + vec3(0.055)) * (1.0 / (1.0 + 0.055)), vec3(2.4)), c * (1.0 / 12.92), lessThan(c, vec3(0.04045)));
}

float hash2(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), u.x), mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), u.x), u.y);
}

// The nearest of a cell pattern's points (one jittered point a cell): x its distance, y its cell's own value.
vec2 cells(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float best = 8.0;
	float id = 0.0;
	for (int dy = -1; dy <= 1; dy++) {
		for (int dx = -1; dx <= 1; dx++) {
			vec2 o = vec2(float(dx), float(dy));
			vec2 c = i + o;
			vec2 r = o + vec2(hash2(c), hash2(c + 19.7)) * 0.8 + 0.1 - f;
			float d = dot(r, r);
			if (d < best) {
				best = d;
				id = hash2(c + 7.3);
			}
		}
	}
	return vec2(sqrt(best), id);
}

float fbm(vec2 p) {
	return vnoise(p) * 0.55 + vnoise(p * 2.03 + 17.3) * 0.3 + vnoise(p * 4.11 + 41.7) * 0.15;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 col = COLOR.rgb;
	float rough = roughness;
	float frost = 0.0;
	if (frost_z.x != frost_z.y) {
		frost = smoothstep(0.0, 1.0, clamp((world_pos.z - frost_z.x) / (frost_z.y - frost_z.x), 0.0, 1.0));
	}
	if (frost > 0.0) {
		bool so = OUTPUT_IS_SRGB;
		vec3 n = normalize(world_nrm);
		vec2 xz = world_pos.xz;
		float y = world_pos.y;
		float dist = length(world_pos - CAMERA_POSITION_WORLD);
		float near = 1.0 - smoothstep(25.0, 90.0, dist);
		float mid_fade = 1.0 - smoothstep(120.0, 420.0, dist);
		float big = fbm(xz * 0.009);
		float mid = fbm(xz * 0.045 + 5.0);
		float fine = vnoise(xz * 0.35);
		// the ground: scree and frozen earth in patches with edges, its stones underfoot
		float patch_ = smoothstep(0.42, 0.58, mid * 0.65 + big * 0.35 + (fine - 0.5) * 0.18);
		vec3 ground = mix(to_linear(EARTH, so), mix(to_linear(SCREE_A, so), to_linear(SCREE_B, so), smoothstep(0.35, 0.65, big)), patch_);
		ground *= 0.93 + 0.14 * fine;
		vec2 pc = cells(xz * 0.9);
		float pebble = (1.0 - smoothstep(0.1, 0.3, pc.x)) * step(0.72, pc.y) * near;
		ground *= mix(1.0, 0.8 + 0.3 * fract(pc.y * 7.0), pebble * 0.6);
		// a cast of the region's own tint (the colour the map and the old ground gave it)
		ground = mix(ground, col, 0.15);
		// the fall line's streaks (gullies, flutes in the snow, stains on the rock)
		float u = abs(n.x) > abs(n.z) ? world_pos.z : world_pos.x;
		float streak = fbm(vec2(u * 0.085, y * 0.011) + 11.0);
		float sloped = 1.0 - smoothstep(0.8, 0.96, n.y);
		// tussock and lichen on the flatter ground below the snow line
		float flat_ = smoothstep(0.82, 0.95, n.y);
		float low = 1.0 - smoothstep(snow_line_m - 120.0, snow_line_m + 40.0, y);
		float tuss = smoothstep(0.6, 0.7, fbm(xz * 0.06 + 31.0) * 0.75 + fine * 0.25) * flat_ * low;
		ground = mix(ground, to_linear(mix(TUSSOCK, MOSS, smoothstep(0.35, 0.65, mid)), so) * (0.85 + 0.3 * fine), tuss * 0.5);
		// snow: holds where it is flat enough, thickens with height, lies in drifts on the upland; rock breaks through
		float alt = smoothstep(snow_line_m - snow_band_m * 0.55, snow_line_m + snow_band_m, y);
		float holds = smoothstep(0.6, 0.85, n.y);
		float drift = fbm(xz * 0.016 + vec2(3.0, 11.0));
		float snow = holds * (alt * 1.15 + (drift - 0.55) * 2.6 + (mid - 0.5) * 0.6);
		// rock breaking through the snow on the slopes (not on the flats)
		float outcrop = smoothstep(0.52, 0.66, fbm(xz * 0.021 + 21.0) * 0.8 + fine * 0.2) * (1.0 - smoothstep(0.78, 0.93, n.y));
		snow = smoothstep(0.45, 0.55, snow + (fine - 0.5) * 0.2 - outcrop * 1.2);
		float sastrugi = vnoise(vec2(xz.x * 0.4 + xz.y * 0.15, xz.y * 1.4));
		vec3 snowc = to_linear(mix(SNOW_SHADE, SNOW, smoothstep(0.7, 1.0, n.y) * (0.75 + 0.25 * mid)), so) * (0.96 + 0.06 * sastrugi);
		snowc *= 1.0 - 0.12 * sloped * (1.0 - streak);
		vec3 g = mix(mix(ground, to_linear(mix(ROCK_A, ROCK_B, mid), so), outcrop * holds), snowc, snow);
		// rock on the steep faces: broad tones, streaks down the fall line, short ledges, snow caught in both
		float steep = 1.0 - smoothstep(0.58, 0.78, n.y);
		float warp = (fbm(xz * 0.008 + 9.0) - 0.5) * 24.0;
		float tone_big = fbm(vec2(u, y) * 0.011 + 3.0);
		float ledge_n = vnoise(vec2(u * 0.024, (y + warp) * 0.13));
		float ledge_lo = vnoise(vec2(u * 0.024, (y + warp + 3.0) * 0.13));
		float ledge = smoothstep(0.64, 0.8, ledge_n);
		float under = smoothstep(0.64, 0.8, ledge_lo) * (1.0 - ledge);
		vec3 rock = mix(to_linear(ROCK_A, so), to_linear(ROCK_B, so), smoothstep(0.3, 0.7, tone_big));
		rock *= 0.74 + 0.46 * streak;
		rock *= 1.0 - 0.28 * under * (1.0 - smoothstep(50.0, 180.0, dist));
		rock *= 0.92 + 0.16 * mix(0.5, vnoise(vec2(u, y) * 0.7), mid_fade);
		// snow on the ledges and down the gullies high up, where the face is not sheer
		float caught = max(ledge, smoothstep(0.5, 0.3, streak) * 0.8);
		float face_snow = alt * smoothstep(0.18, 0.45, n.y) * caught * smoothstep(0.35, 0.6, drift + 0.2);
		rock = mix(rock, snowc * 0.95, clamp(face_snow * 1.4, 0.0, 1.0));
		vec3 frost_col = mix(g, rock, steep);
		col = mix(col, frost_col, frost);
		rough = mix(rough, 0.8, snow * (1.0 - steep) * frost);
		// the relief: the stones underfoot, the beds' ledges, the blocks' faces
		float e = 0.35;
		vec2 q = xz * 0.5;
		float h0 = vnoise(q);
		vec2 grad = vec2(vnoise(q + vec2(e, 0.0)) - h0, vnoise(q + vec2(0.0, e)) - h0) * (1.0 - snow * 0.8);
		vec3 nb = n - vec3(grad.x, 0.0, grad.y) * 0.6 * mid_fade;
		float s2 = fbm(vec2((u + 2.5) * 0.085, y * 0.011) + 11.0);
		vec3 tang = abs(n.x) > abs(n.z) ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
		nb += tang * (s2 - streak) * 3.0 * max(steep, sloped * 0.6) * mid_fade;
		nb.y += (ledge * 0.45 - under * 0.2) * steep * (1.0 - smoothstep(50.0, 180.0, dist));
		nb = normalize(mix(n, normalize(nb), frost));
		NORMAL = normalize((VIEW_MATRIX * vec4(nb, 0.0)).xyz);
	}
	ALBEDO = col;
	METALLIC = 0.0;
	SPECULAR = 0.5;
	ROUGHNESS = rough;
}
