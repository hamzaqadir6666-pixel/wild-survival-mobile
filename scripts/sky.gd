class_name SkyRig
extends Node3D
## Day/night cycle, sun and moon, weather, fog, rain and lightning. All cheap:
## one directional light, colour ambient, depth fog, a sky dome and a rain MultiMesh.

signal lightning
signal weather_changed(kind: int)
signal night_started
signal day_started
signal new_day(day: int)

const WEATHER_NAMES := ["Clear", "Cloudy", "Rain", "Storm"]
var hour := D.START_HOUR
var day := 1
var weather := 0
var cover := 0.25
var rain := 0.0
var flash := 0.0
var dayf := 1.0                 # 1 = full day, 0 = night
var is_night := false
var night_vision := false
var weather_locked := false     # tests can freeze the weather

var env: Environment
var sun: DirectionalLight3D
var dome: MeshInstance3D
var dome_mat: ShaderMaterial
var sun_disc: MeshInstance3D
var moon_disc: MeshInstance3D
var rain_node: MultiMeshInstance3D
var rain_mat: ShaderMaterial
var _weather_timer := 50.0
var _bolt_timer := 6.0
var _rng := RandomNumberGenerator.new()

func setup() -> void:
	_rng.randomize()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.glow_enabled = false
	env.ssao_enabled = false
	env.ssr_enabled = false
	env.sdfgi_enabled = false
	env.volumetric_fog_enabled = false
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_density = 1.0
	env.fog_sun_scatter = 0.0
	env.fog_aerial_perspective = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 45.0
	sun.shadow_bias = 0.08
	sun.shadow_normal_bias = 1.5
	sun.shadow_blur = 1.0
	add_child(sun)
	var sm := SphereMesh.new()
	sm.radius = 1.0; sm.height = 2.0; sm.radial_segments = 20; sm.rings = 10
	dome = MeshInstance3D.new()
	dome.mesh = sm
	dome_mat = ShaderMaterial.new()
	dome_mat.shader = load("res://shaders/sky.gdshader")
	dome_mat.set_shader_parameter("clouds", load("res://assets/textures/clouds.png"))
	dome.material_override = dome_mat
	dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(dome)
	sun_disc = _disc("res://assets/textures/sun.png", true)
	moon_disc = _disc("res://assets/textures/moon.png", false)
	rain_mat = ShaderMaterial.new()
	rain_mat.shader = load("res://shaders/rain.gdshader")
	var q := QuadMesh.new(); q.size = Vector2(0.035, 0.9)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = q
	mm.instance_count = 340
	for i in 340: mm.set_instance_transform(i, Transform3D(Basis(), Vector3(_rng.randf() * 22.0, 0, _rng.randf() * 22.0)))
	rain_node = MultiMeshInstance3D.new()
	rain_node.multimesh = mm
	rain_node.material_override = rain_mat
	rain_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rain_node.custom_aabb = AABB(Vector3(-2000, -500, -2000), Vector3(5000, 1000, 5000))
	rain_node.visible = false
	add_child(rain_node)
	apply_quality()

func _disc(tex: String, additive: bool) -> MeshInstance3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = load(tex)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.disable_fog = true
	m.disable_receive_shadows = true
	m.no_depth_test = false
	var q := QuadMesh.new(); q.size = Vector2(1, 1)
	var mi := MeshInstance3D.new()
	mi.mesh = q; mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi

func apply_quality() -> void:
	if sun == null: return
	sun.shadow_enabled = bool(Cfg.v("shadows"))
	var size := int(Cfg.PRESETS[Cfg.preset].shadow_size)
	if size <= 0: size = 1024
	RenderingServer.directional_shadow_atlas_set_size(size, true)
	rain_node.multimesh.visible_instance_count = int(Cfg.v("rain"))

func reset(start_hour: float) -> void:
	hour = start_hour; day = 1; weather = 0; cover = 0.25; rain = 0.0; flash = 0.0
	is_night = false; _weather_timer = _rng.randf_range(45.0, 80.0)
	_refresh(Vector3.ZERO, true)

func clock_text() -> String:
	return "%02d:%02d" % [int(hour), int(fmod(hour, 1.0) * 60.0)]

func set_weather(kind: int) -> void:
	if kind == weather: return
	weather = kind
	weather_changed.emit(kind)

func update(delta: float, cam: Vector3) -> void:
	hour += delta * 24.0 / D.DAY_LENGTH
	if hour >= 24.0:
		hour -= 24.0
		day += 1
		new_day.emit(day)
	if not weather_locked:
		_weather_timer -= delta
		if _weather_timer <= 0.0:
			_weather_timer = _rng.randf_range(50.0, 110.0)
			var roll := _rng.randf()
			var next := 0
			if roll < 0.34: next = 0
			elif roll < 0.62: next = 1
			elif roll < 0.86: next = 2
			else: next = 3
			if next == weather: next = (weather + 1) % 4
			set_weather(next)
	var cover_t: float = [0.25, 0.62, 0.86, 1.0][weather]
	var rain_t: float = [0.0, 0.0, 0.7, 1.0][weather]
	cover = move_toward(cover, cover_t, delta * 0.08)
	rain = move_toward(rain, rain_t, delta * 0.12)
	if weather == 3 and rain > 0.6:
		_bolt_timer -= delta
		if _bolt_timer <= 0.0:
			_bolt_timer = _rng.randf_range(5.0, 13.0)
			flash = 1.0
			lightning.emit()
	flash = maxf(0.0, flash - delta * 4.0)
	_refresh(cam, false)

func _refresh(cam: Vector3, force: bool) -> void:
	dayf = smoothstep(5.0, 7.0, hour) * (1.0 - smoothstep(18.5, 20.5, hour))
	var night_now := dayf < 0.35
	if night_now != is_night or force:
		is_night = night_now
		if not force:
			if is_night: night_started.emit()
			else: day_started.emit()
	var dusk := dayf * (1.0 - dayf) * 4.0
	var gloom := clampf((cover - 0.25) * 1.1, 0.0, 0.8)
	# light direction: sun by day, moon by night, both arc across the sky
	var ang := (hour - 6.0) / 12.0 * PI if dayf > 0.5 else (fmod(hour + 6.0, 24.0)) / 12.0 * PI
	var elev := maxf(0.22, sin(ang))
	var dir := Vector3(cos(ang) * 0.9, elev, 0.35).normalized()
	sun.look_at_from_position(Vector3.ZERO, -dir, Vector3.UP)
	var warm := Color(1.0, 0.95, 0.84).lerp(Color(1.0, 0.62, 0.35), dusk * 0.8)
	sun.light_color = Color(0.50, 0.62, 0.95).lerp(warm, dayf)
	sun.light_energy = lerpf(0.16, 1.25, dayf) * (1.0 - gloom * 0.65) + flash * 1.2
	var amb_day := Color(0.60, 0.67, 0.74).lerp(Color(0.5, 0.52, 0.55), gloom)
	var amb_night := Color(0.10, 0.13, 0.24)
	var amb_e := lerpf(0.55, 0.85, dayf) * (1.0 - gloom * 0.3)
	if night_vision:
		amb_night = Color(0.28, 0.40, 0.40)      # soft, slightly green lift; tuned to stay clearly darker than day
		amb_e = lerpf(0.80, 0.85, dayf) * (1.0 - gloom * 0.3)
	env.ambient_light_color = amb_night.lerp(amb_day, dayf)
	env.ambient_light_energy = amb_e + flash * 1.5
	var top := Color(0.012, 0.02, 0.06).lerp(Color(0.20, 0.45, 0.85), dayf)
	var hor := Color(0.035, 0.05, 0.10).lerp(Color(0.62, 0.78, 0.92), dayf).lerp(Color(0.95, 0.55, 0.30), dusk * 0.55)
	var grey := Color(0.50, 0.54, 0.60) * lerpf(0.12, 1.0, dayf)
	top = top.lerp(grey * 0.85, gloom)
	hor = hor.lerp(grey, gloom)
	if flash > 0.0:
		top = top.lerp(Color(0.9, 0.92, 1.0), flash * 0.7); hor = hor.lerp(Color(0.95, 0.96, 1.0), flash * 0.7)
	dome_mat.set_shader_parameter("top", top)
	dome_mat.set_shader_parameter("horizon", hor)
	dome_mat.set_shader_parameter("cloud_col", Color(1, 1, 1).lerp(Color(0.45, 0.47, 0.52), gloom) * lerpf(0.10, 1.0, dayf) + Color(flash, flash, flash) * 0.5)
	dome_mat.set_shader_parameter("cover", cover)
	dome_mat.set_shader_parameter("stars", (1.0 - dayf) * (1.0 - gloom))
	var view := float(Cfg.v("view"))
	env.background_color = hor
	env.fog_light_color = hor
	env.fog_depth_begin = view * lerpf(0.34, 0.14, rain)
	env.fog_depth_end = view
	dome.global_position = cam
	dome.scale = Vector3.ONE * (view + 20.0)
	var far := view * 0.9
	sun_disc.visible = dayf > 0.05 and gloom < 0.7
	moon_disc.visible = dayf < 0.6 and gloom < 0.7
	var sdir := Vector3(cos((hour - 6.0) / 12.0 * PI) * 0.9, maxf(0.05, sin((hour - 6.0) / 12.0 * PI)), 0.35).normalized()
	var mdir := Vector3(cos(fmod(hour + 6.0, 24.0) / 12.0 * PI) * 0.9, maxf(0.05, sin(fmod(hour + 6.0, 24.0) / 12.0 * PI)), 0.35).normalized()
	sun_disc.global_position = cam + sdir * far; sun_disc.scale = Vector3.ONE * far * 0.22
	moon_disc.global_position = cam + mdir * far; moon_disc.scale = Vector3.ONE * far * 0.12
	rain_node.visible = rain > 0.03
	rain_mat.set_shader_parameter("amount", rain)
