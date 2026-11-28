// E2: the Cinder Titan's skin (CinderModel): the Stormcaller's body and atlas (the people kit's) burned - a crust of
// charred, basalt-dark hide over a fire that shows through it. Where the atlas carries the Stormcaller's pale branching
// scars the fire shows (his scars are the furnace's cracks), and a net of finer cracks (Voronoi seams in UV) glows
// across the crust, brighter where the crust is thin (`heat` 1 hot .. 0 quenched: the fire sinks to a dull red and the
// crust greys with the steam). The palette bands as person.gdshader's: skin (the crust), hair (ash), cloth (the
// scorched hide kilt), none (kept). RigPaint's `tint` and `flash` as on every actor shader.
shader_type spatial;
render_mode cull_disabled;

#include "res://assets/shaders/cinder_common.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_disable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap, repeat_disable;
uniform sampler2D band_tex : hint_default_black, filter_nearest, repeat_disable;
uniform float heat : hint_range(0.0, 1.0) = 1.0;
uniform float glow_energy : hint_range(0.0, 10.0) = 2.2;
uniform float crack_cells = 48.0;
uniform float scar_from : hint_range(0.0, 1.0) = 0.55;
uniform float scar_to : hint_range(0.0, 1.0) = 0.75;
uniform vec3 crust_color : source_color = vec3(0.115, 0.102, 0.094);
uniform vec3 ash_color : source_color = vec3(0.36, 0.345, 0.33);
uniform vec3 hide_color : source_color = vec3(0.27, 0.19, 0.13);
uniform float normal_depth : hint_range(0.0, 2.0) = 1.1;
uniform vec4 tint = vec4(1.0, 1.0, 1.0, 0.0);
uniform vec3 flash = vec3(0.0);

void fragment() {
	vec4 at = texture(albedo_tex, UV);
	vec4 orm = texture(orm_tex, UV);
	ivec2 size = textureSize(band_tex, 0);
	ivec2 px = clamp(ivec2(UV * vec2(size)), ivec2(0), size - 1);
	int band = int(texelFetch(band_tex, px, 0).b * 5.0);
	float lum = dot(at.rgb, vec3(0.299, 0.587, 0.114));
	vec3 a = at.rgb;
	vec3 emit = vec3(0.0);
	float rough = 0.85;
	float flick = 0.82 + 0.18 * sin(TIME * 1.7 + UV.x * 40.0) * sin(TIME * 0.9 + UV.y * 31.0);
	if (band == 1) {
		// the crust: dark basalt, its relief the atlas's own light pattern, ash in its hollows and dusting it
		float n = cn_fbm(UV * 14.0);
		float ash = smoothstep(0.42, 0.78, cn_fbm(UV * 34.0 + 2.0)) * (1.15 - orm.r * 0.5);
		a = crust_color * (0.55 + 0.9 * lum) * (0.8 + 0.4 * n);
		a = mix(a, ash_color * (0.75 + 0.35 * lum), clamp(ash * 0.5 + 0.12, 0.0, 1.0));
		// the scars: the fire beneath shows through the old lightning scars
		float scar = smoothstep(scar_from, scar_to, lum);
		// the finer cracks: thin Voronoi seams, live only in patches, so most of the crust is whole
		vec2 q = UV * crack_cells + (vec2(cn_fbm(UV * 11.0), cn_fbm(UV * 11.0 + 3.1)) - 0.5) * 1.6;
		vec2 e = cn_cell_edge(q);
		float live = smoothstep(0.6, 0.76, cn_fbm(UV * 7.0 + vec2(e.y * 0.25)));
		float seam = (1.0 - smoothstep(0.008, 0.035, e.x)) * live;
		float fire = max(scar * 0.8, seam);
		// quenched: the crust greys with steam and the fire sinks
		a = mix(a, ash_color * 0.85 * (0.7 + 0.3 * lum), (1.0 - heat) * 0.4);
		float t = mix(0.08, 0.55, heat) * (0.8 + 0.2 * flick);
		emit = cn_fire(t + 0.15 * fire) * fire * glow_energy * mix(0.15, 1.0, heat);
		// a dull warmth round the cracks: the crust thin there
		float near = (1.0 - smoothstep(0.035, 0.14, e.x)) * live + scar * 0.35;
		emit += cn_fire(0.05) * near * 0.22 * heat;
		a = mix(a, vec3(0.22, 0.07, 0.03), fire * 0.5);
		rough = mix(0.93, 0.8, scar);
	} else if (band == 2) {
		a = ash_color * 0.35 * (0.6 + 0.8 * lum);
		rough = 0.95;
	} else if (band == 3 || band == 4) {
		a = hide_color * (0.55 + 0.9 * lum);
		float sear = smoothstep(0.55, 0.85, cn_fbm(UV * 22.0));
		a = mix(a, crust_color, sear * 0.6);
		rough = 0.9;
	} else {
		a = at.rgb * 0.5;
		rough = orm.g;
	}
	AO = orm.r;
	AO_LIGHT_AFFECT = 0.4;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = normal_depth;
	ALBEDO = a * mix(vec3(1.0), tint.rgb, clamp(tint.a, 0.0, 1.0));
	ROUGHNESS = rough;
	METALLIC = 0.0;
	SPECULAR = 0.25;
	EMISSION = flash + emit;
}
