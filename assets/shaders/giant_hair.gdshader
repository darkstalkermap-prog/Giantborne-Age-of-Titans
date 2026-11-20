// The giant's hair and beard cards (P42; plan M10 §2.8, decision 12): Hair_* and Beard_*. Ported from
// the asset research's card shader. Cards drawn with a depth pre-pass and a blended fringe (no alpha to
// coverage in the Compatibility renderer). The colour is a uniform: the hair's (or the beard's) colour,
// sun-bleached tips, a fraction of grey strands (the atlas's G is a per-strand id), darker roots, a
// Kajiya-Kay highlight along the strands, and an alpha boost with the mip level so far cards do not thin
// out. The look pass (P46): the cards' sides feather, each strand of the atlas ends at its own length, the
// cards share a rounded shading normal on both faces and take little of each other's shadow, so a lock
// reads as hair and not as shingles; the tips sway behind the head's motion. The M10 gate (LC-6): a card's
// root edge feathers strand by strand (the hairline and the beard's cheek line were rows of straight card
// ends), a long beard's tips thin strand by strand (tip_thin), and a beard fades out as the camera comes round
// behind the head (back_fade: its cards showed as loose squares beside the neck from behind; the skin under
// them carries the beard's colour). RigPaint's tint and flash as on every giant shader.
//
// The look pass II (P51; plan M11 §2.4, decision 8): a style shades as one volume - the mesh's normal is the
// head-centred normal the kit bakes (outward from the head's centre above it, from a vertical axis through it
// below), and volume_normal blends the card's own facing (its triangle's, from the screen derivatives) towards
// it; two highlights along the strands (spec_primary: white, shifted towards the tip by spec_shift;
// spec_secondary: tinted by the hair's colour, shifted towards the root by spec_shift_2, broader), both
// jittered per strand by strand_noise so they glint instead of banding; less of the cards' shadow on each other
// and a little light through the edges against the light. Braids (UV2.x = 1: tubes) and beads (UV2.x = 2) ride in
// the same draw call: a braid takes its tube's normal and the atlas's dense column as its strands, a bead is
// opaque bone with a rim of light. back_fade is kept for compatibility and no longer set on beards: from behind a
// beard shows its closed under-jaw cards.
shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha;

uniform sampler2D hair_atlas : filter_linear_mipmap, repeat_disable;   // A coverage, R brightness, G strand id
uniform vec3 hair_color : source_color = vec3(0.29, 0.17, 0.10);
uniform vec3 tip_color : source_color = vec3(0.43, 0.29, 0.19);
uniform float grey : hint_range(0.0, 1.0) = 0.12;
uniform float spec_shift = -0.12;
uniform float alpha_boost = 0.25;
uniform float atlas_px = 512.0;
uniform float spec_strength = 0.05;   // M10's single highlight; unused since P51 (spec_primary, spec_secondary)
uniform float spec_power = 48.0;
uniform float volume_normal : hint_range(0.0, 1.0) = 0.75;
uniform float spec_primary = 0.05;
uniform float spec_secondary = 0.025;
uniform float spec_shift_2 = 0.10;
uniform float strand_noise = 0.12;
// P51: the strands' coverage over the atlas's (a style shaded as a volume shows the scalp through thin cards more)
uniform float density = 1.3;
uniform vec3 bead_color : source_color = vec3(0.56, 0.50, 0.40);
// The style's cut (P46): the share of every card's length that is drawn; the cut end thins out like a tip.
uniform float length : hint_range(0.0, 1.0) = 1.0;
uniform float shadow_soft = 0.8;
uniform float side_feather = 0.22;
uniform float root_dark = 0.82;
// The M10 gate (LC-6). root_feather: the share of a card's length over which it fades in from its root, each
// strand offset by its id. tip_thin: the share of the length over which the strands end one by one (GiantLook
// sets BEARD_TIP_THIN on the long beards). back_fade: 1 on a beard (GiantLook), which then fades out between
// BACK_FADE_FROM and BACK_FADE_TO of the camera's direction along the mesh's front (+Z): 0 from the side,
// -1 from straight behind.
uniform float root_feather = 0.14;
uniform float tip_thin : hint_range(0.0, 1.0) = 0.0;
uniform float back_fade : hint_range(0.0, 1.0) = 0.0;
const float BACK_FADE_FROM = -0.35;
const float BACK_FADE_TO = -0.7;
const float BEARD_LOCKS = 7.0;   // the third look lane: the locks a beard card breaks into across its width
const float BEARD_ROOT_FLOOR = 0.0;      // ... from this cover at the root (0: from the skin)
const float BEARD_ROOT_FEATHER = 0.42;   // the fifth look lane: the share of a beard card its strands fade in over
const float BEARD_STRANDS = 6.0;     // the fourth look lane: the strands a lock is drawn with
const float BEARD_EDGE_ALPHA = 0.85; // ... and the share of a card's cover left where it is seen edge-on
const float TIP_TAPER = 0.12;   // the second look lane: how much the side feather widens at a beard card's tip
uniform float atlas_columns = 4.0;
uniform vec4 tint = vec4(1.0, 1.0, 1.0, 0.0);
uniform vec3 flash = vec3(0.0);

// The sway (P46): the head's motion in the mesh's own space, eased and scaled by GiantLook.sway (metres at
// the tips, stage 1); a card's root stays on the head and its tip lags behind the head's motion.
uniform vec3 head_motion = vec3(0.0);

varying vec3 v_strand;
varying float v_behind;
varying float v_sid;
varying float v_kind;
varying float v_edge;

void vertex() {
	v_kind = UV2.x;
	VERTEX -= head_motion * UV.y * UV.y * step(v_kind, 0.5);
	// where the camera stands along the mesh's front: 1 in front of the giant, 0 beside him, -1 behind
	mat3 m = mat3(MODEL_MATRIX);
	vec3 to_cam = (CAMERA_POSITION_WORLD - MODEL_MATRIX[3].xyz) * m / max(dot(m[0], m[0]), 1e-8) - VERTEX;
	v_behind = to_cam.z / max(length(to_cam), 1e-5);
}

void fragment() {
	vec4 t = texture(hair_atlas, UV);
	vec2 dx = dFdx(UV * atlas_px);
	vec2 dy = dFdy(UV * atlas_px);
	float mip = 0.5 * log2(max(max(dot(dx, dx), dot(dy, dy)), 1e-6));
	float sid = t.g - 0.5;
	// A card carries the head-centred normal under it; seen from its back it keeps that normal (the engine
	// flips it), so every card of a lock is lit alike whichever side faces the camera.
	vec3 n = FRONT_FACING ? NORMAL : -NORMAL;
	// the card's own facing (its triangle), taken outside every branch (derivatives in uniform control flow)
	vec3 geo = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	// P56: the strand's way along the card, root to tip, from the screen derivatives of the position and of UV.y: the
	// renderer's blend shapes (the face keys) lose the tangent's sign, so BINORMAL alone flipped every card's highlight
	// at any key's weight; BINORMAL is turned to point to the tip whatever its sign (as most cards' did before)
	vec3 dpx = dFdx(VERTEX);
	vec3 dpy = dFdy(VERTEX);
	vec2 dux = dFdx(UV);
	vec2 duy = dFdy(UV);
	vec3 to_tip = (dpy * dux.x - dpx * duy.x) * sign(dux.x * duy.y - duy.x * dux.y);
	vec3 strand = normalize(BINORMAL) * (dot(BINORMAL, to_tip) < 0.0 ? -1.0 : 1.0);
	if (v_kind > 1.5) {
		// a bead: opaque, the bead's colour, the tube's own normal
		ALPHA = 1.0;
		ALBEDO = bead_color * (0.85 + 0.3 * t.r) * mix(vec3(1.0), tint.rgb, clamp(tint.a, 0.0, 1.0));
		ROUGHNESS = 0.35;
		SPECULAR = 0.5;
		EMISSION = flash;
		NORMAL = n;
		v_strand = strand;
		v_sid = 0.0;
		v_edge = 0.0;
	} else {
		float a;
		float lock_shade = 0.5;
		if (v_kind > 0.5) {
			// a braid's tube: the dense strands wrap round it; only its tie end thins out
			a = clamp(0.55 + t.a, 0.0, 1.0) * (1.0 - smoothstep(0.9, 1.0, UV.y) * 0.8);
		} else {
			a = clamp(t.a * (1.0 + max(mip, 0.0) * alpha_boost) * density, 0.0, 1.0);
			// The card's sides feather and its last part fades, so no card shows its outline over its neighbours
			// (the atlas's strands end at their own lengths, so the tip thins out strand by strand).
			a *= 1.0 - smoothstep(0.82, 1.0, UV.y) * 0.6;
			float u = fract(UV.x * atlas_columns);
			// the second look lane: on a beard (tip_thin set) the feather widens towards the tip, so a card narrows to a
			// point (the short cards of the beards ended square at the cheeks, a row of blocks from the side)
			float sf = side_feather + TIP_TAPER * UV.y * UV.y * step(0.001, tip_thin);
			a *= smoothstep(0.0, sf, u) * smoothstep(0.0, sf, 1.0 - u);
			// The root edge and the tip, strand by strand: each strand starts and ends at its own place along the card
			// (its id, the atlas's G); minified, the ids blend and the edge is a plain ramp.
			// (the fifth look lane: on a beard over a longer share, strand by strand - each card's root stood off the
			// skin as a straight edge: from the side the cheek was a staircase of shingles)
			float beard = step(0.001, tip_thin);
			float rr = mix(smoothstep(0.0, root_feather, UV.y + sid * root_feather),
				smoothstep(0.0, BEARD_ROOT_FEATHER, UV.y + sid * BEARD_ROOT_FEATHER), beard);
			a *= BEARD_ROOT_FLOOR * beard * (1.0 - rr) + rr;
			a *= 1.0 - smoothstep(1.0 - tip_thin, 1.0, UV.y + sid * tip_thin) * step(0.001, tip_thin);
			if (tip_thin > 0.001) {
				// the third look lane: a beard card breaks into locks of its own lengths across it, whatever the atlas's
				// mip (minified, a short card was a solid spade of one colour: square patches at the cheeks)
				float lock_i = floor(u * BEARD_LOCKS) + floor(UV.x * atlas_columns) * 17.0;
				float lock_len = 0.62 + 0.38 * fract(sin(lock_i * 12.9898) * 43758.5453);
				float across = fract(u * BEARD_LOCKS);
				a *= 1.0 - smoothstep(lock_len - 0.15 * (1.0 - 0.6 * abs(across - 0.5) * 2.0), lock_len, UV.y);
				a *= mix(1.0, smoothstep(0.0, 0.25, across) * smoothstep(0.0, 0.25, 1.0 - across), smoothstep(0.8, 1.0, UV.y));
				lock_shade = fract(sin(lock_i * 78.233) * 12543.123);
				// the fourth look lane: strands drawn across the lock whatever the atlas's mip (darker between them), and a
				// card seen edge-on thins out (a short card from the side was a solid block)
				float strand_i = floor(u * BEARD_LOCKS * BEARD_STRANDS);
				lock_shade = 0.55 * lock_shade + 0.45 * fract(sin(strand_i * 91.7 + lock_i) * 24634.6);
				a *= mix(BEARD_EDGE_ALPHA, 1.0, smoothstep(0.08, 0.45, abs(dot(normalize(geo), VIEW))));
			}
			// The volume: the card's own facing (its triangle) blended towards the head-centred normal.
			geo = dot(geo, n) < 0.0 ? -geo : geo;
			n = normalize(mix(geo, n, volume_normal));
		}
		a *= 1.0 - smoothstep(length - 0.14, length, UV.y) * step(length, 0.999);
		a *= mix(1.0, smoothstep(BACK_FADE_TO, BACK_FADE_FROM, v_behind), back_fade);
		ALPHA = a;
		vec3 c = mix(hair_color, tip_color, smoothstep(0.55, 1.0, UV.y) * 0.3);
		// Grey strands by their id; where the atlas is minified a card holds many strands, so the share of
		// grey blends in instead of switching whole cards (the step drew confetti on the short styles).
		float gw = clamp(0.02 + 0.2 * max(mip, 0.0), 0.02, 0.5);
		float is_grey = (1.0 - smoothstep(grey - gw, grey + gw, t.g)) * step(0.001, grey);
		c = mix(c, vec3(0.62, 0.60, 0.57), mix(is_grey, grey, clamp(max(mip, 0.0) * 0.5, 0.0, 1.0)));
		c *= 0.62 + 0.5 * t.r;
		c *= 1.0 - 0.18 * lock_shade * step(0.001, tip_thin);   // (the fifth look lane: 0.32 drew blotches)   // (the third look lane: a beard's locks vary)
		// a little darker at the very root (the fourth look lane: not on a beard, where each short card's dark root drew
		// its outline across the cheek: a row of blocks)
		c *= mix(mix(root_dark, 1.0, 0.75 * step(0.001, tip_thin)), 1.0, smoothstep(0.0, 0.12, UV.y));
		if (v_kind > 0.5) {
			// a braid: the plait's crossing strands as chevrons round the tube, dark in their grooves
			float around = fract(UV.x * atlas_columns);
			float p = fract(UV.y * 30.0 + abs(fract(around * 3.0) - 0.5) * 1.4);
			c *= 0.55 + 0.45 * smoothstep(0.0, 0.2, p) * smoothstep(1.0, 0.75, p);
		}
		ALBEDO = c * mix(vec3(1.0), tint.rgb, clamp(tint.a, 0.0, 1.0));
		ROUGHNESS = 0.9;
		SPECULAR = 0.04;
		EMISSION = flash;
		NORMAL = n;
		v_strand = strand;
		v_sid = sid * strand_noise;
		v_edge = 1.0 - clamp(t.a, 0.0, 1.0);
	}
}

// The highlight of strands along `ts` for the half vector `h` (Kajiya-Kay, its back half faded out).
float strand_spec(vec3 ts, vec3 h, float power) {
	float th = dot(ts, h);
	return pow(sqrt(max(1.0 - th * th, 0.0)), power) * smoothstep(-1.0, 0.0, th);
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	// The cards shadow each other in patches (a shingle each); most of that shadow is left out.
	float att = mix(ATTENUATION, 1.0, shadow_soft);
	DIFFUSE_LIGHT += clamp(ndl * 0.75 + 0.25, 0.0, 1.0) * att * LIGHT_COLOR / PI;
	// light through the thin edges of a style with the light behind it
	float through = pow(clamp(dot(VIEW, -LIGHT), 0.0, 1.0), 3.0) * (0.25 + 0.5 * v_edge);
	DIFFUSE_LIGHT += hair_color * 0.5 * through * att * LIGHT_COLOR / PI;
	vec3 h = normalize(LIGHT + VIEW);
	float lit = clamp(ndl + 0.25, 0.0, 1.0) * att;
	if (v_kind > 1.5) {
		SPECULAR_LIGHT += vec3(strand_spec(normalize(v_strand), h, 24.0)) * 0.3 * lit * LIGHT_COLOR;
	} else {
		vec3 t1 = normalize(v_strand + NORMAL * (spec_shift + v_sid));
		vec3 t2 = normalize(v_strand + NORMAL * (spec_shift_2 + v_sid));
		float s1 = strand_spec(t1, h, spec_power);
		float s2 = strand_spec(t2, h, spec_power * 0.5);
		SPECULAR_LIGHT += (vec3(s1) * spec_primary + hair_color * 1.5 * s2 * spec_secondary) * lit * LIGHT_COLOR;
	}
}
