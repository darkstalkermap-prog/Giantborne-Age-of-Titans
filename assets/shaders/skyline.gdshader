// The skyline (P24a; plan M6-M9 §2.8, decision 12): the whole world's coarse terrain and the
// landmark silhouettes, drawn wherever no chunk's own terrain is. WorldRoot keeps a mask of the
// chunks that are loaded and drawn (within terrain_visibility_end_m) in three global shader
// parameters it registers at run time; a fragment over such a chunk is discarded, so the coarse
// mesh (2 m under the fine heights anyway) never shows through a drawn chunk.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_disabled, shadows_disabled;

// One texel per chunk (x west -> east, y north -> south); red above 0.5 = drawn by its chunk.
global uniform sampler2D world_loaded_mask;
// The world position (x, z) of chunk (0, 0)'s min corner, and the chunk size in metres.
global uniform vec2 world_grid_origin;
global uniform float world_chunk_size;

// C1b: the frost band (x: the world z where it begins, y: where it is whole; equal: none) - north of it the slopes'
// colour is streaked down the fall line (Skyline.set_frost: the near frost ground's look, far off).
uniform vec2 frost_z = vec2(0.0, 0.0);

varying vec3 world_pos;
varying vec3 world_nrm;

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

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	ivec2 size = textureSize(world_loaded_mask, 0);
	vec2 cell_f = (world_pos.xz - world_grid_origin) / max(world_chunk_size, 1.0);
	ivec2 cell = ivec2(floor(cell_f));
	if (cell.x >= 0 && cell.y >= 0 && cell.x < size.x && cell.y < size.y) {
		if (texelFetch(world_loaded_mask, cell, 0).r > 0.5) {
			discard;
		}
	}
	vec3 col = COLOR.rgb;
	if (frost_z.x != frost_z.y) {
		float frost = clamp((world_pos.z - frost_z.x) / (frost_z.y - frost_z.x), 0.0, 1.0);
		if (frost > 0.0) {
			vec3 n = normalize(world_nrm);
			float u = abs(n.x) > abs(n.z) ? world_pos.z : world_pos.x;
			float streak = vnoise(vec2(u * 0.045, world_pos.y * 0.007)) * 0.65 + vnoise(vec2(u * 0.11, world_pos.y * 0.016)) * 0.35;
			float sloped = 1.0 - smoothstep(0.7, 0.95, n.y);
			col *= mix(1.0, 0.76 + 0.42 * streak, sloped * frost);
		}
	}
	ALBEDO = col;
	ROUGHNESS = 1.0;
}
