shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled;

void fragment() {
	vec3 idx = fract(VERTEX * 7.33);
	float seed = fract(dot(idx.xy, vec2(12.9898, 78.233)));
	float t = sin(TIME * (0.4 + seed * 1.2) + seed * 6.28) * 0.5 + 0.5;
	float pulse = 0.15 + 0.85 * pow(t, 3.0);
	float glow = smoothstep(0.5, 0.0, length(UV - 0.5));
	vec3 warm = vec3(1.0, 0.8, 0.2);
	vec3 green = vec3(0.4, 1.0, 0.3);
	vec3 col = mix(warm, green, seed);
	ALBEDO = col;
	EMISSION = col * pulse * glow * 3.0;
	ALPHA = pulse * glow;
}
