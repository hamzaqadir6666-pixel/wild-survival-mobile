shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

// Instanced grass cards with wind sway, distance fade and slope/tint blending.

uniform sampler2D grass_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec3 tint_a : source_color = vec3(0.32, 0.42, 0.15);
uniform vec3 tint_b : source_color = vec3(0.52, 0.52, 0.24);
uniform float wind_strength = 0.18;
uniform float wind_speed = 1.1;
uniform float fade_start = 42.0;
uniform float fade_end = 68.0;
uniform float min_scale = 0.7;
uniform float max_scale = 1.5;

varying float v_fade;
varying vec3 v_world;

void vertex() {
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float t = TIME * wind_speed;
	float phase = origin.x * 0.35 + origin.z * 0.27;
	float sway = sin(t + phase) * 0.6 + sin(t * 2.3 + phase * 1.7) * 0.25;
	// bend only the top of the card (local Y is height)
	float h = clamp(VERTEX.y, 0.0, 4.0);
	float bend = smoothstep(0.0, 1.0, h) * wind_strength * sway;
	VERTEX.x += bend * h;
	VERTEX.z += bend * h * 0.55;
	vec3 cam = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 to_cam = normalize(vec3(cam.x - origin.x, 0.0, cam.z - origin.z));
	// face the camera around Y using the instance basis
	float ang = atan(to_cam.x, to_cam.z);
	mat4 m = MODEL_MATRIX;
	vec3 right = vec3(cos(ang), 0.0, -sin(ang));
	vec3 up = vec3(0.0, 1.0, 0.0);
	vec3 fwd = vec3(sin(ang), 0.0, cos(ang));
	VERTEX = right * VERTEX.x + up * VERTEX.y + fwd * VERTEX.z;
	v_world = origin;
	float d = distance(cam, origin);
	v_fade = 1.0 - smoothstep(fade_start, fade_end, d);
}

void fragment() {
	vec4 tex = texture(grass_tex, UV);
	ALBEDO = tex.rgb * mix(tint_a, tint_b, fract(sin(dot(v_world.xz, vec2(12.9898, 78.233))) * 43758.5453));
	ALPHA = tex.a * v_fade;
	ALPHA_SCISSOR_THRESHOLD = 0.35;
	ROUGHNESS = 0.92;
	SPECULAR = 0.12;
	BACKLIGHT = tex.rgb * 0.35;
	NORMAL_MAP = vec3(0.5, 0.9, 0.5);
	// subtle translucency so grass glows when backlit by the sun
}
