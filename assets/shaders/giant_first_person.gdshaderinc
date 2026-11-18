// First person and the shoulders (the M10 gate's LC-3; docs/systems/P46.md): shared by giant_skin.gdshader and
// giant_cloth.gdshader. In first person the camera stands inside the head, the torso and the head are culled
// (render layers 2 and 3) and only the limbs draw. Looking down past about 55 degrees the arms' shoulder ends
// came into the lower corners of the frame: the flat caps that close the limb mesh at the shoulder cuts, and
// the cut loop's saw-toothed rim. Nothing that belongs in that place can be drawn there (the chest is culled),
// so the limbs fade out towards the shoulders instead: while the camera stands inside the head, every limb
// fragment inside a box round the shoulders (below and behind the eye) is discarded, dithered over FP_FADE_M so
// the arm ends in a soft edge that follows no triangle. Distances are in the mesh's own space (stage 1 metres:
// the model's scale is divided out), so the rule is the same at every stage. A third-person camera stands outside
// the head box; one pressed into it (a wall behind the giant) hides the shoulders as first person does. A shadow
// pass's camera is the light, so the giant's shadow keeps its shoulders.

// The head box: where the camera must stand for the rule to apply (mesh space: +Y up, +Z the giant's front).
const vec3 FP_HEAD_MIN = vec3(-0.35, 3.0, -0.35);
const vec3 FP_HEAD_MAX = vec3(0.35, 3.85, 0.6);
// The shoulder box, relative to the camera: its centre and half extents. It holds both shoulder caps (0.32 to
// 0.48 m out, 0.17 to 0.57 m under the game's eye, from the eye's plane to 0.4 m behind it) with a margin for
// the idle's and the walk's sway.
const vec3 FP_BOX_CENTRE = vec3(0.0, -0.36, -0.22);
const vec3 FP_BOX_HALF = vec3(0.58, 0.24, 0.38);
const float FP_FADE_M = 0.12;

// A shader that includes this declares `varying vec3 v_fp_rel; varying flat float v_fp_on;` and sets them in
// vertex() (a varying may only be assigned there):
//   vec3 fp_cam = fp_camera_mesh(MODEL_MATRIX, CAMERA_POSITION_WORLD);
//   v_fp_rel = VERTEX - fp_cam;
//   v_fp_on = fp_in_head(fp_cam);
// and discards in fragment() when fp_shoulders_hidden(v_fp_rel, v_fp_on, FRAGCOORD.xy).

// The camera in the mesh's own space (the model's uniform scale divided out).
vec3 fp_camera_mesh(mat4 model, vec3 camera_world) {
	mat3 m = mat3(model);
	float k2 = max(dot(m[0], m[0]), 1e-8);
	return ((camera_world - model[3].xyz) * m) / k2;
}

// 1 when the camera stands inside the head box.
float fp_in_head(vec3 cam) {
	return (all(greaterThan(cam, FP_HEAD_MIN)) && all(lessThan(cam, FP_HEAD_MAX))) ? 1.0 : 0.0;
}

// True when this fragment is to be discarded: inside the shoulder box, or the dither's share of the fade round it.
bool fp_shoulders_hidden(vec3 rel, float on, vec2 fragcoord) {
	if (on < 0.5) {
		return false;
	}
	vec3 q = abs(rel - FP_BOX_CENTRE) - FP_BOX_HALF;
	float sd = length(max(q, vec3(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
	if (sd >= FP_FADE_M) {
		return false;
	}
	float hide = 1.0 - clamp(sd / FP_FADE_M, 0.0, 1.0);
	float h = fract(52.9829189 * fract(dot(floor(fragcoord), vec2(0.06711056, 0.00583715))));
	return hide >= h;
}
