shader_type spatial;
// Trees, bushes, plants, rocks: one surface each, colours in the vertices,
// one small tiling detail texture (R = leaf pattern, G = bark pattern).
render_mode cull_disabled, diffuse_lambert, specular_disabled;
uniform sampler2D detail : repeat_enable, filter_linear_mipmap;
uniform float wind = 0.0;
uniform vec3 tint = vec3(1.0);
uniform vec3 glow = vec3(0.0);
uniform vec3 season = vec3(1.0);
varying float leaf;
void vertex() {
	leaf = COLOR.a;
	vec3 wp = MODEL_MATRIX[3].xyz;
	float ph = wp.x * 0.37 + wp.z * 0.23;
	if (wind > 0.0) {
		float s = sin(TIME * 1.3 + ph + VERTEX.y * 0.8) * wind * leaf * VERTEX.y * 0.03;
		VERTEX.x += s;
		VERTEX.z += s * 0.6;
	}
	float v = fract(sin(ph * 12.9898) * 43758.5453);
	COLOR.rgb *= mix(vec3(0.80, 0.90, 0.80), vec3(1.12, 1.08, 0.98), v);
}
void fragment() {
	vec3 d = texture(detail, UV).rgb;
	float k = mix(d.g, d.r, leaf);
	ALBEDO = COLOR.rgb * tint * mix(vec3(1.0), season, leaf) * (0.70 + 0.60 * k);
	EMISSION = glow;
	ROUGHNESS = 1.0;
}
