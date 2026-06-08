shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled;

void fragment() {
	float glow = smoothstep(0.5, 0.0, length(UV - 0.5));
	vec3 col = vec3(0.5, 0.7, 1.0);
	ALBEDO = col;
	EMISSION = col * glow * 3.0;
	ALPHA = glow;
}
