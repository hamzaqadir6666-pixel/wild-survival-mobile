shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Triplanar-ish blended terrain: four albedo/normal layers chosen by the
// vertex-colour biome weights baked by terrain_generator.gd, with macro
// variation to break up tiling.

uniform sampler2D tex_grass : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_dirt : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_sand : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_rock : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_snow : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D nrm_grass : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D nrm_dirt : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D nrm_sand : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D nrm_rock : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;

uniform float uv_scale = 0.22;
uniform float macro_scale = 0.004;
uniform vec3 grass_tint : source_color = vec3(1.0);
uniform vec3 dry_tint : source_color = vec3(1.0);

varying vec4 v_weights;
varying vec3 v_world;

float macro_noise(vec2 p) {
	// cheap value-hash fbm to modulate colour + blend at large scale
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = fract(sin(dot(i, vec2(127.1, 311.7))) * 43758.5453);
	float b = fract(sin(dot(i + vec2(1.0, 0.0), vec2(127.1, 311.7))) * 43758.5453);
	float c = fract(sin(dot(i + vec2(0.0, 1.0), vec2(127.1, 311.7))) * 43758.5453);
	float d = fract(sin(dot(i + vec2(1.0, 1.0), vec2(127.1, 311.7))) * 43758.5453);
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	v_weights = COLOR;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = v_world.xz * uv_scale;
	vec2 uv2 = v_world.xz * uv_scale * 3.7;
	float macro = macro_noise(v_world.xz * macro_scale) * 0.55 + macro_noise(v_world.xz * macro_scale * 3.1) * 0.45;

	vec4 w = v_weights;
	// sharpen biome weights a little so transitions read as natural bands
	w = pow(clamp(w, 0.0, 1.0), vec4(1.35));
	float sum = w.r + w.g + w.b + w.a + 0.0001;
	w /= sum;

	vec3 c_grass = texture(tex_grass, uv).rgb * mix(grass_tint * 0.82, grass_tint, macro);
	vec3 c_grass2 = texture(tex_grass, uv2 + vec2(0.37, 0.11)).rgb;
	c_grass = mix(c_grass, c_grass2, 0.35);
	vec3 c_forest = mix(texture(tex_grass, uv * 1.3 + 0.13).rgb, texture(tex_dirt, uv).rgb, 0.42) * 0.72;
	vec3 c_sand = texture(tex_sand, uv).rgb * mix(dry_tint * 0.9, dry_tint * 1.1, macro);
	vec3 c_rock = texture(tex_rock, uv * 0.7).rgb;
	vec3 c_snow = texture(tex_snow, uv * 0.5).rgb;

	// snow only high up and not on steep slopes
	float height_snow = smoothstep(78.0, 108.0, v_world.y) * smoothstep(0.55, 0.85, NORMAL.y);

	vec3 albedo = c_grass * w.r + c_forest * w.g + c_sand * w.b + c_rock * w.a;
	albedo = mix(albedo, c_snow, height_snow);

	// normals (grass+dirt+sand share planar mapping, rock is triplanar-ish scaled)
	vec3 n_grass = texture(nrm_grass, uv).xyz * 2.0 - 1.0;
	vec3 n_dirt = texture(nrm_dirt, uv).xyz * 2.0 - 1.0;
	vec3 n_sand = texture(nrm_sand, uv).xyz * 2.0 - 1.0;
	vec3 n_rock = texture(nrm_rock, uv * 0.7).xyz * 2.0 - 1.0;
	vec3 nblend = n_grass * w.r + n_dirt * w.g + n_sand * w.b + n_rock * w.a;
	nblend = normalize(vec3(nblend.x, nblend.z * 1.6, nblend.y));
	NORMAL_MAP = nblend * 0.5 + 0.5;

	ALBEDO = albedo;
	ROUGHNESS = mix(0.92, 0.72, w.a);
	SPECULAR = 0.18;
	AO = mix(0.85, 1.0, macro);
	AO_LIGHT_AFFECT = 0.35;
}
