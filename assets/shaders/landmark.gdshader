// C3: the waystones' and the forges' own material (tools/builders/landmark_mesh.gd builds their meshes: no texture,
// no UV). The vertex colour is the base colour; its alpha says what the face is made of:
//   1.0  stone - the colour worn uneven in world space, lichen in blotches on what faces up, grime run down the faces,
//        fine dark cracks, the normal roughened a little;
//   0.75 wood - grain along the part's long axis (world y or x), darker in its joins;
//   0.5  iron - dark, a little metallic, rust in patches;
//   0.3  leather and earth - matte, mottled;
//   0.15 a glowing face - runes cut in a waystone, a forge's coals and flame: `glow_color` x `glow` (0 dark: a closed
//        waystone's runes, a cold forge's ashes), flickering with `flicker`.
// Detail fades with distance (the faces read as their colour far off, as the world's merged meshes do).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec3 glow_color : source_color = vec3(0.45, 0.85, 1.0);
uniform float glow : hint_range(0.0, 4.0) = 1.0;
uniform float flicker : hint_range(0.0, 1.0) = 0.0;
uniform float pulse : hint_range(0.0, 1.0) = 0.0;

varying vec3 world_pos;
varying vec3 world_nrm;
varying float view_dist;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	return 0.55 * noise3(p) + 0.3 * noise3(p * 2.03 + 7.1) + 0.15 * noise3(p * 4.11 + 3.7);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	view_dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

void fragment() {
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;   // (the kit's faces are wound either way: each is lit from the side it is seen from)
	}
	vec3 c = COLOR.rgb;
	float kind = COLOR.a;
	float detail = 1.0 - smoothstep(60.0, 260.0, view_dist);
	float rough = 0.95;
	float metal = 0.0;
	vec3 emit = vec3(0.0);
	float n = fbm(world_pos * 0.45);
	float fine = noise3(world_pos * 3.7);
	if (kind > 0.88) {
		// stone
		c *= mix(1.0, 0.78 + 0.42 * n, detail);
		float up = clamp(world_nrm.y, 0.0, 1.0);
		float lichen = smoothstep(0.58, 0.72, fbm(world_pos * 0.9 + 11.0)) * smoothstep(0.25, 0.7, up + 0.25 * fine);
		c = mix(c, mix(vec3(0.42, 0.46, 0.30), vec3(0.56, 0.54, 0.38), fine), lichen * 0.75 * detail);
		float grime = smoothstep(0.45, 0.8, noise3(vec3(world_pos.x * 1.3, world_pos.y * 0.18, world_pos.z * 1.3))) * (1.0 - up);
		c = mix(c, c * 0.62, grime * 0.6 * detail);
		float crack = smoothstep(0.035, 0.0, abs(noise3(world_pos * 1.6) - 0.5)) * detail;
		c *= 1.0 - 0.45 * crack;
	} else if (kind > 0.62) {
		// wood: grain along the longer axis of the face's world position (posts stand, beams lie)
		float g = noise3(vec3(world_pos.x * 7.0, world_pos.y * 0.6, world_pos.z * 7.0));
		c *= mix(1.0, 0.75 + 0.45 * g, detail);
		c *= mix(1.0, 0.85 + 0.2 * fine, detail);
		rough = 0.85;
	} else if (kind > 0.4) {
		// iron
		float rust = smoothstep(0.55, 0.75, fbm(world_pos * 1.8 + 3.0)) * detail;
		c = mix(c, vec3(0.36, 0.20, 0.11), rust * 0.6);
		c *= 0.9 + 0.2 * fine;
		rough = mix(0.45, 0.85, rust);
		metal = mix(0.65, 0.2, rust);
	} else if (kind > 0.22) {
		// leather, earth
		c *= mix(1.0, 0.8 + 0.35 * n, detail);
		rough = 0.9;
	} else {
		// a glowing face: runes, coals, flame
		float t = TIME;
		float fl = 1.0 - flicker * (0.35 * noise3(vec3(world_pos.xz * 0.7, t * 3.1)) + 0.15 * sin(t * 13.0 + world_pos.x * 2.0));
		float pl = 1.0 - pulse * 0.35 * (0.5 + 0.5 * sin(t * 1.6));
		float bed = 0.75 + 0.5 * noise3(world_pos * 2.2 + vec3(0.0, t * 0.6 * flicker, 0.0));
		emit = glow_color * glow * fl * pl * bed;
		c = mix(c * 0.25, glow_color, clamp(glow, 0.0, 1.0) * 0.6);
		rough = 0.7;
	}
	ALBEDO = c;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = emit;
}
