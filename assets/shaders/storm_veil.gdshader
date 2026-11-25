// C1b: the storm on the Hoarcrown (the world's "storms": tools/builders/world.gd _storms) - something vast stirring on
// the heights the Frostbound will come down from. Cards of cloud standing round a summit, each turned to the camera
// about the vertical (its corner's offset in UV2, metres; its centre in VERTEX, world space), their alpha a churning
// value noise that rises, swirls round the peak and thins at the edges; a cold light deep inside them swells and fades
// slowly, as if something breathed under the snow. Unshaded, never writes depth; the fog takes it with distance.
shader_type spatial;
render_mode world_vertex_coords, blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

uniform vec4 cloud_color : source_color = vec4(0.86, 0.88, 0.92, 1.0);
uniform vec4 shade_color : source_color = vec4(0.4, 0.44, 0.52, 1.0);
uniform vec4 glow_color : source_color = vec4(0.62, 0.8, 0.98, 1.0);
uniform float density = 1.25;
uniform float speed = 1.0;

varying vec2 card;
varying float seed;

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
	return vnoise(p) * 0.5 + vnoise(p * 2.1 + 13.7) * 0.28 + vnoise(p * 4.3 + 37.1) * 0.14 + vnoise(p * 8.7 + 71.3) * 0.08;
}

void vertex() {
	vec3 right = normalize(vec3(INV_VIEW_MATRIX[0].x, 0.0, INV_VIEW_MATRIX[0].z));
	VERTEX = VERTEX + right * UV2.x + vec3(0.0, UV2.y, 0.0);
	card = UV;
	seed = COLOR.r * 17.0;
}

void fragment() {
	float t = TIME * 0.02 * speed;
	vec2 uv = card;
	// soft edges: thin toward the card's sides and top, a little at the foot
	float edge = smoothstep(0.0, 0.28, uv.x) * smoothstep(1.0, 0.72, uv.x) * smoothstep(1.0, 0.55, uv.y) * smoothstep(0.0, 0.4, uv.y);
	vec2 q = vec2(uv.x * 2.2 + seed + t * 3.0, uv.y * 1.6 - t * 1.4);
	vec2 warp = vec2(fbm(q + vec2(0.0, t * 2.0)), fbm(q + vec2(5.2, -t * 1.6)));
	float c = fbm(q * 1.3 + warp * 1.6 - vec2(t * 2.4, 0.0));
	float a = smoothstep(0.32, 0.66, c) * edge * density;
	// the cold light under the storm: slow, uneven breaths
	float breath = 0.5 + 0.5 * sin(TIME * 0.35 + seed) * (0.6 + 0.4 * sin(TIME * 0.13 + seed * 2.0));
	float core = smoothstep(0.65, 0.05, abs(uv.x - 0.5) * 2.0) * smoothstep(0.75, 0.15, uv.y) * smoothstep(0.45, 0.8, c);
	vec3 col = mix(shade_color.rgb, cloud_color.rgb, smoothstep(0.35, 0.85, c + uv.y * 0.25));
	col = mix(col, glow_color.rgb, core * breath * 0.45);
	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 0.92);
}
