shader_type spatial;
// E3: the Hollow Titan's armour (HollowModel): old iron gone dark, pitted and rust-stained, its gilt trims worn to the
// metal on every edge a hand or a blow ever met; inside, nothing - the plates' inner faces are near black, lit only by
// the oath-knot's pale gold where they face it. No texture: everything from the mesh's colours and the model-space
// position (HollowArmour writes COLOR: r = edge wear 0..1, g = gilt 0..1, b = the plate's own tone, a = 1; UV2 = the
// its rim). The inner faces (COLOR.a 0) are inside the shell. Presentation only.
//   crack      0 whole .. 1 about to break: a plate's damage (dark splits, the oath's light in the deepest)
//   resonance  0 .. 1: his echo - a pale shimmer along the plates' edges and gilt, quickening as it fills
//   knot       the oath-knot's place (model space) and glow: the inner faces lit by it
//   life       1 moving .. 0 his fall: the inner light dies with him
render_mode cull_back, depth_draw_opaque;

uniform float crack : hint_range(0.0, 1.0) = 0.0;
uniform float resonance : hint_range(0.0, 1.0) = 0.0;
uniform vec3 knot_pos = vec3(0.0, 24.4, 1.4);
uniform float knot_glow = 1.0;
uniform float life : hint_range(0.0, 1.0) = 1.0;
uniform vec3 iron_tint : source_color = vec3(0.105, 0.105, 0.115);
uniform vec3 rust_tint : source_color = vec3(0.22, 0.12, 0.07);
uniform vec3 gilt_tint : source_color = vec3(0.62, 0.47, 0.2);
uniform vec3 oath_light : source_color = vec3(1.0, 0.83, 0.52);
uniform float seed_offset = 0.0;

varying vec3 local_pos;
varying vec3 local_nrm;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i + vec3(0, 0, 0)), hash3(i + vec3(1, 0, 0)), f.x),
		mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x),
		mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise3(p);
		p = p * 2.07 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	local_pos = VERTEX;
	local_nrm = NORMAL;
}

void fragment() {
	float wear = COLOR.r;
	float gilt = COLOR.g;
	float tone = COLOR.b;
	vec3 p = local_pos + vec3(seed_offset);
	// rust: blotches that run down the plates (stretched in y), heaviest in the hollows away from the edges
	float blot = fbm(p * vec3(0.55, 0.22, 0.55));
	float pits = fbm(p * 3.1);
	float steel = step(0.9, tone);
	float rust = smoothstep(0.56, 0.8, blot + 0.18 * pits - 0.3 * wear) * 0.7 * (1.0 - steel);
	// the iron: dark, a little bluer on the upper faces (the sky in it), polished bright on worn edges
	vec3 iron = iron_tint * (0.75 + 0.5 * tone) * (0.85 + 0.3 * pits);
	iron = mix(iron, vec3(0.3, 0.31, 0.32) * (0.85 + 0.3 * pits), steel);
	vec3 col = mix(iron, rust_tint * (0.7 + 0.6 * pits), rust * 0.8);
	vec3 bright = vec3(0.42, 0.41, 0.4);
	col = mix(col, bright, smoothstep(0.55, 1.0, wear) * 0.55 * (1.0 - rust));
	// the gilt: worn through to the iron in streaks and on the edges
	float gilt_left = gilt * smoothstep(0.32, 0.62, fbm(p * 1.7 + 4.0) + 0.25 - wear * 0.35);
	col = mix(col, gilt_tint * (0.8 + 0.4 * pits), gilt_left);
	float metal = mix(0.82, 1.0, gilt_left) * (1.0 - rust * 0.7);
	float rough = mix(mix(0.58, 0.36, steel), 0.34, gilt_left);
	rough = mix(rough, 0.9, rust);
	rough = mix(rough, 0.32, smoothstep(0.6, 1.0, wear) * (1.0 - rust));
	// damage: splits along a cellular pattern that open as the plate fails
	float splits = 0.0;
	if (crack > 0.01) {
		// a few long splits (the cell edges of a coarse noise), widening as the plate fails
		float c = abs(fbm(p * 0.55 + 11.0) - 0.5);
		float w = mix(0.003, 0.022, crack);
		splits = 1.0 - smoothstep(w * 0.5, w, c);
		col = mix(col, vec3(0.012), splits);
	}
	vec3 emit = vec3(0.0);
	if (COLOR.a < 0.5) {
		// inside the shell: nothing - near black, the knot's light on what faces it
		vec3 to_knot = knot_pos - local_pos;
		float d = length(to_knot);
		float facing = clamp(dot(normalize(local_nrm), to_knot / max(d, 0.001)), 0.0, 1.0);
		col = vec3(0.012, 0.011, 0.01);
		metal = 0.0;
		rough = 0.95;
		emit = oath_light * knot_glow * life * facing * facing * 0.35 / (1.0 + 0.06 * d * d);
	} else {
		// the oath's light in the deepest of them only
		emit += oath_light * splits * smoothstep(0.6, 1.0, crack) * 0.35 * life;
		// the echo: a pale pulse along the edges and the gilt
		float pulse = 0.5 + 0.5 * sin(TIME * mix(2.0, 9.0, resonance) + p.y * 0.4);
		emit += vec3(0.75, 0.8, 0.85) * resonance * resonance * (0.25 + 0.75 * wear + gilt_left) * pulse * 0.5 * life;
	}
	ALBEDO = col;
	METALLIC = metal;
	ROUGHNESS = rough;
	SPECULAR = 0.5;
	EMISSION = emit;
}
