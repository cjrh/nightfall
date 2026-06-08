shader_type canvas_item;

uniform sampler2D depth_texture : hint_default_white, filter_linear, repeat_disable;
uniform float variance_threshold = 0.0004;
uniform float edge_threshold = 0.05;
uniform float edge_density_req = 0.5;

void fragment() {
	vec2 texel = 1.0 / vec2(textureSize(depth_texture, 0));
	vec2 uv = clamp(UV, vec2(texel * 3.0), vec2(1.0 - texel * 3.0));

	float mu = 0.0;
	float mu2 = 0.0;
	for (int dy = -2; dy <= 2; dy++) {
		for (int dx = -2; dx <= 2; dx++) {
			float d = texture(depth_texture, uv + vec2(float(dx), float(dy)) * texel).r;
			mu += d;
			mu2 += d * d;
		}
	}
	mu /= 25.0;
	mu2 /= 25.0;
	float variance = mu2 - mu * mu;
	float flatness = 1.0 - smoothstep(0.0, variance_threshold, variance);

	int edge_count = 0;
	for (int a = 0; a < 16; a++) {
		float angle = float(a) * 3.14159265 * 2.0 / 16.0;
		vec2 ring_uv = uv + vec2(cos(angle), sin(angle)) * texel * 5.0;
		float d_ring = texture(depth_texture, clamp(ring_uv, vec2(0.0), vec2(1.0))).r;
		if (abs(d_ring - mu) > edge_threshold) {
			edge_count++;
		}
	}
	float edge_density = float(edge_count) / 16.0;

	float gx = 0.0;
	float gy = 0.0;
	gx += texture(depth_texture, uv + vec2(-texel.x, -texel.y)).r * -1.0;
	gx += texture(depth_texture, uv + vec2(-texel.x, 0.0)).r * -2.0;
	gx += texture(depth_texture, uv + vec2(-texel.x, texel.y)).r * -1.0;
	gx += texture(depth_texture, uv + vec2( texel.x, -texel.y)).r * 1.0;
	gx += texture(depth_texture, uv + vec2( texel.x, 0.0)).r * 2.0;
	gx += texture(depth_texture, uv + vec2( texel.x, texel.y)).r * 1.0;
	gy += texture(depth_texture, uv + vec2(-texel.x, -texel.y)).r * -1.0;
	gy += texture(depth_texture, uv + vec2(0.0, -texel.y)).r * -2.0;
	gy += texture(depth_texture, uv + vec2( texel.x, -texel.y)).r * -1.0;
	gy += texture(depth_texture, uv + vec2(-texel.x, texel.y)).r * 1.0;
	gy += texture(depth_texture, uv + vec2(0.0, texel.y)).r * 2.0;
	gy += texture(depth_texture, uv + vec2( texel.x, texel.y)).r * 1.0;
	float gradient_mag = abs(gx) + abs(gy);

	bool is_flat = variance < variance_threshold;
	bool is_edge_bounded = edge_density > edge_density_req;
	bool is_interior = gradient_mag < 0.01;

	float mask = 0.0;
	if (is_flat && is_edge_bounded && is_interior) {
		mask = 1.0;
	}

	float local_min = 1.0;
	float local_max = 0.0;
	for (int dy = -1; dy <= 1; dy++) {
		for (int dx = -1; dx <= 1; dx++) {
			float d = texture(depth_texture, uv + vec2(float(dx), float(dy)) * texel).r;
			local_min = min(local_min, d);
			local_max = max(local_max, d);
		}
	}
	if ((local_max - local_min) < 0.005 && (mu < 0.03 || mu > 0.97)) {
		mask = 1.0;
	}

	float dilated = mask;
	for (int dy = -1; dy <= 1; dy++) {
		for (int dx = -1; dx <= 1; dx++) {
			if (texture(depth_texture, uv + vec2(float(dx), float(dy)) * texel).r > 0.0) {
				vec2 n_uv = clamp(uv + vec2(float(dx), float(dy)) * texel * 2.0, vec2(0.0), vec2(1.0));
			}
		}
	}

	COLOR = vec4(vec3(mask), 1.0);
}
