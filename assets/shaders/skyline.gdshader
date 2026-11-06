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

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
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
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 1.0;
}
