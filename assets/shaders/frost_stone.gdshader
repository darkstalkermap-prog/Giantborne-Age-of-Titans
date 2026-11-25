// C1b: the weathered stone of the land beyond the rim - the material of a chunk's structures mesh when it holds
// weathered parts (the old giant kings' works, the Breach's fallen rock, the Hoarfell's scatter: tools/world/
// layout.gd add_parts writes a part's "weather" into its vertex colour's alpha as 1 - weather). A face with an
// alpha of 1 is drawn exactly as the plain vertex-colour material it stands in for (assets/world/shared/
// mat_vertex.tres: the colour sRGB as the albedo, roughness 0.95), so a chunk's other structures look as before.
// A weathered face, all in world space (no texture, no UV): snow lying on what faces up (thinning on slopes, in
// drifts), frost-killed lichen in blotches, grime run down the faces under the snow, the colour worn uneven, and
// fine dark cracks; its normal roughened a little, the detail fading out with distance.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform float roughness : hint_range(0.0, 1.0) = 0.95;

varying vec3 world_pos;
varying vec3 world_nrm;

const vec3 SNOW = vec3(0.83, 0.85, 0.89);
const vec3 SNOW_SHADE = vec3(0.7, 0.75, 0.84);
const vec3 LICHEN_A = vec3(0.56, 0.52, 0.36);
const vec3 LICHEN_B = vec3(0.42, 0.45, 0.36);
const vec3 GRIME = vec3(0.2, 0.19, 0.18);

// A colour (sRGB) in the space the albedo is written in (linear, unless the renderer's output is sRGB).
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

float fbm(vec2 p) {
	return vnoise(p) * 0.55 + vnoise(p * 2.07 + 17.3) * 0.3 + vnoise(p * 4.13 + 41.7) * 0.15;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	if (!OUTPUT_IS_SRGB) {
		COLOR.rgb = mix(pow((COLOR.rgb + vec3(0.055)) * (1.0 / (1.0 + 0.055)), vec3(2.4)),
				COLOR.rgb * (1.0 / 12.92), lessThan(COLOR.rgb, vec3(0.04045)));
	}
}

void fragment() {
	vec3 col = COLOR.rgb;
	float rough = roughness;
	float weather = 1.0 - COLOR.a;
	if (weather > 0.004) {
		bool srgb_out = OUTPUT_IS_SRGB;
		vec3 n = normalize(world_nrm);
		vec3 an = abs(n);
		// the face's own plane for the 2-D patterns (the larger of its horizontal axes on a wall)
		vec2 uv = an.y > 0.7 ? world_pos.xz : (an.x > an.z ? world_pos.zy : world_pos.xy);
		float dist = length(world_pos - CAMERA_POSITION_WORLD);
		float near = 1.0 - smoothstep(90.0, 320.0, dist);
		float big = fbm(uv * 0.045 + 3.1);
		float mid = fbm(uv * 0.21);
		// worn colour: the stone lighter and darker in broad patches
		col *= 0.9 + 0.2 * big;
		// grime run down from the tops (vertical faces: streaks long in y)
		float streak = vnoise(vec2(dot(world_pos.xz, vec2(0.71, 0.7)) * 0.55, world_pos.y * 0.035));
		float wall = 1.0 - smoothstep(0.35, 0.6, an.y);
		col = mix(col, to_linear(GRIME, srgb_out), wall * smoothstep(0.6, 0.9, streak) * 0.3 * weather);
		// lichen blotches, frost-killed
		float lich = smoothstep(0.62, 0.76, fbm(uv * 0.12 + 11.0) * 0.7 + mid * 0.3);
		col = mix(col, to_linear(mix(LICHEN_A, LICHEN_B, big), srgb_out) * (0.85 + 0.3 * mid), lich * 0.4 * weather);
		// cracks: the zero lines of a noise, thin and dark, nearer only
		float cr = abs(vnoise(uv * 0.32 + vec2(5.0, 9.0)) - 0.5);
		float crack = (1.0 - smoothstep(0.0, 0.009, cr)) * near * smoothstep(0.45, 0.7, vnoise(uv * 0.05 + 3.0));
		col *= 1.0 - 0.4 * crack * weather;
		// snow on what faces up: whole on the flats, in drifts on a slope, a dusting in the cracks
		float up = smoothstep(0.7, 0.92, n.y);
		float drift = fbm(world_pos.xz * 0.06 + 7.0);
		float snow = clamp(up * (0.7 + 0.9 * (drift - 0.35)) + up * up * 0.35, 0.0, 1.0);
		snow = smoothstep(0.4, 0.62, snow + (mid - 0.5) * 0.25) * weather;
		vec3 snowc = to_linear(mix(SNOW_SHADE, SNOW, smoothstep(0.6, 1.0, n.y)), srgb_out);
		col = mix(col, snowc * (0.94 + 0.06 * mid), snow);
		rough = mix(rough, 0.75, snow);
		// the face's normal roughened (fine relief), fading with distance
		float e = 0.3;
		vec2 q = uv * 2.2;
		float h0 = vnoise(q);
		vec2 g = vec2(vnoise(q + vec2(e, 0.0)) - h0, vnoise(q + vec2(0.0, e)) - h0);
		vec3 t1 = an.y > 0.7 ? vec3(1.0, 0.0, 0.0) : (an.x > an.z ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0));
		vec3 t2 = an.y > 0.7 ? vec3(0.0, 0.0, 1.0) : vec3(0.0, 1.0, 0.0);
		vec3 nb = normalize(n - (t1 * g.x + t2 * g.y) * 0.25 * near * weather * (1.0 - snow * 0.7));
		NORMAL = normalize((VIEW_MATRIX * vec4(nb, 0.0)).xyz);
	}
	ALBEDO = col;
	METALLIC = 0.0;
	SPECULAR = 0.5;
	ROUGHNESS = rough;
}
