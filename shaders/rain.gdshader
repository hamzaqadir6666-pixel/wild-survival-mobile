shader_type spatial;
// Rain streaks: a MultiMesh of thin quads, animated entirely in the vertex shader.
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, fog_disabled;
uniform float amount = 1.0;
uniform float box = 22.0;
uniform float tall = 14.0;
varying float a;
void vertex() {
	vec3 o = MODEL_MATRIX[3].xyz;            // instance origin inside the box
	float seed = fract(sin(o.x * 12.9898 + o.z * 78.233) * 43758.5453);
	float fall = fract(seed - TIME * (1.1 + seed * 0.5));
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 p = vec3(o.x, 0.0, o.z);
	p.xz = mod(p.xz - cam.xz, box) - box * 0.5 + cam.xz;
	p.y = cam.y - 3.0 + fall * tall;
	vec3 right = normalize(vec3(INV_VIEW_MATRIX[0].x, 0.0, INV_VIEW_MATRIX[0].z));
	vec3 wv = p + right * VERTEX.x + vec3(0.06, 1.0, 0.0) * VERTEX.y;
	POSITION = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(wv, 1.0));
	a = step(seed, amount) * 0.55;
}
void fragment() {
	ALBEDO = vec3(0.78, 0.84, 0.92);
	ALPHA = a * (1.0 - abs(UV.x - 0.5) * 2.0);
}
