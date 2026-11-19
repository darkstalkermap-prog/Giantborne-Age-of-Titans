// The giant's eyes (P42; plan M10 §2.8): Eyes. Ported from the asset research's eye shader: the iris is
// drawn here, no texture. UV.y is the polar angle / pi from the pupil (the low-poly eye sphere's pole
// looks along the gaze), UV.x the azimuth. iris_glow lights the iris a little (the Stormborn eyes).
// RigPaint's tint and flash as on every giant shader.
//
// The look pass II (P51; plan M11 §2.4): `look` turns the iris (the iris and the pupil slide over the eyeball by
// up to a quarter of the iris's radius: x toward the giant's right, y up; SkinnedRig writes it toward the lock
// target, the creator toward the camera); a darker limbal ring (`limbal`); the upper lid's shadow on the eyeball
// (`lid_shadow`: the top of the visible eye darkens) and a little shade in the corners; a painted cornea
// highlight (`cornea_spec`: a small soft catch-light fixed in the view, the engine having no reflections to
// give one) and the iris a little lit through the cornea. The eyeball's frame: x the giant's left (azimuth 0),
// y up (azimuth a quarter turn), the pole along the gaze.
shader_type spatial;
render_mode cull_back;

uniform vec3 iris_color : source_color = vec3(0.30, 0.45, 0.38);
uniform float iris_glow : hint_range(0.0, 1.0) = 0.0;
uniform float pupil_size : hint_range(0.02, 0.12) = 0.055;
uniform vec3 iris_inner : source_color = vec3(0.55, 0.42, 0.20);
uniform vec3 sclera : source_color = vec3(0.86, 0.82, 0.78);
uniform float iris_r = 0.168;
uniform vec2 look = vec2(0.0);
uniform float cornea_spec : hint_range(0.0, 2.0) = 0.7;
uniform float limbal : hint_range(0.0, 1.0) = 0.6;
uniform float lid_shadow : hint_range(0.0, 1.0) = 0.6;
uniform vec4 tint = vec4(1.0, 1.0, 1.0, 0.0);
uniform vec3 flash = vec3(0.0);

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

void fragment() {
	// the eyeball's disc coordinates (x his left, y up), and the iris moved by `look`
	float ang = UV.x * 6.2831853;
	vec2 d = UV.y * vec2(cos(ang), sin(ang));
	vec2 q = d - vec2(-clamp(look.x, -0.25, 0.25), clamp(look.y, -0.25, 0.25)) * iris_r;
	float r = length(q);
	float az = (atan(q.y, q.x) / 6.2831853 + 0.5) * 64.0;
	float streak = mix(hash(floor(az)), hash(floor(az) + 1.0), fract(az));
	// The look pass (P46): the eye colours read alike, so the brown ring round the pupil takes most of its
	// colour from the iris and ends sooner, the iris is larger and brighter and keeps a little of its
	// colour under the brow's shadow.
	vec3 inner = mix(iris_color, iris_inner, 0.4);
	vec3 iris = mix(inner, iris_color, smoothstep(pupil_size, iris_r * 0.6, r)) * (0.8 + 0.5 * streak);
	iris *= 1.0 - limbal * smoothstep(iris_r * 0.72, iris_r, r);   // the limbal ring
	float in_iris = 1.0 - smoothstep(iris_r * 0.97, iris_r * 1.06, r);
	// the sclera: off-white, redder and darker towards the corners
	vec3 white = mix(sclera * 0.88, sclera * vec3(0.9, 0.72, 0.68), smoothstep(0.22, 0.5, UV.y));
	vec3 c = mix(white, iris, in_iris);
	float pupil = 1.0 - smoothstep(pupil_size * 0.9, pupil_size * 1.1, r);
	c = mix(c, vec3(0.015), pupil);
	// the upper lid's shadow (the top of the eye: its normal turned up in the view) and the corners' shade
	float shade = 1.0 - lid_shadow * smoothstep(-0.1, 0.12, d.y) - 0.3 * smoothstep(0.2, 0.42, UV.y);
	c *= clamp(shade, 0.2, 1.0);
	ALBEDO = c * mix(vec3(1.0), tint.rgb, clamp(tint.a, 0.0, 1.0));
	ROUGHNESS = 0.08;
	SPECULAR = 0.6;
	// the cornea's catch-light: a small soft spot painted on the iris's upper outer edge (it turns with the eye)
	float catch_light = 1.0 - smoothstep(0.016, 0.03, length(q - vec2(0.3, 0.25) * iris_r));
	EMISSION = flash + iris_color * (iris_glow + 0.06) * in_iris * (1.0 - pupil) + vec3(cornea_spec * catch_light);
}
