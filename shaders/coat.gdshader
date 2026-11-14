shader_type spatial;
// Textured animal coat (0 A.D. and Poly models): the model's own colour texture on UV,
// plus an optional tiling pattern (stripes, spots) projected from the side on UV2.
render_mode diffuse_lambert, specular_disabled, cull_disabled;
uniform sampler2D tex : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D fur : repeat_enable, filter_linear_mipmap;
uniform vec3 pattern_color : source_color = vec3(0.05);
uniform float pattern = 0.0;
uniform vec2 uv_scale = vec2(1.0);
uniform vec3 tint = vec3(1.0);
void fragment() {
	vec3 c = texture(tex, UV).rgb * tint;
	if (pattern > 0.0) {
		float t = texture(fur, UV2 * uv_scale).r;
		c = mix(pattern_color, c, mix(1.0, t, pattern));
	}
	ALBEDO = c;
	ROUGHNESS = 1.0;
}
