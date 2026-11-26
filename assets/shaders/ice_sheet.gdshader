// D1: a frozen tarn's ice (IceSheet): a disc of old lake ice over dark water, drawn from a small texture of the cells'
// states (R: 1 whole, 0.5 cracked, 0 open; nearest, one texel a cell).
//   whole    grey-blue ice, darker where it is clear and the water shows under it, frost and wind-packed snow lying
//            on it in drifts, a few old pressure cracks white in it
//   cracked  the same ice shattered: a dense net of white fractures, the plates between them tilted (shade jumps),
//            dark water seeping along the worst of them
//   open     nothing: the water plane under it shows; the hole's edge is ragged (a cell's neighbours' ice reaches into it
//            by a noise), with white broken rims
// Outside radius_m the disc is discarded (the shore's ground shows). Unshaded parts none: lit like the ground.
shader_type spatial;

uniform sampler2D cells : filter_nearest, repeat_disable;
uniform float cells_n = 16.0;
uniform float radius_m = 70.0;
uniform vec3 ice_clear : source_color = vec3(0.34, 0.44, 0.52);
uniform vec3 ice_white : source_color = vec3(0.80, 0.84, 0.88);
uniform vec3 snow : source_color = vec3(0.90, 0.92, 0.94);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float a = 0.5;
	float s = 0.0;
	for (int k = 0; k < 4; k++) {
		s += a * vnoise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return s;
}

vec2 cell_hash(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

// the distance to the nearest Voronoi edge (fracture lines) and the cell's random value
vec2 voronoi(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	float id = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 r = g + cell_hash(i + g) - f;
			float d = dot(r, r);
			if (d < d1) {
				d2 = d1;
				d1 = d;
				id = cell_hash(i + g).x;
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return vec2(sqrt(d2) - sqrt(d1), id);
}

varying vec2 local_xz;

void vertex() {
	local_xz = VERTEX.xz;
}

float state_at(vec2 xz) {
	vec2 uv = (xz + vec2(radius_m)) / (2.0 * radius_m);
	return texture(cells, uv).r;
}

void fragment() {
	vec2 p = local_xz;
	float edge_noise = fbm(p * 0.18) * 6.0;
	if (length(p) > radius_m - 1.5 - edge_noise * 0.4) {
		discard;
	}
	// the state here, with the hole's edge ragged: read the cell a noise's offset away
	vec2 jitter = (vec2(fbm(p * 0.21 + 3.1), fbm(p * 0.21 + 7.7)) - 0.5) * 5.0;
	float s = state_at(p + jitter);
	if (s < 0.25) {
		discard;
	}
	float s_here = state_at(p);
	float rim = (s_here < 0.25) ? 1.0 : 0.0;   // a ragged lip of ice reaching over an open cell
	// whole ice: clear patches show the dark water's depth, frost and drifts over it
	float clear = smoothstep(0.45, 0.75, fbm(p * 0.035 + 11.0));
	vec3 col = mix(ice_white, ice_clear, clear * 0.75);
	float drift = smoothstep(0.55, 0.78, fbm(p * 0.05 + vec2(0.0, 4.0)) + 0.25 * fbm(p * 0.4));
	col = mix(col, snow, drift * 0.85);
	// old pressure cracks, white
	vec2 v = voronoi(p * 0.045);
	float old_crack = 1.0 - smoothstep(0.0, 0.025, v.x);
	col = mix(col, ice_white * 1.05, old_crack * (1.0 - drift) * 0.7);
	float rough = mix(0.22, 0.85, max(drift, old_crack));
	if (s < 0.75) {
		// cracked: a dense net of fractures, the plates between them tilted in shade, water seeping in the worst
		vec2 w = voronoi(p * 0.32 + 1.7);
		float frac = 1.0 - smoothstep(0.0, 0.06, w.x);
		float seep = 1.0 - smoothstep(0.0, 0.025, w.x);
		col *= 0.82 + 0.32 * w.y;
		col = mix(col, vec3(0.92, 0.95, 0.97), frac * 0.85);
		col = mix(col, vec3(0.06, 0.09, 0.11), seep * smoothstep(0.4, 0.8, fbm(p * 0.3)));
		rough = mix(rough, 0.6, 0.5);
	}
	if (rim > 0.5) {
		col = mix(col, vec3(0.93, 0.95, 0.97), 0.6);
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.5;
}
