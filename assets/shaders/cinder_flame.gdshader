// E2: fire (CinderFx: his burning ground, the brand's head, a fallen ember): an upright flame drawn on a camera-facing
// quad, added light (never a dark quad), its shape and its tongues from scrolling noise. A MultiMesh of them is one
// draw call for every flame of the fight. INSTANCE_CUSTOM: r the flame's seed, g its strength (0 out .. 1), b how fast
// its tongues rise, a spare. The quad is 1 x 1 m, its foot at y = 0; the instance's basis scales it.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

#include "res://assets/shaders/cinder_common.gdshaderinc"

uniform float energy : hint_range(0.0, 8.0) = 1.3;

varying vec4 v_custom;

void vertex() {
	v_custom = INSTANCE_CUSTOM;
	// upright billboard: the quad's x along the camera's right, y the instance's own up
	vec3 right = normalize(INV_VIEW_MATRIX[0].xyz * vec3(1.0, 0.0, 1.0) + vec3(1e-4, 0.0, 0.0));
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	vec3 world = MODEL_MATRIX[3].xyz + right * VERTEX.x * sx + vec3(0.0, 1.0, 0.0) * VERTEX.y * sy;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	float seed = v_custom.r * 91.7;
	float strength = v_custom.g;
	float rise = 1.2 + v_custom.b * 1.6;
	vec2 uv = vec2(UV.x - 0.5, 1.0 - UV.y);
	// the tongues: two layers of noise scrolling up, the flame leaning and wavering sideways as it rises
	float n1 = cn_fbm(vec2(uv.x * 2.6 + seed, uv.y * 1.8 - TIME * rise));
	float n2 = cn_noise(vec2(uv.x * 6.0 - seed, uv.y * 4.0 - TIME * rise * 1.7));
	float wob = (cn_noise(vec2(uv.y * 1.6 - TIME * 1.1, seed)) - 0.5) * 0.35 * uv.y;
	float x = abs(uv.x + wob);
	// a broad foot narrowing upward, torn into tongues near its top by the noise
	float height = 0.55 + 0.45 * n1;
	float h = uv.y / height;
	float width = 0.44 * (1.0 - smoothstep(0.0, 1.0, h)) * (0.65 + 0.7 * n2) + 0.015;
	float body = 1.0 - smoothstep(width * 0.15, width, x);
	body *= smoothstep(0.0, 0.12, uv.y) * (1.0 - smoothstep(0.6, 1.0, h));
	body = clamp(body * (0.8 + 0.5 * n1), 0.0, 1.0);
	// hottest low in the middle, red and thin at the tips
	float temp = clamp(body * (1.05 - uv.y * 0.8) * 0.95 + 0.1 * n2, 0.0, 1.0);
	vec3 c = cn_fire(temp * 0.92) * body * body * strength * energy;
	ALBEDO = c;
}
