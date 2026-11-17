shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;

// Stylised-realistic water: two scrolling normal maps, fresnel reflection,
// depth-based shoreline foam and refraction.

uniform sampler2D normal_map_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_map_b : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

uniform vec3 shallow_color : source_color = vec3(0.22, 0.42, 0.40);
uniform vec3 deep_color : source_color = vec3(0.03, 0.12, 0.16);
uniform vec3 foam_color : source_color = vec3(0.92, 0.96, 1.0);
uniform float wave_speed = 0.045;
uniform float normal_strength = 0.55;
uniform float refraction = 0.03;
uniform float depth_fade = 1.6;
uniform float foam_width = 0.55;
uniform float clarity = 0.85;
uniform float flow = 0.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// gentle vertical bob so the surface is never perfectly flat
	float w = sin(world_pos.x * 0.35 + TIME * 0.9) * cos(world_pos.z * 0.28 + TIME * 0.7);
	VERTEX.y += w * 0.045;
}

void fragment() {
	vec2 uv1 = world_pos.xz * 0.045 + vec2(TIME * wave_speed, TIME * wave_speed * 0.6);
	vec2 uv2 = world_pos.xz * 0.031 - vec2(TIME * wave_speed * 0.7, -TIME * wave_speed * 0.4);
	vec3 n1 = texture(normal_map_a, uv1).rgb * 2.0 - 1.0;
	vec3 n2 = texture(normal_map_b, uv2).rgb * 2.0 - 1.0;
	vec3 n = normalize(vec3((n1.x + n2.x) * normal_strength, 1.0, (n1.y + n2.y) * normal_strength));
	NORMAL_MAP = n * 0.5 + 0.5;

	// depth of the scene behind the water surface, measured along the view ray
	float raw_depth = texture(depth_tex, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, raw_depth);
	vec4 view_pos = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view_pos.xyz /= view_pos.w;
	// VERTEX is in view space here; both z values are negative going forward
	float thickness = clamp(VERTEX.z - view_pos.z, 0.0, 60.0);

	float d01 = clamp(thickness / depth_fade, 0.0, 1.0);
	vec3 body = mix(shallow_color, deep_color, d01);

	// refraction offset
	vec2 refr = n.xy * refraction;
	vec3 refr_col = texture(screen_tex, SCREEN_UV + refr).rgb;
	body = mix(refr_col, body, clarity * 0.75 + 0.15 * d01);

	// foam at the shoreline
	float foam = smoothstep(foam_width, 0.0, thickness) * (0.6 + 0.4 * sin(TIME * 3.0 + world_pos.x * 2.0));
	body = mix(body, foam_color, clamp(foam, 0.0, 1.0) * 0.7);

	ALBEDO = body;
	ROUGHNESS = 0.06;
	METALLIC = 0.0;
	SPECULAR = 0.6;
	ALPHA = 1.0;
	// fresnel-ish roughness so grazing angles look smooth
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ROUGHNESS = mix(0.03, 0.18, fres);
}
