// E2: the Cinder Titan's slag (CinderModel): his plates (the Stormcaller's slabs re-cast), his crown's horns, the spines
// down his back and the brand's head - black glassy slag in plates whose seams run with molten iron. Mapped in metres
// (the plates' UVs, the procedural gear's), Stoneback's stone normal map as its pits and folds.
//   heat   1 hot (the seams bright, the slag's surface dark and glassy) .. 0 quenched (the seams a dull red, the slag
//          grey and dry); CinderModel follows his crust
//   core   extra glow for a piece that is all fire inside (the heart-coal, the brand's head)
//   crack  0 whole .. 1 about to break (CinderModel.set_plate_crack): wider, hotter splits open across it
// RigPaint's `tint` and `flash` as on every actor shader.
shader_type spatial;

#include "res://assets/shaders/cinder_common.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float heat : hint_range(0.0, 1.0) = 1.0;
uniform float core : hint_range(0.0, 1.0) = 0.0;
uniform float crack : hint_range(0.0, 1.0) = 0.0;
uniform float cells = 0.9;
uniform float glow_energy : hint_range(0.0, 12.0) = 2.4;
uniform float normal_depth : hint_range(0.0, 3.0) = 0.9;
uniform vec3 slag_color : source_color = vec3(0.085, 0.078, 0.075);
uniform vec3 cooled_color : source_color = vec3(0.34, 0.32, 0.30);
uniform vec4 tint = vec4(1.0, 1.0, 1.0, 0.0);
uniform vec3 flash = vec3(0.0);

void fragment() {
	float grain = dot(texture(albedo_tex, UV * 0.37 + vec2(0.21, 0.53)).rgb, vec3(0.3333));
	vec2 q = UV * cells + (vec2(cn_fbm(UV * 0.7), cn_fbm(UV * 0.7 + 4.3)) - 0.5) * 0.9;
	vec2 e = cn_cell_edge(q);
	float w = mix(0.018, 0.1, crack) + 0.02 * core;
	float seam = 1.0 - smoothstep(w * 0.35, w, e.x);
	float near = 1.0 - smoothstep(w, w * 3.5, e.x);
	float flick = 0.8 + 0.2 * sin(TIME * 2.3 + e.y * 17.0) * sin(TIME * 1.1 + grain * 9.0);
	vec3 col = mix(slag_color * (0.7 + 0.6 * grain), cooled_color * (0.8 + 0.4 * grain), 1.0 - heat);
	// a plate's own tone a little varied
	col *= 0.85 + 0.3 * e.y;
	float t = mix(0.06, 0.42, heat) + 0.1 * core;
	vec3 emit = cn_fire(t * flick) * seam * glow_energy * mix(0.1, 1.0, heat);
	emit += cn_fire(0.15) * near * 0.4 * heat;
	emit += cn_fire(0.6 * flick) * core * (0.5 + 0.5 * heat) * glow_energy * 0.35 * smoothstep(0.3, 0.9, cn_fbm(UV * 1.3 + TIME * 0.05));
	col = mix(col, vec3(0.3, 0.07, 0.02), seam * 0.7);
	ALBEDO = col * mix(vec3(1.0), tint.rgb, clamp(tint.a, 0.0, 1.0));
	ROUGHNESS = mix(0.28, 0.85, 1.0 - heat) + 0.4 * seam;
	METALLIC = 0.15 * heat;
	SPECULAR = 0.5;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = normal_depth;
	EMISSION = flash + emit;
}
