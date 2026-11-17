shader_type sky;

// Physically-inspired procedural sky: Rayleigh-ish gradient + sun disc,
// horizon haze, night time stars and drifting cirrus clouds.

uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 zenith_color : source_color = vec3(0.18, 0.34, 0.62);
uniform vec3 horizon_color : source_color = vec3(0.72, 0.78, 0.85);
uniform vec3 ground_color : source_color = vec3(0.22, 0.19, 0.16);
uniform vec3 sun_color : source_color = vec3(1.0, 0.9, 0.75);
uniform float sun_disc_size = 0.9995;
uniform float sun_energy = 22.0;
uniform float cloud_coverage = 0.42;
uniform float cloud_sharpness = 3.0;
uniform vec3 cloud_tint : source_color = vec3(1.0);
uniform float star_amount = 0.0;
uniform float haze = 0.35;
uniform float time_of_day = 12.0;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i + vec3(0,0,0)), hash(i + vec3(1,0,0)), f.x),
	               mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
	           mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x),
	               mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise3(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float up = clamp(d.y, -1.0, 1.0);
	// base gradient
	float t = pow(clamp(1.0 - max(up, 0.0), 0.0, 1.0), 1.4);
	vec3 col = mix(zenith_color, horizon_color, t);
	// ground hemisphere
	if (up < 0.0) {
		float g = clamp(-up * 4.0, 0.0, 1.0);
		col = mix(col, ground_color, smoothstep(0.0, 0.35, -up));
	}
	// sun glow
	float mu = clamp(dot(d, normalize(sun_dir)), -1.0, 1.0);
	float glow = pow(clamp(mu, 0.0, 1.0), 8.0) * 0.55 + pow(clamp(mu, 0.0, 1.0), 64.0) * 0.9;
	col += sun_color * glow;
	// sun disc
	if (mu > sun_disc_size) {
		col += sun_color * sun_energy;
	}
	// horizon haze
	float haze_band = exp(-abs(up) * 9.0) * haze;
	col = mix(col, horizon_color * 1.06, haze_band);
	// stars
	if (up > 0.02 && star_amount > 0.001) {
		vec3 sp = d * 260.0;
		float s = hash(floor(sp));
		float star = smoothstep(0.9975, 1.0, s);
		float twinkle = 0.6 + 0.4 * sin(TIME * 4.0 + s * 90.0);
		col += vec3(0.85, 0.9, 1.0) * star * twinkle * star_amount * 2.2;
		// milky band
		float band = exp(-pow((d.y - 0.35) * 5.0, 2.0)) * 0.05 * star_amount;
		col += vec3(0.5, 0.55, 0.75) * band * fbm(d * 12.0);
	}
	// clouds: project the direction on a plane for a flat layer look
	if (up > 0.005) {
		vec2 cuv = d.xz / max(up + 0.12, 0.05);
		vec3 cp = vec3(cuv * 0.55, TIME * 0.004);
		float n = fbm(cp);
		float cover = smoothstep(1.0 - cloud_coverage, 1.0 - cloud_coverage + 0.32, n);
		float detail = fbm(cp * 3.1) * 0.45;
		float mask = clamp(cover * (0.7 + detail), 0.0, 1.0) * smoothstep(0.005, 0.16, up);
		vec3 ccol = cloud_tint * (0.75 + 0.5 * pow(clamp(mu, 0.0, 1.0), 3.0));
		col = mix(col, ccol, mask * 0.9);
	}
	COLOR = col;
}
