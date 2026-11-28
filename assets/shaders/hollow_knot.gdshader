shader_type spatial;
// E3: the oath-knot in the Hollow Titan's breast and the chains it drives the shell with (HollowModel): old dark iron lit
// from inside its links by a pale gold that pulses slowly, brighter at the knot's heart; `glow` how bright (dimmer while
// his breastplate covers it, brighter as his echo fills), `life` 1 .. 0 at his fall. Presentation only.

uniform float glow = 0.6;
uniform float life : hint_range(0.0, 1.0) = 1.0;
uniform vec3 oath_light : source_color = vec3(1.0, 0.7, 0.32);
uniform vec3 centre = vec3(0.0, 24.4, 1.4);

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	float d = length(local_pos - centre);
	float heart = exp(-d * d * 0.12);
	float pulse = 0.75 + 0.25 * sin(TIME * 1.7 + d * 0.9);
	ALBEDO = vec3(0.09, 0.085, 0.08);
	METALLIC = 0.7;
	ROUGHNESS = 0.55;
	EMISSION = oath_light * glow * life * pulse * (0.12 + 0.9 * heart) * (0.4 + 0.6 * COLOR.r);
}
