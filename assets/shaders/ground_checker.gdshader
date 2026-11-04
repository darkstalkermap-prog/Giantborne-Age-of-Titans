// World-space checker for the sandbox floor: 4 m cells make distance and scale readable.
shader_type spatial;

uniform vec3 color_a : source_color = vec3(0.40, 0.45, 0.36);
uniform vec3 color_b : source_color = vec3(0.35, 0.40, 0.32);
uniform vec3 line_color : source_color = vec3(0.28, 0.32, 0.26);
uniform float cell_size = 4.0;
uniform float line_width = 0.05;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 cell = floor(world_pos.xz / cell_size);
	float checker = mod(cell.x + cell.y, 2.0);
	vec2 f = fract(world_pos.xz / cell_size);
	float edge = step(f.x, line_width / cell_size) + step(f.y, line_width / cell_size);
	vec3 base = mix(color_a, color_b, checker);
	ALBEDO = mix(base, line_color, clamp(edge, 0.0, 1.0));
	ROUGHNESS = 0.95;
}
