// C3: a discovered waystone's beam - a column of pale light standing from its stone into the sky, seen from far off at
// every growth stage: unshaded and added onto what is behind it, brightest at its foot and fading to nothing at its
// top (its local height over `height`), softest at its edges (the view-facing rim), its light drifting slowly up.
// `strength` 0..1 (WaystoneLook fades it in when the stone is first reached). C3b: `unlit` draws an open stone's
// column before it is reached - grey and faint, breathing slowly instead of shimmering.
shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

uniform vec3 beam_color : source_color = vec3(0.55, 0.85, 1.0);
uniform float strength : hint_range(0.0, 1.0) = 1.0;
uniform float height = 90.0;
// C3b: 1 = an open stone not yet reached - a faint grey column, no shimmer, breathing slowly (WaystoneLook)
uniform float unlit : hint_range(0.0, 1.0) = 0.0;

varying vec3 world_nrm;
varying vec3 world_pos;
varying float up;

void vertex() {
	up = clamp(VERTEX.y / height + 0.5, 0.0, 1.0);
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 to_cam = normalize(CAMERA_POSITION_WORLD - world_pos);
	float rim = abs(dot(normalize(vec3(world_nrm.x, 0.0, world_nrm.z)), normalize(vec3(to_cam.x, 0.0, to_cam.z))));
	float fall = pow(1.0 - up, 1.6);
	float drift = mix(0.8 + 0.2 * sin(up * 30.0 - TIME * 1.4), 0.75 + 0.25 * sin(TIME * 0.9), unlit);
	// near the camera it thins (a giant beside his stone is not blinded by it); far off it reads at full strength
	float far = mix(0.25, 1.0, smoothstep(30.0, 180.0, length(CAMERA_POSITION_WORLD - world_pos)));
	ALBEDO = beam_color * fall * rim * rim * drift * strength * far * 0.85;
}
