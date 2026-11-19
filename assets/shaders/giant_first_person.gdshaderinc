// First person and the shoulders (the M10 gate's LC-3; docs/systems/P46.md): shared by giant_skin.gdshader and
// giant_cloth.gdshader. In first person the camera stands inside the head, the torso and the head are culled
// (render layers 2 and 3) and only the limbs draw. Looking down past about 55 degrees the arms' shoulder ends
// came into the lower corners of the frame: the flat caps that close the limb mesh at the shoulder cuts, and
// the cut loop's saw-toothed rim. Nothing that belongs in that place can be drawn there (the chest is culled),
// so the limbs fade out towards the shoulders instead: while the camera stands inside the head, every limb
// fragment inside a box round the shoulders is discarded, dithered over FP_FADE_M so
// the arm ends in a soft edge that follows no triangle. Distances are in the mesh's own space (stage 1 metres:
// the model's scale is divided out), so the rule is the same at every stage. A third-person camera stands outside
// the head box; one pressed into it (a wall behind the giant) hides the shoulders as first person does. A shadow
// pass's camera is the light, so the giant's shadow keeps its shoulders.

// The head box: where the camera must stand for the rule to apply (mesh space: +Y up, +Z the giant's front).
const vec3 FP_HEAD_MIN = vec3(-0.35, 3.0, -0.35);
const vec3 FP_HEAD_MAX = vec3(0.35, 3.85, 0.6);
// The shoulder box in the mesh's own space (the model, not the camera: the camera's bob while walking must not
// move it): its centre and half extents. It holds both shoulder caps (0.32 to 0.48 m out, 2.80 to 3.20 m up,
// 0.21 m behind the shoulder joint to 0.20 m in front of it) with a margin for the walk's and the run's lean.
const vec3 FP_BOX_CENTRE = vec3(0.0, 3.0, 0.0);
const vec3 FP_BOX_HALF = vec3(0.58, 0.25, 0.40);
const float FP_FADE_M = 0.12;

// A shader that includes this declares `varying vec3 v_fp_pos; varying flat float v_fp_on;` and sets them in
// vertex() (a varying may only be assigned there):
//   v_fp_pos = VERTEX;
//   v_fp_on = fp_in_head(fp_camera_mesh(MODEL_MATRIX, CAMERA_POSITION_WORLD));
// and discards in fragment() when fp_shoulders_hidden(v_fp_pos, v_fp_on, FRAGCOORD.xy).

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

// Gate A2: the hips. Looking down, the camera saw the flat caps that close the thighs (and, with the tunic, the
// skirt's waist) where the culled torso met them. The legs are not drawn in first person now, as the torso is not:
// a fragment whose body region (COLOR.r, kit/split.py: 7 pelvis, 11 thigh, 12 knee, 13 shin, 14 foot, 15 the caps of
// every cut) is FP_PELVIS_REGION or FP_FIRST_HIDDEN_REGION and above is discarded while the camera stands in the head, on the skin and on
// every garment over those regions (garments carry the region of the skin under them). Looking down shows the arms,
// the weapon and the whole body's shadow (the shadow pass's camera is the light). Position cannot do it: a fade
// by height dissolved the thighs into rings with the feet inside, and a column round the legs cut the hanging
// hands, which reach the same x. A shader that includes this passes its vertex's region:
//   v_fp_on = fp_in_head(...) * fp_region_shown(region)   - 0 hides nothing, as before.
const int FP_FIRST_HIDDEN_REGION = 11;
// The pelvis is the torso's (culled), but a limb garment's hip rim takes the region of the skin nearest it.
const int FP_PELVIS_REGION = 7;

// -1 for a vertex of a region first person does not draw (times fp_in_head: -1 in first person, 0 outside), else 1.
float fp_region_shown(int region) {
	return (region >= FP_FIRST_HIDDEN_REGION || region == FP_PELVIS_REGION) ? -1.0 : 1.0;
}

// True when this fragment is to be discarded: inside the shoulder box, or the dither's share of the fade round it.
bool fp_shoulders_hidden(vec3 pos, float on, vec2 fragcoord) {
	if (on < -0.5) {
		return true;   // first person: a leg or a cap (fp_region_shown)
	}
	if (on < 0.5) {
		return false;
	}
	vec3 q = abs(pos - FP_BOX_CENTRE) - FP_BOX_HALF;
	float sd = length(max(q, vec3(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
	if (sd >= FP_FADE_M) {
		return false;
	}
	float hide = 1.0 - clamp(sd / FP_FADE_M, 0.0, 1.0);
	float h = fract(52.9829189 * fract(dot(floor(fragcoord), vec2(0.06711056, 0.00583715))));
	return hide >= h;
}
