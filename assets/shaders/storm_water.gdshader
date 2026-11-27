// Standing water that moves (D2): the Stormstair's pools in the Stormcaller's test arena and a frozen tarn's open water
// (IceSheet). Opaque (a body in it is hidden below its surface: wading), a deep slate grey-green, glossy, its normal
// stirred by a few slow travelling ripples in world space, and - while `rain` is up - the rain's rings: little circles
// opening and fading on a grid of cells, each on its own clock. `flash` lights it (a lightning strike near). Cheap: a
// handful of sines and one cell loop, no textures, no screen reads (the compatibility renderer and the Web). Dgate: the
// ripples and rings are storm_water_waves.gdshaderinc (shared with the world's shore water, storm_water_shore.gdshader).
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

#include "res://assets/shaders/storm_water_waves.gdshaderinc"

void fragment() {
	vec2 p = world_pos.xz;
	float crest;
	vec2 g = storm_waves(p, TIME, ripple, rain, ring_cell_m, crest);
	vec3 n_world = normalize(vec3(-g.x, 1.0, -g.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	ALBEDO = mix(deep, sky * 0.55, fres * 0.6);
	ROUGHNESS = 0.08;
	METALLIC = 0.0;
	SPECULAR = 0.75;
	EMISSION = vec3(0.55, 0.65, 0.85) * flash * (0.25 + 0.75 * fres);
}
