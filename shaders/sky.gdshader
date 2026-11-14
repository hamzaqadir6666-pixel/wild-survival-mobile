shader_type spatial;
// Sky dome that follows the camera: gradient, drifting clouds, stars at night.
render_mode unshaded, cull_front, depth_draw_never, fog_disabled;
uniform vec3 top : source_color = vec3(0.2, 0.45, 0.85);
uniform vec3 horizon : source_color = vec3(0.65, 0.8, 0.95);
uniform vec3 cloud_col : source_color = vec3(1.0);
uniform sampler2D clouds : repeat_enable, filter_linear;
uniform float cover = 0.3;
uniform float stars = 0.0;
varying vec3 dir;
void vertex() {
	dir = VERTEX;
}
void fragment() {
	vec3 d = normalize(dir);
	float h = clamp(d.y, 0.0, 1.0);
	vec3 c = mix(horizon, top, pow(h, 0.55));
	vec2 uv = d.xz / (d.y + 0.3) * 0.16 + TIME * vec2(0.004, 0.002);
	float n = texture(clouds, uv).r;
	if (stars > 0.01) {
		float s = texture(clouds, d.xz * 3.1 / (d.y + 0.6)).r * texture(clouds, d.zx * 5.3 / (d.y + 0.6) + 0.37).r;
		c += vec3(smoothstep(0.80, 0.95, s)) * stars * h;
	}
	float cl = smoothstep(1.0 - cover, 1.25 - cover, n) * smoothstep(0.0, 0.22, d.y);
	ALBEDO = mix(c, cloud_col, cl * 0.92);
}
