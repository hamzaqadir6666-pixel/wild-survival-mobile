extends CharacterBody3D
## Rideable horse with a real gait model: walk / trot / canter / gallop,
## stamina, smooth turning and player-driven steering while mounted.

signal mounted_by(player: Node)

const TROT_SPEED := 6.2
const CANTER_SPEED := 10.5
const GALLOP_SPEED := 15.5
const ACCEL := 5.5
const DECEL := 7.0
const TURN_RATE := 2.1
const GRAVITY := 18.0

@onready var model_root: Node3D = $ModelRoot

var anim: AnimationPlayer
var speed := 0.0
var target_speed := 0.0
var yaw := 0.0
var rider: Node = null
var is_mounted := false
var _whinny_timer := 12.0
var _hoof_timer := 0.0
var _call_timer := 0.0
var _graze_timer := 8.0
var _state := "idle"
var _wander_cooldown := 4.0


func _ready() -> void:
	add_to_group("horse")
	add_to_group("interactable")
	collision_layer = 8
	collision_mask = 1 | 32


func setup(p_model: Node3D) -> void:
	model_root.add_child(p_model)
	var aps := p_model.find_children("*", "AnimationPlayer", true, false)
	if not aps.is_empty():
		anim = aps[0]
		for clip in anim.get_animation_library("").get_animation_list():
			var a := anim.get_animation(clip)
			if clip in ["Idle", "Walk", "Gallop", "Eating", "Idle_2", "Idle_Headlow"]:
				a.loop_mode = Animation.LOOP_LINEAR
		_play("Idle")
	# The source horse is authored several times life size; normalise to ~1.6 m at the withers.
	var bb := _model_aabb()
	if bb.size.y > 8.0:
		p_model.scale = Vector3.ONE * (3.6 / bb.size.y)
	elif bb.size.y > 3.0:
		p_model.scale = Vector3.ONE * (2.6 / bb.size.y)


func _model_aabb() -> AABB:
	var total := AABB()
	var first := true
	for m in model_root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = m
		if mi.mesh == null:
			continue
		var a: AABB = mi.global_transform * mi.mesh.get_aabb()
		if first:
			total = a
			first = false
		else:
			total = total.merge(a)
	return total


func _play(name: String) -> void:
	if anim and anim.has_animation(name) and anim.current_animation != name:
		anim.play(name, 0.25)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = -0.2
	if not is_mounted:
		_idle_behaviour(delta)
	var forward := Vector3(-sin(yaw), 0, -cos(yaw))
	var target_vel := forward * speed
	velocity.x = move_toward(velocity.x, target_vel.x, ACCEL * delta * 4.0)
	velocity.z = move_toward(velocity.z, target_vel.z, ACCEL * delta * 4.0)
	move_and_slide()
	model_root.rotation.y = lerp_angle(model_root.rotation.y, yaw, clampf(8.0 * delta, 0.0, 1.0))
	_update_gait(delta)
	_ambient_sounds(delta)
	GameState.horse_position = global_position
	GameState.horse_rot = yaw


func _idle_behaviour(delta: float) -> void:
	_wander_cooldown -= delta
	if _call_timer > 0.0:
		_call_timer -= delta
		var player := get_tree().get_first_node_in_group("player")
		if player:
			var to_p: Vector3 = player.global_position - global_position
			to_p.y = 0
			if to_p.length() > 3.4:
				yaw = lerp_angle(yaw, atan2(to_p.x, to_p.z), clampf(3.0 * delta, 0.0, 1.0))
				speed = move_toward(speed, 4.5, ACCEL * delta)
			else:
				speed = move_toward(speed, 0.0, DECEL * delta)
		return
	if speed > 0.2:
		speed = move_toward(speed, 0.0, DECEL * delta)
		return
	_graze_timer -= delta
	if _graze_timer <= 0.0:
		if _state == "graze":
			_state = "idle"
			_graze_timer = randf_range(5.0, 11.0)
			_play("Idle")
		else:
			_state = "graze"
			_graze_timer = randf_range(3.0, 7.0)
			_play("Eating")
	if _wander_cooldown <= 0.0 and _state != "graze":
		_wander_cooldown = randf_range(10.0, 22.0)
		yaw += randf_range(-0.8, 0.8)
		speed = 1.6


func drive_from_player(player: Node, delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var want_sprint := Input.is_action_pressed("sprint")
	yaw -= input.x * TURN_RATE * delta * (0.55 + clampf(speed / GALLOP_SPEED, 0.0, 1.0) * 0.65)
	var forward_input := -input.y
	if forward_input > 0.1:
		if want_sprint and GameState.horse_stamina > 1.0:
			target_speed = GALLOP_SPEED
		else:
			target_speed = CANTER_SPEED
		var boost := clampf(1.0 - speed / GALLOP_SPEED, 0.0, 1.0)
		speed = move_toward(speed, target_speed, ACCEL * delta * (1.0 + boost))
	elif forward_input < -0.1:
		speed = move_toward(speed, 0.0, DECEL * 1.6 * delta)
	else:
		speed = move_toward(speed, 0.0, DECEL * delta)
	if speed > CANTER_SPEED * 0.92:
		GameState.drain_horse_stamina(9.0 * delta)
	elif speed > TROT_SPEED:
		GameState.drain_horse_stamina(4.5 * delta)
	else:
		GameState.recover_horse_stamina(7.5 * delta)
	if GameState.horse_stamina <= 1.0 and speed > CANTER_SPEED:
		speed = move_toward(speed, CANTER_SPEED, DECEL * delta)
	if rider and is_instance_valid(rider):
		var seat := global_transform * Vector3(0, 1.62, 0.08)
		rider.global_position = seat
		rider.yaw = yaw


func mount(player: Node) -> void:
	is_mounted = true
	rider = player
	target_speed = 0.0
	speed = 0.0
	_play("Idle")
	emit_signal("mounted_by", player)


func dismount(_player: Node) -> void:
	is_mounted = false
	rider = null
	speed = 0.0
	target_speed = 0.0


func _update_gait(delta: float) -> void:
	if speed < 0.25:
		if is_mounted:
			_play("Idle")
	elif speed < TROT_SPEED * 0.9:
		_play("Walk")
	else:
		_play("Gallop")
	if anim and anim.current_animation in ["Walk", "Gallop"]:
		var base := 2.4 if anim.current_animation == "Walk" else 10.0
		anim.speed_scale = clampf(speed / base, 0.6, 1.7)
	if speed > 0.8:
		_hoof_timer -= delta * (speed / 3.0)
		if _hoof_timer <= 0.0:
			_hoof_timer = 0.5
			var cam := get_viewport().get_camera_3d()
			var dist := 10.0
			if cam:
				dist = cam.global_position.distance_to(global_position)
			if dist < 45.0:
				AudioManager.play_sfx_3d("horse_gallop" if speed > 9.0 else "horse_hoof", global_position,
					get_parent(), -6.0 if speed > 9.0 else -10.0, randf_range(0.9, 1.1), 60.0)


func _ambient_sounds(delta: float) -> void:
	_whinny_timer -= delta
	if _whinny_timer <= 0.0:
		_whinny_timer = randf_range(22.0, 55.0)
		var cam := get_viewport().get_camera_3d()
		if cam and cam.global_position.distance_to(global_position) < 40.0:
			AudioManager.play_sfx_3d("horse_snort" if randf() < 0.6 else "horse_whinny", global_position,
				get_parent(), -8.0, randf_range(0.9, 1.1), 50.0)


func call_to_player() -> void:
	_call_timer = 14.0
	AudioManager.play_sfx("whistle", 1.0, -2.0)


func summon_near(pos: Vector3) -> void:
	global_position = pos + Vector3(3.0, 0.8, 2.0)
	speed = 0.0


func interact_prompt() -> String:
	return "Mount %s  [E]" % GameState.HORSE_NAME


func interact(player: Node) -> void:
	if player.has_method("mount"):
		player.mount(self)


func take_damage(_amount: float, _pos: Vector3 = Vector3.ZERO, _dir: Vector3 = Vector3.ZERO) -> void:
	AudioManager.play_sfx_3d("horse_whinny", global_position, get_parent(), 0.0, 1.1, 60.0)
	speed = GALLOP_SPEED
