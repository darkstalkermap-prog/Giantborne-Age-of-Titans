// The giant's eyes (P42; plan M10 §2.8): Eyes. Ported from the asset research's eye shader: the iris is
// drawn here, no texture. UV.y is the polar angle / pi from the pupil (the low-poly eye sphere's pole
// looks along the gaze), UV.x the azimuth. iris_glow lights the iris a little (the Stormborn eyes).
// RigPaint's tint and flash as on every giant shader.
shader_type spatial;
render_mode cull_back;

uniform vec3 iris_color : source_color = vec3(0.30, 0.45, 0.38);
uniform float iris_glow : hint_range(0.0, 1.0) = 0.0;
uniform float pupil_size : hint_range(0.02, 0.12) = 0.055;
uniform vec3 iris_inner : source_color = vec3(0.55, 0.42, 0.20);
uniform vec3 sclera : source_color = vec3(0.86, 0.82, 0.78);
uniform float iris_r = 0.165;
uniform vec4 tint = vec4(1.0, 1.0, 1.0, 0.0);
uniform vec3 flash = vec3(0.0);

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

void fragment() {
	float r = UV.y;
	float az = UV.x * 64.0;
	float streak = mix(hash(floor(az)), hash(floor(az) + 1.0), fract(az));
	vec3 iris = mix(iris_inner, iris_color, smoothstep(pupil_size, iris_r * 0.9, r)) * (0.75 + 0.5 * streak);
	iris *= 1.0 - 0.6 * smoothstep(iris_r * 0.8, iris_r, r);   // limbal ring
	float in_iris = 1.0 - smoothstep(iris_r * 0.97, iris_r * 1.06, r);
	vec3 c = mix(sclera, iris, in_iris);
	float pupil = 1.0 - smoothstep(pupil_size * 0.9, pupil_size * 1.1, r);
	c = mix(c, vec3(0.02), pupil);
	c = mix(c, c * vec3(1.0, 0.75, 0.72), smoothstep(0.35, 0.55, r));   // redder towards the corners
	ALBEDO = c * mix(vec3(1.0), tint.rgb, clamp(tint.a, 0.0, 1.0));
	ROUGHNESS = 0.08;
	SPECULAR = 0.6;
	EMISSION = flash + iris_color * iris_glow * in_iris * (1.0 - pupil);
}
