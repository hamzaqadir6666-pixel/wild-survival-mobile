shader_type spatial;
// Ground: 6 textures blended by weights stored in the mesh (vertex colour + UV2).
// Heights are in the mesh itself; no texture is read in the vertex stage.
render_mode diffuse_lambert, specular_disabled;
uniform sampler2D t_grass : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D t_forest : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D t_dirt : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D t_sand : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D t_rock : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D t_mud : source_color, repeat_enable, filter_linear_mipmap;
uniform vec3 tint = vec3(1.0);
varying vec4 w;
varying float mud;
void vertex() {
	w = COLOR;
	mud = UV2.x;
}
void fragment() {
	float g = clamp(1.0 - w.r - w.g - w.b - w.a - mud, 0.0, 1.0);
	vec3 c = texture(t_grass, UV).rgb * g * tint;
	c += texture(t_forest, UV).rgb * w.r * mix(vec3(1.0), tint, 0.5);
	c += texture(t_dirt, UV).rgb * w.g;
	c += texture(t_sand, UV).rgb * w.b;
	c += texture(t_rock, UV * 0.5).rgb * w.a;
	c += texture(t_mud, UV).rgb * mud;
	// large soft patches so the tiling is not obvious from far away
	float macro = texture(t_grass, UV * 0.043).g;
	ALBEDO = c * (0.72 + macro * 0.9);
	ROUGHNESS = 1.0;
}
