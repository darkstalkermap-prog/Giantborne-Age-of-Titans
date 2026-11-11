// Trees that fade out of the giant's way (M8 screenshot pass, V1): the material of the world's tree
// meshes (assets/world/shared/mat_tree_fade.tres, vertex colours as albedo) and of the Valley's trees
// (assets/materials/valley_*_fade.tres, a flat albedo), otherwise the look of the StandardMaterial3D
// it replaces. A fragment near the camera, or inside the cone from the camera to the giant (and on
// past him where what he fights stands) or to the locked target, dithers out: a 4 x 4 ordered dither
// discards that share of its pixels, so the giant and his fight show through and a ghost of the tree
// stays. The camera rig sets the three global parameters every frame (SceneryFade.set_view; the
// project declares them); scripts/presentation/scenery_fade.gd holds the same rule on the CPU
// (SceneryFade.fade_at, for the tests) - change both together.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// xyz: the camera's position; w: the near radius (m) - closer fragments fade out whole (0: no fading).
global uniform vec4 scenery_fade_camera;
// xyz: the giant's middle; w: the cone's radius at him (0: none, as in first person).
global uniform vec4 scenery_fade_focus;
// xyz: the locked target's lock point; w: its cone's radius (0: no lock).
global uniform vec4 scenery_fade_target;

uniform vec4 albedo : source_color = vec4(1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.95;
// The world's scenery meshes carry their colour (sRGB) in the vertex colours.
uniform bool vertex_color_albedo = false;

// SceneryFade's constants (keep equal).
const float CONE_FADE = 0.8;
const float CONE_APEX_M = 0.5;
const float CONE_EDGE = 0.35;
const float EDGE_M = 0.5;
const float FOCUS_REACH_RADII = 1.4;
const float TARGET_REACH_RADII = 0.5;
const float NEAR_CORE = 0.75;
const float SAME_CAMERA_M = 0.5;

// The fragment's world position (MODEL_MATRIX holds a MultiMesh instance's transform too).
varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (vertex_color_albedo && !OUTPUT_IS_SRGB) {
		COLOR.rgb = mix(pow((COLOR.rgb + vec3(0.055)) * (1.0 / (1.0 + 0.055)), vec3(2.4)),
				COLOR.rgb * (1.0 / 12.92), lessThan(COLOR.rgb, vec3(0.04045)));
	}
}

// The fade of world point p in the cone from the camera `cam` to `focus` (xyz, w: its radius there),
// going on `reach_radii` x the radius past the focus.
float cone_fade(vec3 p, vec3 cam, vec4 focus, float reach_radii) {
	if (focus.w <= 0.0) {
		return 0.0;
	}
	vec3 axis = focus.xyz - cam;
	float len = length(axis);
	if (len < 0.01) {
		return 0.0;
	}
	axis /= len;
	vec3 rel = p - cam;
	float s = dot(rel, axis);
	if (s <= 0.0) {
		return 0.0;
	}
	float d = length(rel - axis * s);
	float r = CONE_APEX_M + focus.w * min(s / len, 1.0);
	float across = 1.0 - smoothstep(r, r + r * CONE_EDGE + EDGE_M, d);
	float reach = focus.w * reach_radii;
	float along = 1.0 - smoothstep(len + reach * 0.5, len + reach, s);
	return CONE_FADE * across * along;
}

// SceneryFade.fade_at: 0 (drawn whole) .. 1 (gone).
float scenery_fade(vec3 p, vec3 eye) {
	if (scenery_fade_camera.w <= 0.0 || distance(eye, scenery_fade_camera.xyz) > SAME_CAMERA_M) {
		return 0.0;
	}
	vec3 cam = scenery_fade_camera.xyz;
	float near_r = scenery_fade_camera.w;
	float f = 1.0 - smoothstep(near_r * NEAR_CORE, near_r, distance(p, cam));
	f = max(f, cone_fade(p, cam, scenery_fade_focus, FOCUS_REACH_RADII));
	f = max(f, cone_fade(p, cam, scenery_fade_target, TARGET_REACH_RADII));
	return f;
}

// A 4 x 4 ordered (Bayer) threshold in [0, 1): sixteen levels.
float bayer2(vec2 a) {
	a = floor(a);
	return fract(a.x * 0.5 + a.y * a.y * 0.75);
}

float bayer4(vec2 a) {
	a = mod(floor(a), 4.0);
	return bayer2(a * 0.5) * 0.25 + bayer2(a);
}

void fragment() {
	// The eye of this pass: the camera's own pass matches scenery_fade_camera, a shadow pass does not.
	vec3 eye = INV_VIEW_MATRIX[3].xyz;
	float fade = scenery_fade(world_pos, eye);
	if (fade > 0.0 && fade >= bayer4(FRAGCOORD.xy) + 1.0 / 32.0) {
		discard;
	}
	ALBEDO = vertex_color_albedo ? albedo.rgb * COLOR.rgb : albedo.rgb;
	METALLIC = 0.0;
	SPECULAR = 0.5;
	ROUGHNESS = roughness;
}
