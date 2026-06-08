shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled;

void fragment() {
	float wave1 = sin(UV.x * 6.28 + TIME * 0.3) * 0.5 + 0.5;
	float wave2 = sin(UV.x * 4.0 + TIME * 0.5 + 2.0) * 0.5 + 0.5;
	float vert_fade = smoothstep(0.0, 0.25, UV.y) * smoothstep(1.0, 0.75, UV.y);
	vec3 green = vec3(0.1, 0.9, 0.4);
	vec3 cyan = vec3(0.1, 0.5, 0.9);
	vec3 purple = vec3(0.6, 0.2, 0.9);
	vec3 col = mix(green, cyan, wave1);
	col = mix(col, purple, wave2 * 0.4);
	ALBEDO = col;
	EMISSION = col * 2.0;
	ALPHA = (0.2 + 0.35 * wave1) * vert_fade;
}
