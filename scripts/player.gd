class_name Player
extends Animal
## The animal you play. Movement, the four bars, eating, drinking, abilities.

signal died(cause: String)
signal note(text: String, kind: int)
signal plant_wanted
signal hurt(amount: float)

const GRAVITY := 15.0
var health := 100.0
var max_health := 100.0
var stamina := 100.0
var max_stamina := 100.0
var food := 100.0
var water := 100.0
var speed_mult := 0.8
var vy := 0.0
var air := 0.0                 # height above the ground while jumping
var swimming := false
var sprinting := false
const THIRST_TIME := 30.0
var thirst_left := 0.0          # seconds left to drink once the water bar is empty (0 = not counting)
var action := ""               # "", "graze", "drink"
var action_time := 0.0
var poison := 0.0
var step_acc := 0.0
var exhausted := false
var regen_block := 0.0
var cause := ""
var splash: CPUParticles3D
var distance_walked := 0.0
var _warn_food := false
var _warn_water := false
var ch := {}                   # D.CHARACTERS entry

## swaps the playable animal (menu choice)
func set_character(sp: String) -> void:
	if species == sp and model != null: return
	clear_model()
	ch = D.CHARACTERS[sp]
	setup(sp)

func setup_player(sp: String) -> void:
	set_character(sp)
	splash = CPUParticles3D.new()
	splash.emitting = false
	splash.amount = 14
	splash.lifetime = 0.55
	splash.one_shot = false
	splash.explosiveness = 0.2
	splash.direction = Vector3.UP
	splash.spread = 50.0
	splash.initial_velocity_min = 1.6
	splash.initial_velocity_max = 3.2
	splash.gravity = Vector3(0, -9, 0)
	splash.scale_amount_min = 0.5
	splash.scale_amount_max = 1.0
	var q := QuadMesh.new(); q.size = Vector2(0.22, 0.22)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.85, 0.93, 1.0, 0.75)
	m.albedo_texture = load("res://assets/textures/blob.png")
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	q.material = m
	splash.mesh = q
	splash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(splash)

## start of a run: bars full, permanent abilities applied from the save file
func reset_run(at: Vector2) -> void:
	alive = true
	cause = ""
	refresh_abilities()
	health = max_health; stamina = max_stamina; food = 100.0; water = 100.0; thirst_left = 0.0
	poison = 0.0; vy = 0.0; air = 0.0; action = ""; exhausted = false; regen_block = 0.0
	distance_walked = 0.0
	_warn_food = false; _warn_water = false
	place(at.x, at.y)
	yaw = 0.0; rotation.y = 0.0
	if model: model.rotation = Vector3.ZERO
	cur_anim = ""
	play("idle")
	set_tier(TIER_NEAR)

func refresh_abilities() -> void:
	var keep_h := max_health - health
	var keep_s := max_stamina - stamina
	speed_mult = 0.8 + 0.035 * mini(Save.ability("clover"), D.CLOVER_MAX)
	max_health = float(ch.hp) + 10.0 * Save.ability("ironbark")
	max_stamina = float(ch.stamina) + 10.0 * Save.ability("sunberry")
	health = max_health - keep_h
	stamina = max_stamina - keep_s

func has(key: String) -> bool:
	return Save.ability(key) > 0

func speed_percent() -> int:
	return int(round(speed_mult * 100.0))

func context() -> String:
	if not alive or air > 0.05: return ""
	var f := forward()
	var ahead := World.height(position.x + f.x * 1.3, position.z + f.y * 1.3)
	var here := World.height(position.x, position.z)
	if (here < 0.12 or ahead < 0.02) and water < 99.0: return "drink"
	if swimming: return ""
	var b := World.biome(position.x, position.z)
	if (b == World.FOREST or b == World.GRASS) and food < 99.0: return "graze"
	return ""

func damage(amount: float, why: String) -> void:
	if not alive: return
	health -= amount
	regen_block = 6.0
	action = ""
	hurt.emit(amount)
	if health <= 0.0:
		health = 0.0
		die(why)

func die(why: String) -> void:
	if not alive: return
	alive = false
	cause = why
	action = ""
	speed = 0.0
	noise = 0.0
	splash.emitting = false
	cur_anim = ""
	play("death")
	died.emit(why)

func heal(v: float) -> void:
	health = minf(max_health, health + v)

func update(delta: float, move: Vector2, cam_yaw: float, want_sprint: bool, want_sneak: bool, want_jump: bool, want_action: bool) -> void:
	if not alive:
		if in_water: position.y = -swim_depth
		return
	# ---- bars ----
	var hungry := 100.0 / 420.0
	var thirsty := 100.0 / 330.0
	if sprinting: hungry *= 1.6; thirsty *= 1.6
	food = maxf(0.0, food - hungry * delta)
	water = maxf(0.0, water - thirsty * delta)
	if food < 20.0 and not _warn_food:
		_warn_food = true; note.emit("You are hungry. Graze on grass.", 1)
	elif food > 35.0: _warn_food = false
	if water < 20.0 and not _warn_water:
		_warn_water = true; note.emit("You are thirsty. Find water.", 1)
	elif water > 35.0: _warn_water = false
	regen_block = maxf(0.0, regen_block - delta)
	if food <= 0.0:
		health -= 1.6 * delta
		if health <= 0.0: health = 0.0; die("Starvation"); return
	if water <= 0.0:
		# an empty water bar starts a 30 second countdown instead of hurting at once
		if thirst_left <= 0.0:
			thirst_left = THIRST_TIME
			note.emit("Water is empty! Drink within %d seconds." % int(THIRST_TIME), 2)
		thirst_left -= delta
		if thirst_left <= 0.0:
			thirst_left = 0.0; health = 0.0; die("Thirst"); return
	else: thirst_left = 0.0
	if poison > 0.0:
		poison -= delta
		health -= 4.0 * delta
		if health <= 0.0: health = 0.0; die("Poison"); return
	elif regen_block <= 0.0 and food > 35.0 and water > 35.0 and health < max_health:
		health = minf(max_health, health + 1.3 * delta)
	# ---- input to movement ----
	var mlen := minf(move.length(), 1.0)
	var moving := mlen > 0.12
	if moving or want_jump: action = ""
	var h_here := World.height(position.x, position.z)
	swimming = h_here < -swim_depth and air <= 0.0
	sneaking = want_sneak and not swimming
	sprinting = want_sprint and moving and not exhausted and not sneaking and stamina > 0.0
	var target_speed := 0.0
	if moving:
		if swimming: target_speed = 4.3 if has("lotus") else 2.7
		elif sneaking: target_speed = 2.0
		elif sprinting: target_speed = ch.run
		else: target_speed = ch.walk
		target_speed *= speed_mult * lerpf(0.55, 1.0, mlen)
		if not swimming and h_here < -0.25: target_speed *= 0.7      # wading
	speed = move_toward(speed, target_speed, delta * (22.0 if target_speed > speed else 30.0))
	if sprinting:
		stamina = maxf(0.0, stamina - 6.5 * delta)
		if stamina <= 0.0:
			exhausted = true
			note.emit("Out of breath!", 1)
	else:
		var regen := 9.5 if not moving else 6.0
		if swimming: regen = -1.2 if moving else 1.0
		if food < 20.0 or water < 20.0: regen *= 0.5
		stamina = clampf(stamina + regen * delta, 0.0, max_stamina)
		if exhausted and stamina > max_stamina * 0.25: exhausted = false
	if moving:
		var mv := move.normalized()         # x = right, y = forward on the stick
		var dir := Vector2(cos(cam_yaw) * mv.x - sin(cam_yaw) * mv.y, -sin(cam_yaw) * mv.x - cos(cam_yaw) * mv.y)
		face(dir, delta, 9.0 if not swimming else 4.5)
	if speed > 0.02:
		var f := forward()
		var nx := position.x + f.x * speed * delta
		var nz := position.z + f.y * speed * delta
		var np := World.collide_trees(Vector2(nx, nz), 0.45)
		nx = np.x; nz = np.y
		if World.playable(nx, nz) and _slope_ok(nx, nz):
			position.x = nx; position.z = nz
			distance_walked += speed * delta
		elif World.playable(nx, position.z) and _slope_ok(nx, position.z): position.x = nx
		elif World.playable(position.x, nz) and _slope_ok(position.x, nz): position.z = nz
		else: speed = 0.0
	# ---- vertical ----
	var ground := World.height(position.x, position.z)
	var was_water := in_water
	in_water = ground < -swim_depth
	var floor_y := -swim_depth if in_water else ground
	if want_jump and air <= 0.0 and not in_water and stamina >= 5.0 and action == "" and float(ch.jump) > 0.0:
		vy = (7.6 if has("springlily") else 5.6) * sqrt(float(ch.jump))
		stamina -= 5.0
		air = 0.01
	if air > 0.0 or vy > 0.0:
		vy -= GRAVITY * delta
		air += vy * delta
		if air <= 0.0:
			air = 0.0; vy = 0.0
			if ground < 0.0: _splash_sound(0.9)
			elif not has("ghostfern"): Sfx.play("step%d" % (1 + randi() % 4), 0.5, 0.8)
	position.y = floor_y + air
	if in_water and not was_water and air <= 0.0: _splash_sound(0.8)
	splash.emitting = (in_water and speed > 0.5 and air <= 0.0) or (ground < -0.05 and ground >= -swim_depth and speed > 2.5 and air <= 0.0)
	splash.position.y = (-position.y) + 0.05 if ground < 0.0 else 0.0
	if blob: blob.visible = not in_water and air < 2.5
	hide_kind = 2 if World.thicket_at(position.x, position.z) >= 0 else (1 if air <= 0.0 and not in_water and World.bush_at(position.x, position.z) else 0)
	hidden = hide_kind > 0
	# ---- noise heard by hunters ----
	if has("ghostfern"): noise = 0.0
	elif speed < 0.3: noise = 0.0
	elif in_water: noise = 15.0
	elif sneaking: noise = 3.0
	elif sprinting: noise = 26.0
	else: noise = 12.0
	if action != "": noise = maxf(noise, 5.0 if not has("ghostfern") else 0.0)
	# ---- eat / drink ----
	if want_action and action == "" and air <= 0.0:
		plant_wanted.emit()        # the game eats a rare plant if one is in reach, else calls begin_context()
	if action != "":
		speed = 0.0
		action_time += delta
		play("eat")
		if action_time >= 1.5:
			action_time = 0.0
			if action == "graze":
				food = minf(100.0, food + 15.0)
				Sfx.play("eat", 0.5, randf_range(0.9, 1.1))
				if food >= 100.0: action = ""; note.emit("Food is full.", 0)
			elif action == "drink":
				water = minf(100.0, water + 24.0)
				Sfx.play("drink", 0.5, randf_range(0.9, 1.1))
				if water >= 100.0: action = ""; note.emit("Water is full.", 0)
	elif air > 0.0:
		play("jump", 1.0)
	elif in_water:
		play("walk", 0.9 if speed > 0.3 else 0.35)
	else:
		locomotion(speed)
	# ---- footsteps ----
	if speed > 0.3 and air <= 0.0:
		step_acc += speed * delta
		var stride := 1.5 if speed < 4.0 else 2.6
		if step_acc >= stride:
			step_acc = 0.0
			if ground < 0.02: _splash_sound(0.35 if not in_water else 0.5)
			elif not has("ghostfern"):
				Sfx.play("step%d" % (1 + randi() % 4), 0.12 if sneaking else (0.42 if sprinting else 0.28), randf_range(0.9, 1.15))

func begin_context() -> void:
	var c := context()
	if c == "": return
	action = c
	action_time = 0.6
	speed = 0.0

func _splash_sound(v: float) -> void:
	Sfx.play("splash%d" % (1 + randi() % 3), v, randf_range(0.9, 1.1))

func _slope_ok(x: float, z: float) -> bool:
	# the mountain ring: no climbing when the ground rises too steeply
	var h0 := World.height(position.x, position.z)
	var h1 := World.height(x, z)
	var run := Vector2(x - position.x, z - position.z).length()
	if run < 0.0001: return true
	return (h1 - h0) / run < 1.15 or h1 < 14.0
