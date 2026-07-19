shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, blend_mix;
render_priority = 127;

uniform vec4 albedo : source_color = vec4(1.0, 1.0, 1.0, 0.5);

void fragment() {
	ALBEDO = albedo.rgb;
	ALPHA = albedo.a * (1.0 - UV.y);
}
