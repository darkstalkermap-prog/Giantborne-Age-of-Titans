// The giant's garments (P42; plan M10 §2.8): Garment_*. Ported from the asset research's cloth shader,
// with a tileable detail map (a weave, a leather grain or a fur with mipmaps; P41's cloth_*.png) instead of
// the procedural weave that moired at a distance. detail_tex holds, as P41 packs it, a tangent-space normal
// in RGB (OpenGL, Y up) and the albedo detail in A (0.75 = the dye itself); detail_strength scales the
// albedo detail, normal_strength the normal. The dye is a uniform (each garment takes its slot's dye). fade
// (0-1) is the creator's "Hidden by your clothing": a screen-door fade (pixels dropped in a fixed pattern),
// so the garment stays an opaque material. RigPaint's tint and flash as on every giant shader. GiantLook
// always binds the map (a garment without it is a problem GiantLook.validate() reports).
//
// The look pass II (P51; plan M11 §2.4): `kind` 0 is cloth, leather and fur as before, 1 metal (the hammered
// detail map, a metallic response: armour from P54 on); `rim` a soft edge light for wool and fur (the cloth's
// fuzz against the light); the darkest dyes lifted to DARK_FLOOR (linear albedo) so dark leather is not black in
// the world's shadow; the detail maps are 256 px.
//
// The wardrobe (P54; plan M11 §2.4, §3.7): the metal kind (1) also draws mail and scale (their detail maps carry the
// rings' and the scales' dark gaps in A, so the gaps stay dark and rough); kind 2 is bone (bone spaulders and the bone
// trophies): its own pale colour under the dye's faint stain, a soft sheen, no metal.
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D detail_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec3 dye_color : source_color = vec3(0.45, 0.38, 0.29);
uniform float detail_strength : hint_range(0.0, 1.0) = 0.35;
uniform float normal_strength : hint_range(0.0, 4.0) = 0.4;
uniform float detail_scale = 96.0;
uniform float roughness_base : hint_range(0.0, 1.0) = 0.85;
uniform float fade : hint_range(0.0, 1.0) = 0.0;
uniform int kind = 0;
uniform float rim : hint_range(0.0, 1.0) = 0.0;
// P53 (plan M11 §2.4, decision 7): the build sliders (brawn, girth; each -1 to 1) push the surface along its
// normal by the mesh's build weights (COLOR.g brawn, COLOR.b girth, stored as 0.5 + 0.5 w) times the index's
// build_max_m (stage-1 metres). No joint moves; at (0, 0) nothing does.
uniform vec2 build = vec2(0.0);
uniform float build_max_m = 0.0;
// P56 (plan M11 §2.5): a bead set holds its beads for every style with anchors, each vertex carrying its style's code
// in UV2.x; GiantLook sets the codes of the shown styles as bits, and the others' beads collapse to a point (no
// fragment). -1 (every garment and accessory): no mask.
uniform int bead_mask = -1;
const float DARK_FLOOR = 0.035;
const vec3 BONE = vec3(0.62, 0.56, 0.45);   // linear: an aged, sun-yellowed bone
uniform vec4 tint = vec4(1.0, 1.0, 1.0, 0.0);
uniform vec3 flash = vec3(0.0);

#include "res://assets/shaders/giant_first_person.gdshaderinc"
varying vec3 v_fp_pos;
varying flat float v_fp_on;

void vertex() {
	if (bead_mask >= 0 && ((bead_mask >> int(UV2.x + 0.5)) & 1) == 0) {
		VERTEX = vec3(0.0);   // P56: a bead of a style not shown
	}
	v_fp_pos = VERTEX;
	VERTEX += NORMAL * dot(COLOR.gb * 2.0 - 1.0, build) * build_max_m;   // P53: the build sliders
	v_fp_on = fp_in_head(fp_camera_mesh(MODEL_MATRIX, CAMERA_POSITION_WORLD)) * fp_region_shown(clamp(int(COLOR.r * 16.0), 0, 15));
}

void fragment() {
	if (fp_shoulders_hidden(v_fp_pos, v_fp_on, FRAGCOORD.xy)) {
		discard;   // first person: a sleeve fades out towards the shoulder with the arm in it
	}
	if (fade > 0.0) {
		float h = fract(sin(dot(floor(FRAGCOORD.xy), vec2(12.9898, 78.233))) * 43758.5453);
		if (h < fade * 0.85) {
			discard;
		}
	}
	vec4 t = texture(detail_tex, UV * detail_scale);
	float d = t.a / 0.75;   // 1 = the dye itself
	// the detail scales the dye and, a little, lifts or sinks it, so it also shows on the darkest dyes (P46)
	vec3 cloth = dye_color * mix(1.0, d, detail_strength) + vec3((d - 1.0) * detail_strength * 0.07);
	cloth = max(cloth, vec3(DARK_FLOOR) * mix(vec3(1.0), dye_color / max(max(dye_color.r, dye_color.g), max(dye_color.b, 0.001)), 0.5));
	ALBEDO = cloth * mix(vec3(1.0), tint.rgb, clamp(tint.a, 0.0, 1.0));
	ROUGHNESS = clamp(roughness_base + (1.0 - d) * 0.1, 0.0, 1.0);
	if (kind == 1) {
		// P54: without reflections to mirror (the world's sky is a colour, the creator's backdrop dark) a fully
		// metallic surface drew black: the metal keeps a part of its colour as diffuse, and the gaps between rings and
		// scales are dark and dull, not bright metal
		METALLIC = 0.55 * smoothstep(0.35, 0.75, d);
		ROUGHNESS = clamp(0.36 + (1.0 - d) * 0.4, 0.0, 1.0);
		SPECULAR = 0.65;
	} else if (kind == 2) {
		ALBEDO = BONE * mix(vec3(1.0), dye_color / max(max(dye_color.r, dye_color.g), max(dye_color.b, 0.001)), 0.15)
			* mix(1.0, d, detail_strength) * mix(vec3(1.0), tint.rgb, clamp(tint.a, 0.0, 1.0));
		ROUGHNESS = clamp(0.45 + (1.0 - d) * 0.2, 0.0, 1.0);
		SPECULAR = 0.35;
	}
	RIM = rim;
	RIM_TINT = 0.6;
	NORMAL_MAP = t.rgb;
	NORMAL_MAP_DEPTH = normal_strength;
	EMISSION = flash;
}
