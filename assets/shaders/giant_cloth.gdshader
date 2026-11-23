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
// trophies): its own pale colour under the dye's faint stain, a soft sheen, no metal. The W33 look lane: kind 3 is fur
// (clumps, a fuzz at the rim, a silhouette broken into tufts where it turns from the eye). The second look lane: kind 4
// is leather (warm, waxed, sewn in panels), and metal mirrors a sky and a horizon (it read as dull cloth). B1: kind 5
// is cut stone with iron bands where the kit's band mask is 1 (UV2.y 0 after the glTF's flip: the Quarry set).
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
// B2: a modelled armour piece of metal (kind 1) or leather (kind 4) whose band mask (UV2.y; 0 after the glTF's V flip)
// marks its iron - straps, rivets, rings - as kind 5's does (GiantLook sets it from the index entry's "band")
uniform bool band_mask = false;
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
// The W33 look lane: a garment's mesh sits where it would over nothing; each vertex's colour alpha is its push (along
// the skin's normal) to its place over the loosest garment of every inner slot, over the mesh's push_m. GiantLook sets
// push_m to the shares of that the garments worn under it need at six knots of rest height (push_knots, stage-1 m:
// from the thighs to the shoulders; GiantLook.garment_pushes): 0 worn alone. UV2.x is the vertex's rest height over
// push_y_norm; between two knots the share eases from the one to the other.
uniform float push_m[6];
uniform float push_knots[6];
uniform float push_y_norm = 4.0;
uniform bool pushed = false;
// The W33 look lane: a ring accessory (a torc, an arm ring) shades with its own round normals and carries the skin's
// normal, the line the build sliders push it along, in its tangents (no detail normal then).
uniform bool push_tangent = false;
const float DARK_FLOOR = 0.035;
const float CLOTH_SATURATION = 0.82;   // the fourth look lane: a cloth dye's saturation kept
const float METAL_SHEEN = 2.1;   // the second look lane: the metal's mirrored sky (kind 1; the fourth: 1.6 left plate
//                                  dark in the world's light)
const float LEATHER_PANEL_M = 0.17;   // the second look lane: a leather garment's panels (stage-1 m of rest height)
const vec3 BONE = vec3(0.64, 0.55, 0.40);   // linear: an aged, sun-yellowed bone (W33: warmer; it read grey-blue)
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
	float push = 0.0;
	if (pushed) {
		float y = UV2.x * push_y_norm;
		push = push_m[5];
		for (int j = 4; j >= 0; j--) {
			if (y < push_knots[j + 1]) {
				push = mix(push_m[j], push_m[j + 1], smoothstep(push_knots[j], push_knots[j + 1], y));
			}
		}
	}
	vec3 along = push_tangent ? TANGENT : NORMAL;
	VERTEX += along * (dot(COLOR.gb * 2.0 - 1.0, build) * build_max_m + COLOR.a * push);   // P53: the build; W33: the layering
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
	vec4 clumps = vec4(0.5, 0.5, 1.0, 0.75);
	if (kind == 3) {
		// the W33 look lane: fur - the detail map again at a third of its scale for the clumps, and where the surface
		// turns away from the eye its edge breaks into tufts (a clump's thin places drop out)
		clumps = texture(detail_tex, UV * detail_scale * 0.31 + vec2(0.37, 0.11));
		float ndv = abs(dot(NORMAL, VIEW));
		if (ndv < 0.32 && clumps.a < (0.32 - ndv) * 2.6 + 0.12) {
			discard;
		}
		t.rgb = normalize(mix(t.rgb * 2.0 - 1.0, clumps.rgb * 2.0 - 1.0, 0.55)) * 0.5 + 0.5;
	}
	float d = t.a / 0.75;   // 1 = the dye itself
	// the detail scales the dye and, a little, lifts or sinks it, so it also shows on the darkest dyes (P46)
	vec3 cloth = dye_color * mix(1.0, d, detail_strength) + vec3((d - 1.0) * detail_strength * 0.07);
	cloth = max(cloth, vec3(DARK_FLOOR) * mix(vec3(1.0), dye_color / max(max(dye_color.r, dye_color.g), max(dye_color.b, 0.001)), 0.5));
	if (kind == 0) {
		// the fourth look lane: a natural dye on wool is a little greyer than its swatch, and uneven over the cloth (the
		// dyes read as flat saturated fills)
		float uneven = texture(detail_tex, UV * detail_scale * 0.043 + vec2(0.21, 0.67)).a / 0.75;
		cloth = mix(vec3(dot(cloth, vec3(0.2126, 0.7152, 0.0722))), cloth, CLOTH_SATURATION) * mix(1.0, uneven, 0.25);
	}
	ALBEDO = cloth * mix(vec3(1.0), tint.rgb, clamp(tint.a, 0.0, 1.0));
	ROUGHNESS = clamp(roughness_base + (1.0 - d) * 0.1, 0.0, 1.0);
	vec3 metal_sheen = vec3(0.0);
	if (kind == 1) {
		// P54: without reflections to mirror (the world's sky is a colour, the creator's backdrop dark) a fully
		// metallic surface drew black: the metal keeps a part of its colour as diffuse, and the gaps between rings and
		// scales are dark and dull, not bright metal
		float plate = smoothstep(0.35, 0.75, d);
		METALLIC = 0.6 * plate;   // (the fourth look lane: 0.7 drew plate near black in the world's light)
		ROUGHNESS = clamp(0.3 + (1.0 - d) * 0.45, 0.0, 1.0);
		SPECULAR = 0.7;
		// the second look lane: metal read as dull cloth (bronze as leather) under both lights - it mirrors a sky
		// above, the dark ground below and a bright horizon between (the reflection the scene does not give it),
		// tinted by the metal's own colour and stronger at grazing angles
		vec3 up_v = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
		float u = dot(reflect(-VIEW, NORMAL), up_v);
		vec3 env = mix(vec3(0.06, 0.055, 0.05), vec3(0.4, 0.44, 0.5), smoothstep(-0.3, 0.6, u))
			+ vec3(0.45) * exp(-abs(u - 0.08) * 8.0);
		float fres = 0.55 + 0.45 * pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
		metal_sheen = env * mix(cloth, vec3(dot(cloth, vec3(0.333))), 0.15) * plate * fres * METAL_SHEEN;
	} else if (kind == 2) {
		ALBEDO = BONE * mix(vec3(1.0), dye_color / max(max(dye_color.r, dye_color.g), max(dye_color.b, 0.001)), 0.15)
			* mix(1.0, d, detail_strength) * mix(vec3(1.0), tint.rgb, clamp(tint.a, 0.0, 1.0));
		ROUGHNESS = clamp(0.62 + (1.0 - d) * 0.2, 0.0, 1.0);   // (W33: duller, so it mirrors less of a cool sky)
		SPECULAR = 0.22;
	}
	if (kind == 4) {
		// the second look lane: leather - a warm, waxed hide (a soft sheen, lifted out of black) sewn in panels: on a
		// garment that carries its rest height (UV2.x; the pushed ones: a jerkin, a cuirass, boots over wraps) a seam
		// every LEATHER_PANEL_M of height, a dark groove with a row of lighter stitches beside it
		vec3 warm = cloth * vec3(1.18, 1.0, 0.8);
		cloth = max(mix(cloth, warm, 0.6), vec3(0.05, 0.035, 0.022));
		float y = UV2.x * push_y_norm;
		if (y > 0.01) {
			float row = fract(y / LEATHER_PANEL_M);
			float edge = min(row, 1.0 - row) * LEATHER_PANEL_M;
			float groove = 1.0 - smoothstep(0.004, 0.011, edge);
			float stitch_row = 1.0 - smoothstep(0.003, 0.006, abs(edge - 0.018));
			float stitch = stitch_row * step(0.55, fract(UV.x * detail_scale * 0.35 + UV.y * detail_scale * 0.35));
			cloth = cloth * (1.0 - 0.55 * groove) + vec3(0.16, 0.12, 0.08) * stitch * 0.6;
		}
		ALBEDO = cloth * mix(vec3(1.0), tint.rgb, clamp(tint.a, 0.0, 1.0));
		ROUGHNESS = clamp(0.55 + (1.0 - d) * 0.2, 0.0, 1.0);
		SPECULAR = 0.42;
	}
	if (kind == 5) {
		// B1: cut stone (the Quarry set) - its own grey, mottled at two scales of the detail map, the chisel marks of
		// the hammered map darkening its pits, matte; where UV2.y is 1 (the mesh's band mask) an iron band, which
		// takes the metal's dark sheen (the glTF's V is flipped on export: the mask's 1 arrives as UV2.y 0)
		float mottle = texture(detail_tex, UV * detail_scale * 0.11 + vec2(0.53, 0.29)).a / 0.75;
		float grain = texture(detail_tex, UV * detail_scale * 0.37 + vec2(0.13, 0.71)).a / 0.75;
		vec3 stone = dye_color * mix(0.68, 1.18, smoothstep(0.65, 1.3, mottle)) * mix(0.82, 1.08, grain)
			* mix(1.0, d, 0.6);
		// lichen-dark weathering in the low places of the mottle, a warmer tint where it is high
		stone = mix(stone * vec3(0.78, 0.8, 0.74), stone * vec3(1.04, 1.0, 0.94), smoothstep(0.8, 1.15, mottle));
		ALBEDO = stone * mix(vec3(1.0), tint.rgb, clamp(tint.a, 0.0, 1.0));
		ROUGHNESS = clamp(0.86 + (1.0 - d) * 0.1, 0.0, 1.0);
		SPECULAR = 0.25;
		if (UV2.y < 0.5) {
			vec3 iron = vec3(0.085, 0.085, 0.09) * mix(1.0, d, 0.5);
			ALBEDO = iron * mix(vec3(1.0), tint.rgb, clamp(tint.a, 0.0, 1.0));
			METALLIC = 0.55;
			ROUGHNESS = clamp(0.42 + (1.0 - d) * 0.35, 0.0, 1.0);
			SPECULAR = 0.6;
			vec3 up_s = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
			float us = dot(reflect(-VIEW, NORMAL), up_s);
			vec3 env_s = mix(vec3(0.05), vec3(0.32, 0.34, 0.38), smoothstep(-0.3, 0.6, us));
			metal_sheen = env_s * vec3(0.5) * smoothstep(0.35, 0.75, d) * 1.2;
		}
	}
	if (band_mask && kind != 5 && UV2.y < 0.5) {
		// B2: the iron of a metal or leather armour piece (as kind 5's bands)
		vec3 iron_b = vec3(0.085, 0.085, 0.09) * mix(1.0, d, 0.5);
		ALBEDO = iron_b * mix(vec3(1.0), tint.rgb, clamp(tint.a, 0.0, 1.0));
		METALLIC = 0.55;
		ROUGHNESS = clamp(0.42 + (1.0 - d) * 0.35, 0.0, 1.0);
		SPECULAR = 0.6;
		vec3 up_b = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
		float ub = dot(reflect(-VIEW, NORMAL), up_b);
		metal_sheen = mix(vec3(0.05), vec3(0.32, 0.34, 0.38), smoothstep(-0.3, 0.6, ub)) * vec3(0.5)
			* smoothstep(0.35, 0.75, d) * 1.2;
	}
	RIM = rim;
	RIM_TINT = 0.6;
	if (kind == 3) {
		float c = clumps.a / 0.75;
		ALBEDO *= mix(0.62, 1.18, smoothstep(0.55, 1.25, c));   // the clumps' roots dark, their tips light
		ROUGHNESS = 0.96;
		SPECULAR = 0.18;
		RIM = max(rim, 0.65);
		RIM_TINT = 0.35;
	}
	NORMAL_MAP = t.rgb;
	NORMAL_MAP_DEPTH = push_tangent ? 0.0 : normal_strength * (kind == 3 ? 2.2 : 1.0);
	EMISSION = flash + metal_sheen;
}
