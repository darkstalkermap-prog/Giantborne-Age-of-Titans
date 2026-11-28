// E2: burnt ground (CinderFx's patches under his fire; the burned road in the world): charred earth and ash, embers
// glowing in it while it burns (`ember` 1 .. 0 out), its edge ragged. Drawn on flat discs or a draped ribbon: UV.x
// across (0..1), UV.y along (metres for the road, 0..1 for a disc), `disc` true for a patch (its edge the circle).
// Alpha-blended over the ground; per instance (a MultiMesh of patches): INSTANCE_CUSTOM r seed, g ember, b the fade.
shader_type spatial;
render_mode depth_draw_never, cull_disabled, shadows_disabled;

#include "res://assets/shaders/cinder_common.gdshaderinc"

uniform bool disc = true;
uniform float ember = 1.0;
uniform float energy : hint_range(0.0, 6.0) = 2.2;
uniform vec3 char_color : source_color = vec3(0.045, 0.04, 0.038);
uniform vec3 ash_color : source_color = vec3(0.38, 0.37, 0.35);
uniform float along_scale = 0.05;

varying vec4 v_custom;
varying vec3 v_world;

void vertex() {
	v_custom = vec4(0.5, COLOR.a, 1.0, 0.0);
	if (disc) {
		v_custom = INSTANCE_CUSTOM;
	}
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float seed = v_custom.r * 53.0;
	// (the road: its embers brighter toward its head, where he stands - the vertex colour's alpha)
	float glow = disc ? v_custom.g : ember * mix(0.15, 1.0, v_custom.g * v_custom.g);
	float fade = disc ? v_custom.b : 1.0;
	vec2 w = v_world.xz;
	float edge;
	if (disc) {
		float r = length(UV - 0.5) * 2.0;
		edge = 1.0 - smoothstep(0.55 + 0.3 * cn_fbm(w * 0.4 + seed), 1.0, r);
	} else {
		float x = abs(UV.x - 0.5) * 2.0;
		edge = 1.0 - smoothstep(0.55 + 0.35 * cn_fbm(w * 0.06), 1.0, x);
	}
	float n = cn_fbm(w * 0.35 + seed);
	float ash = smoothstep(0.55, 0.85, cn_fbm(w * 0.9 + 7.0));
	vec3 col = mix(char_color, ash_color, ash * 0.6) * (0.75 + 0.5 * n);
	// embers: small hot spots, flickering
	float sp = smoothstep(0.72, 0.9, cn_noise(w * 1.7 + seed)) * smoothstep(0.4, 0.7, n);
	float flick = 0.7 + 0.3 * sin(TIME * 3.1 + n * 20.0);
	vec3 emit = cn_fire(0.35 + 0.35 * flick) * sp * glow * energy * edge;
	ALBEDO = col;
	ROUGHNESS = 0.97;
	SPECULAR = 0.1;
	EMISSION = emit;
	ALPHA = edge * fade * 0.94;
}
