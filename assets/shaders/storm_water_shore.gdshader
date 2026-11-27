// Dgate: the world's standing water drawn to its shore - the Stormstair's pools (StormWater) and the Rimeglass tarn's
// open water (IceSheet). The mesh (StormWater.shore_mesh) knows the water's depth at each vertex: UV.x is the depth in
// metres, negative where the mesh lies draped over the bank above the water; UV.y the distance out from the middle (1
// at the basin's edge). So the water shades from the bed's colour in the shallows to its depth, a pale wet line marks
// where it meets the bank, the bank just above it is darkened wet and fades out within bank_m of height - no hard line
// where a flat plane cuts the terrain, none at the mesh's own rim - and the sky mirrors in it by the fresnel. The
// ripples and the rain's rings are D2's (storm_water_waves.gdshaderinc), the rings' opening crests drawn bright enough
// to read from a giant's height. Drawn after the chunks' own water (the material's render priority) and writing its
// depth, so the chunks' flat water plane under it never shows through. No textures, no screen reads.
shader_type spatial;
render_mode cull_disabled, blend_mix, depth_draw_always;

uniform vec3 deep : source_color = vec3(0.075, 0.105, 0.12);
uniform vec3 sky : source_color = vec3(0.42, 0.48, 0.54);
uniform vec3 shallow : source_color = vec3(0.25, 0.28, 0.23);
uniform vec3 bank_wet : source_color = vec3(0.21, 0.23, 0.18);
uniform float rain : hint_range(0.0, 1.0) = 0.0;
uniform float ripple : hint_range(0.0, 2.0) = 0.6;
uniform float ring_cell_m = 3.2;
uniform float flash : hint_range(0.0, 4.0) = 0.0;
// how far up the bank the wet shows (m), how deep the bed's colour still shows through (m)
uniform float bank_m = 0.7;
uniform float bank_alpha = 0.6;
uniform float clear_m = 2.2;
// how much the sky mirrors in it at least (looking straight down) and the strength of the rings' crests
uniform float mirror = 0.22;
uniform float crest_light = 0.6;
// the mesh's rim (UV.y) fades from rim_fade.x to rim_fade.y
uniform vec2 rim_fade = vec2(1.25, 1.42);

varying vec3 world_pos;
varying float depth_m;
varying float out_u;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	depth_m = UV.x;
	out_u = UV.y;
}

#include "res://assets/shaders/storm_water_waves.gdshaderinc"

void fragment() {
	vec2 p = world_pos.xz;
	float rim = 1.0 - smoothstep(rim_fade.x, rim_fade.y, out_u);
	float d = depth_m;
	if (d >= 0.0) {
		float crest;
		vec2 g = storm_waves(p, TIME, ripple, rain, ring_cell_m, crest);
		vec3 n_world = normalize(vec3(-g.x, 1.0, -g.y));
		NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
		float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
		// the bed's colour in the shallows, the depth's further out
		vec3 water = mix(shallow, deep, smoothstep(0.0, clear_m, d));
		// the sky in it, in broad slow patches (the wind's sheen) so it never reads as one flat colour
		float sheen = 0.5 + 0.5 * sin(dot(p, vec2(0.031, 0.017)) + 0.8 * sin(p.y * 0.023 + TIME * 0.15));
		water = mix(water, sky * 0.62, clamp(mirror + fres * 0.7, 0.0, 1.0) * (0.7 + 0.3 * sheen));
		// the rain's rings, their opening crests catching the light
		water += vec3(0.32, 0.35, 0.38) * clamp(crest, 0.0, 1.0) * rain * crest_light;
		// toward the shore the bed and the wet bank show through the thinning water, so at the waterline the water's
		// colour is the bank's (no line where the one meets the other), with a faint pale wet line on it
		float thin = 1.0 - smoothstep(0.0, 0.7, d);
		water = mix(water, mix(shallow, bank_wet, 0.6), thin * 0.8);
		water = mix(water, vec3(0.42, 0.45, 0.45), smoothstep(0.02, 0.12, d) * (1.0 - smoothstep(0.12, 0.3, d)) * 0.18);
		ALBEDO = water;
		ALPHA = rim;
		ROUGHNESS = 0.06;
		SPECULAR = 0.8;
		EMISSION = vec3(0.55, 0.65, 0.85) * flash * (0.25 + 0.75 * fres);
	} else {
		// the bank just above the water: wet and dark, gone within bank_m of height (the terrain's own colour beyond)
		// (how far up it shows wanders along the shore, so it is no even band)
		float wander = 0.6 + 0.8 * (0.5 + 0.5 * sin(p.x * 0.37 + 2.0 * sin(p.y * 0.29)));
		ALBEDO = bank_wet;
		float up = -d;
		ALPHA = (1.0 - smoothstep(0.0, bank_m * wander, up)) * mix(1.0, bank_alpha, smoothstep(0.0, 0.2, up)) * rim;
		ROUGHNESS = 0.35;
		SPECULAR = 0.45;
	}
	METALLIC = 0.0;
}
