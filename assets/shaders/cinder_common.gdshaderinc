// E2: the Cinder Titan's shared noise (cinder_skin, cinder_plate, cinder_ground): a cell hash, value noise, a two-octave
// fbm and the edge distance of a Voronoi cell (the seams between slag plates, the cracks in his skin).
vec2 cn_hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

float cn_hash1(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float cn_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = cn_hash1(i);
	float b = cn_hash1(i + vec2(1.0, 0.0));
	float c = cn_hash1(i + vec2(0.0, 1.0));
	float d = cn_hash1(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float cn_fbm(vec2 p) {
	return cn_noise(p) * 0.6 + cn_noise(p * 2.13 + vec2(5.2, 1.3)) * 0.3 + cn_noise(p * 4.7 + vec2(1.7, 9.2)) * 0.1;
}

// x: the distance to the nearest cell edge; y: the cell's own random value
vec2 cn_cell_edge(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 best_r = vec2(0.0);
	vec2 best_c = vec2(0.0);
	float d1 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 r = g + cn_hash2(i + g) - f;
			float d = dot(r, r);
			if (d < d1) {
				d1 = d;
				best_r = r;
				best_c = i + g;
			}
		}
	}
	float edge = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 c = i + vec2(float(x), float(y));
			vec2 r = vec2(float(x), float(y)) + cn_hash2(c) - f;
			if (dot(best_r - r, best_r - r) > 1e-5) {
				edge = min(edge, dot(0.5 * (best_r + r), normalize(r - best_r)));
			}
		}
	}
	return vec2(edge, cn_hash1(best_c));
}

// the fire's colour at temperature t (0 dull red .. 1 white-yellow)
vec3 cn_fire(float t) {
	vec3 c = mix(vec3(0.55, 0.05, 0.0), vec3(1.0, 0.32, 0.03), smoothstep(0.0, 0.45, t));
	c = mix(c, vec3(1.0, 0.72, 0.25), smoothstep(0.45, 0.8, t));
	return mix(c, vec3(1.0, 0.95, 0.78), smoothstep(0.8, 1.0, t));
}
