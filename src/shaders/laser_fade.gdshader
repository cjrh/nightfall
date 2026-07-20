shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, blend_mix;
render_priority = 127;

uniform vec4 albedo : source_color = vec4(1.0, 1.0, 1.0, 0.5);
uniform float half_height = 0.2;

varying float fade_t;

void vertex() {
	float t = (VERTEX.y + half_height) / (half_height * 2.0);
	fade_t = clamp(t, 0.0, 1.0);
}

void fragment() {
	ALBEDO = albedo.rgb;
	ALPHA = albedo.a * (1.0 - fade_t);
}
