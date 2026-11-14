shader_type spatial;
// Simple animated semi-transparent water. Never reads the screen or depth buffer.
// Vertex alpha (baked from the real water depth) fades the surface out at the shore.
render_mode blend_mix, depth_draw_never, cull_back, diffuse_lambert, specular_disabled;
uniform sampler2D ripple : repeat_enable, filter_linear_mipmap;
uniform vec3 shallow : source_color = vec3(0.30, 0.62, 0.72);
uniform vec3 deep : source_color = vec3(0.07, 0.30, 0.55);
void fragment() {
	float a = texture(ripple, UV * 0.9 + vec2(TIME * 0.030, TIME * 0.021)).r;
	float b = texture(ripple, UV * 0.47 - vec2(TIME * 0.017, TIME * 0.026)).g;
	float r = a * 0.6 + b * 0.4;
	vec3 col = mix(shallow, deep, COLOR.a);
	col *= 0.85 + r * 0.3;
	col += vec3(0.30, 0.34, 0.36) * smoothstep(0.80, 0.93, a) * COLOR.a;
	ALBEDO = col;
	ALPHA = mix(0.30, 0.88, COLOR.a);
	ROUGHNESS = 1.0;
}
