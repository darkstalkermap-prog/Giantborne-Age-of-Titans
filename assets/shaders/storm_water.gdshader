// Standing water that moves (D2): the Stormstair's pools in the Stormcaller's test arena and a frozen tarn's open water
// (IceSheet). Opaque (a body in it is hidden below its surface: wading), a deep slate grey-green, glossy, its normal
// stirred by a few slow travelling ripples in world space, and - while `rain` is up - the rain's rings: little circles
// opening and fading on a grid of cells, each on its own clock. `flash` lights it (a lightning strike near). Cheap: a
// handful of sines and one cell loop, no textures, no screen reads (the compatibility renderer and the Web).
shader_type spatial;
render_mode cull_disabled;

uniform vec3 deep : source_color = vec3(0.075, 0.105, 0.12);
uniform vec3 sky : source_color = vec3(0.42, 0.48, 0.54);
uniform float rain : hint_range(0.0, 1.0) = 0.0;
uniform float ripple : hint_range(0.0, 2.0) = 0.6;
uniform float ring_cell_m = 2.6;
uniform float flash : hint_range(0.0, 4.0) = 0.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float h21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 p = world_pos.xz;
	float t = TIME;
	// slow ripples: a few travelling waves (the wind on the water)
	vec2 g = vec2(0.0);
	g += vec2(0.8, 0.3) * cos(dot(p, vec2(0.21, 0.08)) + t * 1.1) * 0.5;
	g += vec2(-0.3, 0.9) * cos(dot(p, vec2(-0.07, 0.25)) + t * 1.4) * 0.35;
	g += vec2(0.6, -0.7) * cos(dot(p, vec2(0.43, -0.31)) + t * 2.3) * 0.2;
	g *= ripple * 0.12;
	// the rain's rings
	if (rain > 0.01) {
		vec2 c = floor(p / ring_cell_m);
		vec2 f = fract(p / ring_cell_m) - 0.5;
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec2 o = vec2(float(x), float(y));
				float r0 = h21(c + o);
				vec2 at = o + vec2(h21(c + o + 3.1), h21(c + o + 7.7)) - 0.5;
				float life = fract(t * (0.7 + 0.6 * r0) + r0 * 9.0);
				float d = length(f - at);
				float ring = sin(clamp((d - life * 0.9) * 28.0, -3.1416, 3.1416)) * (1.0 - life) * smoothstep(0.0, 0.1, life);
				vec2 dir = (f - at) / max(d, 1e-3);
				g += dir * ring * 0.10 * rain * step(0.35, r0);
			}
		}
	}
	vec3 n_world = normalize(vec3(-g.x, 1.0, -g.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	ALBEDO = mix(deep, sky * 0.55, fres * 0.6);
	ROUGHNESS = 0.08;
	METALLIC = 0.0;
	SPECULAR = 0.75;
	EMISSION = vec3(0.55, 0.65, 0.85) * flash * (0.25 + 0.75 * fres);
}
