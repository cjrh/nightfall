shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled;

void fragment() {
	float flake = smoothstep(0.5, 0.1, length(UV - 0.5));
	vec3 snow = vec3(0.95);
	ALBEDO = snow;
	EMISSION = vec3(0.5);
	ALPHA = flake;
}
