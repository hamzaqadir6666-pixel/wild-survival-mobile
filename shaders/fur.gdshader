shader_type spatial;
// Animal coat: species colours come from the vertices, the fur pattern
// (stripes, spots, scales) from one small tiling texture. One draw call per animal.
render_mode diffuse_lambert, specular_disabled;
uniform sampler2D fur : repeat_enable, filter_linear_mipmap;
uniform vec3 pattern_color : source_color = vec3(0.05);
uniform float pattern = 0.0;
uniform vec2 uv_scale = vec2(1.0);
uniform vec3 tint = vec3(1.0);
void fragment() {
	vec3 t = texture(fur, UV * uv_scale).rgb;
	float m = mix(1.0, t.r, pattern * COLOR.a);
	ALBEDO = mix(pattern_color, COLOR.rgb, m) * (0.80 + 0.40 * t.g) * tint;
	ROUGHNESS = 1.0;
}
