shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled;

void fragment() {
	float dy = fract(UV.y * 8.0 + TIME * 3.0);
	float dot_y = step(0.6, dy);
	float dot_x = step(0.4, fract(UV.x * 2.0));
	float dots = dot_x * dot_y;
	float fade_x = smoothstep(0.0, 0.15, UV.x) * smoothstep(1.0, 0.85, UV.x);
	vec3 col = vec3(0.0, 0.8, 0.9);
	ALBEDO = col;
	EMISSION = col * dots * 2.5;
	ALPHA = dots * fade_x * 0.9;
}
