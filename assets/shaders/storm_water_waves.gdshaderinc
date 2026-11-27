// The storm water's moving surface (D2; shared by storm_water.gdshader and, Dgate, storm_water_shore.gdshader): a few
// slow travelling ripples in world space (the wind on the water) and - while `rain` is up - the rain's rings, little
// circles opening and fading on a grid of `cell` m cells, each on its own clock. Returns the surface's slope (the
// normal is (-g.x, 1, -g.y)); `crest` gathers the rings' bright opening edges (the shore shader draws them).

float storm_h21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec2 storm_waves(vec2 p, float t, float ripple_k, float rain_k, float cell, out float crest) {
	vec2 g = vec2(0.0);
	g += vec2(0.8, 0.3) * cos(dot(p, vec2(0.21, 0.08)) + t * 1.1) * 0.5;
	g += vec2(-0.3, 0.9) * cos(dot(p, vec2(-0.07, 0.25)) + t * 1.4) * 0.35;
	g += vec2(0.6, -0.7) * cos(dot(p, vec2(0.43, -0.31)) + t * 2.3) * 0.2;
	g *= ripple_k * 0.12;
	crest = 0.0;
	if (rain_k > 0.01) {
		vec2 c = floor(p / cell);
		vec2 f = fract(p / cell) - 0.5;
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec2 o = vec2(float(x), float(y));
				float r0 = storm_h21(c + o);
				vec2 at = o + vec2(storm_h21(c + o + 3.1), storm_h21(c + o + 7.7)) - 0.5;
				float life = fract(t * (0.7 + 0.6 * r0) + r0 * 9.0);
				float d = length(f - at);
				float fade = (1.0 - life) * smoothstep(0.0, 0.1, life) * step(0.35, r0);
				float ring = sin(clamp((d - life * 0.9) * 28.0, -3.1416, 3.1416)) * fade;
				vec2 dir = (f - at) / max(d, 1e-3);
				g += dir * ring * 0.10 * rain_k;
				crest += smoothstep(0.07, 0.0, abs(d - life * 0.9)) * fade;
			}
		}
	}
	return g;
}
