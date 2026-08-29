shader_type canvas_item;

uniform vec4 glow_color : source_color = vec4(0.25, 0.62, 1.0, 0.95);
uniform vec4 core_color : source_color = vec4(0.75, 0.90, 1.0, 1.0);
uniform vec2 rect_size = vec2(96.0, 128.0);
uniform float corner_radius = 1.0;
uniform float border_width = 2.0;
uniform float glow_width = 6.0;
uniform float pulse_speed = 3.2;
uniform float pulse_intensity = 0.15;

// Exact 2D Signed Distance Function for a rounded/square box
float sd_rounded_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + vec2(r);
	return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

void fragment() {
	vec2 padded_size = rect_size + vec2(glow_width * 2.0);
	vec2 p = (UV - 0.5) * padded_size;
	vec2 half_rect = rect_size * 0.5;

	float d = sd_rounded_box(p, half_rect, corner_radius);

	// Core crisp inner/outer hairline edge (sub-pixel anti-aliased)
	float edge = 1.0 - smoothstep(0.0, 1.5, abs(d) - border_width * 0.5);
	edge = clamp(edge, 0.0, 1.0);

	// Smooth Gaussian-like exponential glow outside the border
	float glow = 0.0;
	if (d > -border_width * 0.5) {
		float dist_from_border = max(d, 0.0);
		glow = exp(-dist_from_border * 3.5 / glow_width);
	}

	// Subtle breathing pulse
	float pulse = 1.0 + sin(TIME * pulse_speed) * pulse_intensity;
	glow *= pulse;

	// Combine core highlight and celestial sapphire glow
	vec3 col = mix(glow_color.rgb, core_color.rgb, edge * 0.75);
	float alpha = max(glow * glow_color.a, edge * core_color.a);

	COLOR = vec4(col, clamp(alpha, 0.0, 1.0));
}
