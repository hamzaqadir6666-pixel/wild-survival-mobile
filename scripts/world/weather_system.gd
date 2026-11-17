extends Node
## Dynamic weather: clear / cloudy / rain / fog / storm with smooth transitions,
## rain particles that follow the camera, wind particles and thunder audio.

signal weather_changed(state: String)

enum Weather { CLEAR, CLOUDY, RAIN, FOG, STORM }

const STATES := {
	"CLEAR": {"cloud": 0.22, "fog": 0.0035, "rain": 0.0, "sun": 1.0, "vol": 0.005},
	"CLOUDY": {"cloud": 0.62, "fog": 0.006, "rain": 0.0, "sun": 0.7, "vol": 0.008},
	"RAIN": {"cloud": 0.85, "fog": 0.011, "rain": 0.7, "sun": 0.42, "vol": 0.014},
	"FOG": {"cloud": 0.55, "fog": 0.03, "rain": 0.0, "sun": 0.55, "vol": 0.03},
	"STORM": {"cloud": 0.95, "fog": 0.016, "rain": 1.0, "sun": 0.25, "vol": 0.02},
}

@export var auto_weather := true
@export var min_clear_time := 90.0
@export var max_clear_time := 240.0

var current_state := "CLEAR"
var target_state := "CLEAR"
var blend := 1.0
var _params := {"cloud": 0.22, "fog": 0.0035, "rain": 0.0, "sun": 1.0, "vol": 0.005}
var _target_params := {"cloud": 0.22, "fog": 0.0035, "rain": 0.0, "sun": 1.0, "vol": 0.005}
var _timer := 60.0
var _lightning_timer := 6.0

var day_night: Node
var sky_material: ShaderMaterial
var world_env: WorldEnvironment
var rain_particles: GPUParticles3D
var splash_particles: GPUParticles3D
var _rain_mat: ParticleProcessMaterial
var _lightning_light: OmniLight3D
var _wind_audio: AudioStreamPlayer


func setup(p_day_night: Node, p_env: WorldEnvironment, p_sky_material: ShaderMaterial) -> void:
	day_night = p_day_night
	world_env = p_env
	sky_material = p_sky_material
	_build_rain()


func _build_rain() -> void:
	rain_particles = GPUParticles3D.new()
	rain_particles.name = "Rainfall"
	_rain_mat = ParticleProcessMaterial.new()
	_rain_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_rain_mat.emission_box_extents = Vector3(28, 1, 28)
	_rain_mat.direction = Vector3(0.12, -1.0, 0.06)
	_rain_mat.spread = 3.0
	_rain_mat.initial_velocity_min = 22.0
	_rain_mat.initial_velocity_max = 30.0
	_rain_mat.gravity = Vector3(0, -9.8, 0)
	_rain_mat.scale_min = 0.5
	_rain_mat.scale_max = 1.2
	_rain_mat.color = Color(0.72, 0.78, 0.86, 0.42)
	rain_particles.process_material = _rain_mat
	var qm := QuadMesh.new()
	qm.size = Vector2(0.018, 0.42)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(0.8, 0.85, 0.95, 0.5)
	qm.material = mat
	rain_particles.draw_pass_1 = qm
	rain_particles.amount = 6000
	rain_particles.lifetime = 1.4
	rain_particles.visibility_aabb = AABB(Vector3(-30, -16, -30), Vector3(60, 34, 60))
	rain_particles.emitting = false
	rain_particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rain_particles)

	_lightning_light = OmniLight3D.new()
	_lightning_light.light_color = Color(0.8, 0.86, 1.0)
	_lightning_light.omni_range = 240.0
	_lightning_light.light_energy = 0.0
	_lightning_light.shadow_enabled = false
	add_child(_lightning_light)


func _process(delta: float) -> void:
	if auto_weather and not Engine.is_editor_hint():
		_timer -= delta
		if _timer <= 0.0:
			_pick_next_state()
	if target_state != current_state:
		blend = minf(1.0, blend + delta * 0.12)
		_lerp_params(delta)
		if blend >= 1.0:
			current_state = target_state
	if rain_particles:
		var cam := get_viewport().get_camera_3d()
		if cam:
			rain_particles.global_position = cam.global_position + Vector3(0, 14.0, 0)
		rain_particles.emitting = _params["rain"] > 0.02
		_rain_mat.color = Color(0.72, 0.78, 0.86, 0.42 * clampf(_params["rain"], 0.0, 1.0))
	if _lightning_light:
		var cam2 := get_viewport().get_camera_3d()
		if cam2:
			_lightning_light.global_position = cam2.global_position + Vector3(0, 30, 0)
	if current_state == "STORM":
		_lightning_timer -= delta
		if _lightning_timer <= 0.0:
			_lightning_timer = randf_range(5.0, 14.0)
			_strike_lightning()


func _lerp_params(delta: float) -> void:
	var rate := clampf(delta * 0.6, 0.0, 1.0)
	for k in _params.keys():
		_params[k] = lerpf(_params[k], _target_params[k], rate)
	_apply_params()


func _apply_params() -> void:
	if sky_material:
		sky_material.set_shader_parameter("cloud_coverage", _params["cloud"])
	if world_env and world_env.environment:
		var night_factor := 1.0
		if day_night and day_night.has_method("is_night"):
			night_factor = 1.25 if day_night.is_night() else 1.0
		world_env.environment.fog_density = _params["fog"] * night_factor
		if world_env.environment.volumetric_fog_enabled:
			world_env.environment.volumetric_fog_density = _params["vol"]
	# day/night owns the sun's position and base energy; weather only scales it
	if day_night and day_night.get("light_scale") != null and _params.has("sun"):
		day_night.light_scale = _params["sun"]


func _pick_next_state() -> void:
	var roll := randf()
	var next := "CLEAR"
	if roll < 0.34:
		next = "CLOUDY"
	elif roll < 0.55:
		next = "RAIN"
	elif roll < 0.68:
		next = "FOG"
	elif roll < 0.80:
		next = "STORM"
	if next == current_state:
		next = "CLOUDY" if current_state != "CLOUDY" else "CLEAR"
	set_weather(next)
	_timer = randf_range(min_clear_time, max_clear_time)


func set_weather(state: String, instant: bool = false) -> void:
	if not STATES.has(state):
		return
	target_state = state
	current_state = state
	_target_params = STATES[state].duplicate()
	if instant:
		_params = _target_params.duplicate()
		blend = 1.0
		_apply_params()
	else:
		blend = 0.0
	GameState.weather_state = state
	emit_signal("weather_changed", state)
	_announce_weather(state)


func _announce_weather(state: String) -> void:
	match state:
		"RAIN":
			AudioManager.set_ambience("rain", -12.0, 4.0)
			GameState.notify("Rain rolls across the territory.", 3.0)
		"STORM":
			AudioManager.set_ambience("rain", -8.0, 3.0)
			GameState.notify("A storm is brewing. Lightning splits the sky.", 4.0)
		"FOG":
			AudioManager.set_ambience("wind", -20.0, 4.0)
			GameState.notify("Fog settles over the land.", 3.0)
		"CLEAR":
			AudioManager.set_ambience("wind", -26.0, 5.0)
		_:
			AudioManager.set_ambience("wind", -24.0, 5.0)


func _strike_lightning() -> void:
	if _lightning_light:
		_lightning_light.light_energy = 14.0
		var tw := create_tween()
		tw.tween_property(_lightning_light, "light_energy", 0.0, 0.35)
	var cam := get_viewport().get_camera_3d()
	var close := randf() < 0.5
	var id := "thunder_close" if close else "thunder_far"
	AudioManager.play_sfx(id, randf_range(0.9, 1.1), -4.0 if close else -10.0)


func rain_amount() -> float:
	return _params["rain"]


func is_raining() -> bool:
	return _params["rain"] > 0.05
