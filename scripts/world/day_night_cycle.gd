extends Node
## Drives the sun/moon, sky shader, ambient light and fog over a 24h cycle.
## Also exposes helpers used by NPC schedules and the weather system.

signal hour_changed(hour: int)
signal day_changed(day: int)

const MINUTES_PER_REAL_SECOND := 1.6   # 1 in-game minute per 1.6 real seconds
const DAY_SECONDS := 24.0 * 60.0 / MINUTES_PER_REAL_SECOND

@export var time_of_day := 8.0 * 3600.0
@export var day := 1
@export var time_scale := 1.0
@export var paused := false

var sun: DirectionalLight3D
var moon: DirectionalLight3D
var world_env: WorldEnvironment
var sky_material: ShaderMaterial
var _last_hour := -1
## Multiplied into the sun's energy so the weather system can dim an overcast sky.
var light_scale := 1.0


func setup(p_sun: DirectionalLight3D, p_moon: DirectionalLight3D, p_env: WorldEnvironment) -> void:
	sun = p_sun
	moon = p_moon
	world_env = p_env
	if world_env and world_env.environment and world_env.environment.sky:
		sky_material = world_env.environment.sky.sky_material as ShaderMaterial
	time_of_day = GameState.world_time
	day = GameState.day
	update_lighting()


func _process(delta: float) -> void:
	if paused:
		return
	advance(delta)


func advance(delta: float) -> void:
	time_of_day += delta * time_scale * MINUTES_PER_REAL_SECOND * 60.0
	if time_of_day >= 86400.0:
		time_of_day -= 86400.0
		day += 1
		emit_signal("day_changed", day)
	GameState.world_time = time_of_day
	GameState.day = day
	var h := int(time_of_day / 3600.0)
	if h != _last_hour:
		_last_hour = h
		emit_signal("hour_changed", h)
	update_lighting()


func hour_float() -> float:
	return time_of_day / 3600.0


func is_night() -> bool:
	var h := hour_float()
	return h < 5.5 or h > 20.0


func set_time(hours: float) -> void:
	time_of_day = fposmod(hours, 24.0) * 3600.0
	update_lighting()


func skip_hours(h: float) -> void:
	set_time(hour_float() + h)


func sun_direction() -> Vector3:
	# Sun rises in the east (+X) and sets in the west (-X), tilted south.
	var t := (hour_float() - 6.0) / 12.0      # 0 at sunrise, 1 at sunset
	var angle := t * PI
	var y := sin(angle)
	var x := cos(angle)
	var z := -0.35
	return Vector3(x, y, z).normalized()


func update_lighting() -> void:
	var dir := sun_direction()
	var h := hour_float()
	var day_factor := clampf(dir.y * 4.0, 0.0, 1.0)          # 0 at night, 1 in full day
	var sunset := clampf(1.0 - absf(h - 18.4) / 1.8, 0.0, 1.0)
	var sunrise := clampf(1.0 - absf(h - 6.3) / 1.8, 0.0, 1.0)
	var golden := maxf(sunset, sunrise)

	if sun:
		sun.visible = dir.y > -0.12
		sun.global_transform = Transform3D(Basis(), Vector3(0, 80, 0)).looking_at(Vector3(0, 80, 0) - dir, Vector3.UP)
		var warm := Color(1.0, 0.94, 0.86).lerp(Color(1.0, 0.56, 0.26), golden * 0.9)
		sun.light_color = warm
		sun.light_energy = lerpf(0.02, 1.55, day_factor) * lerpf(1.0, 0.72, golden) * light_scale
		sun.shadow_enabled = dir.y > 0.02
	if moon:
		var mdir := -dir
		moon.global_transform = Transform3D(Basis(), Vector3(0, 80, 0)).looking_at(Vector3(0, 80, 0) - mdir, Vector3.UP)
		moon.visible = dir.y < 0.1
		moon.light_color = Color(0.55, 0.68, 1.0)
		moon.light_energy = lerpf(0.0, 0.28, clampf(-dir.y * 2.5, 0.0, 1.0))
		moon.shadow_enabled = dir.y < -0.05

	if world_env and world_env.environment:
		var env := world_env.environment
		var night := clampf(-dir.y * 3.0, 0.0, 1.0)
		if sky_material:
			sky_material.set_shader_parameter("sun_dir", dir)
			sky_material.set_shader_parameter("time_of_day", h)
			sky_material.set_shader_parameter("star_amount", night)
			sky_material.set_shader_parameter("sun_energy", lerpf(30.0, 4.0, golden))
			var zenith := Color(0.12, 0.26, 0.55).lerp(Color(0.03, 0.04, 0.11), night)
			zenith = zenith.lerp(Color(0.24, 0.2, 0.34), golden * 0.55)
			var horizon := Color(0.62, 0.73, 0.9).lerp(Color(0.05, 0.07, 0.14), night)
			horizon = horizon.lerp(Color(0.98, 0.55, 0.28), golden * 0.8)
			sky_material.set_shader_parameter("zenith_color", zenith)
			sky_material.set_shader_parameter("horizon_color", horizon)
			sky_material.set_shader_parameter("sun_color", Color(1.0, 0.92, 0.8).lerp(Color(1.0, 0.52, 0.22), golden))
			sky_material.set_shader_parameter("cloud_tint", Color(0.95, 0.95, 0.97).lerp(Color(0.09, 0.11, 0.18), night).lerp(Color(1.0, 0.68, 0.45), golden * 0.7))
			sky_material.set_shader_parameter("ground_color", Color(0.24, 0.21, 0.17).lerp(Color(0.02, 0.02, 0.03), night))
		env.ambient_light_energy = lerpf(0.35, 1.0, day_factor)
		env.ambient_light_sky_contribution = lerpf(0.55, 0.9, day_factor)
		env.tonemap_exposure = lerpf(0.92, 1.02, day_factor)
		env.fog_light_color = Color(0.55, 0.62, 0.74).lerp(Color(0.06, 0.08, 0.14), night).lerp(Color(0.95, 0.66, 0.42), golden * 0.6)
		env.fog_density = lerpf(0.0045, 0.008, golden) + 0.002 * night
		if env.volumetric_fog_enabled:
			env.volumetric_fog_albedo = Color(0.9, 0.92, 0.95).lerp(Color(0.25, 0.3, 0.42), night)
		env.glow_intensity = lerpf(0.4, 0.62, night)
