extends CharacterBody3D
## Human NPC: town residents, shopkeepers, bandits, hunters and sheriffs.
## Schedules drive them between waypoints; they react to gunfire, flee danger
## and bandits will actively hunt the player.

enum Role { RESIDENT, SHOPKEEPER, BANDIT, SHERIFF, HUNTER }

signal died(npc: Node)

@export var role := Role.RESIDENT
@export var display_name := "Resident"
@export var walk_speed := 1.5
@export var run_speed := 5.2
@export var max_health := 70.0
@export var is_armed := false
@export var aggression := 0.0

@onready var model_root: Node3D = $ModelRoot

var anim: AnimationPlayer
var health := 70.0
var yaw := 0.0
var speed := 0.0
var alive := true
var _player: Node3D
var _waypoints: Array[Vector3] = []
var _waypoint_index := 0
var _wait_timer := 0.0
var _idle_anim := "Idle_Loop"
var _alert := 0.0
var _attack_cd := 0.0
var _dead_timer := 0.0
var _home := Vector3.ZERO
var _state := "patrol"
var _talk_timer := 0.0
var _greeted := false


func _ready() -> void:
	add_to_group("npcs")
	add_to_group("interactable")
	collision_layer = 4
	collision_mask = 1 | 2 | 32
	health = max_health
	_home = global_position
	randomize()


func setup(p_model: Node3D, p_name: String, p_role: int) -> void:
	display_name = p_name
	role = p_role
	# _ready() ran before the spawner placed us, so re-anchor the home point here.
	_home = global_position
	model_root.add_child(p_model)
	var aps := p_model.find_children("*", "AnimationPlayer", true, false)
	if not aps.is_empty():
		anim = aps[0]
		for clip in anim.get_animation_library("").get_animation_list():
			var a := anim.get_animation(clip)
			if clip in ["Idle", "Walk", "Run", "Idle_Loop", "Walk_Loop", "Jog_Fwd_Loop"]:
				a.loop_mode = Animation.LOOP_LINEAR
		_idle_anim = _resolve_anim("Idle_Loop")
		_play(_idle_anim)
	match role:
		Role.BANDIT:
			max_health = 60.0
			is_armed = true
			aggression = 0.85
			walk_speed = 1.8
		Role.SHERIFF:
			max_health = 110.0
			is_armed = true
			aggression = 0.6
		Role.HUNTER:
			max_health = 80.0
			is_armed = true
			aggression = 0.2
		_:
			pass
	health = max_health


func set_schedule(points: Array[Vector3]) -> void:
	_waypoints = points
	_waypoint_index = 0


## Godot's glTF importer strips a trailing "_Loop" and sets loop mode from it,
## so "Idle_Loop" arrives as "Idle". Accept either spelling.
func _resolve_anim(clip: String) -> String:
	if anim == null:
		return ""
	if anim.has_animation(clip):
		return clip
	if clip.ends_with("_Loop"):
		var base := clip.trim_suffix("_Loop")
		if anim.has_animation(base):
			return base
	elif anim.has_animation(clip + "_Loop"):
		return clip + "_Loop"
	return ""


func _play(name: String) -> void:
	var clip := _resolve_anim(name)
	if clip == "":
		return
	if anim.current_animation != clip:
		anim.play(clip, 0.25)


func _physics_process(delta: float) -> void:
	if not alive:
		_dead_timer += delta
		if _dead_timer > 12.0 and role == Role.BANDIT:
			queue_free()
		return
	if not is_on_floor():
		velocity.y -= 20.0 * delta
	else:
		velocity.y = -0.2
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	_alert -= delta
	_attack_cd -= delta
	_wait_timer -= delta
	_talk_timer -= delta
	_behave(delta)
	var forward := Vector3(-sin(yaw), 0, -cos(yaw))
	var target_vel := forward * speed
	velocity.x = move_toward(velocity.x, target_vel.x, 12.0 * delta)
	velocity.z = move_toward(velocity.z, target_vel.z, 12.0 * delta)
	move_and_slide()
	model_root.rotation.y = lerp_angle(model_root.rotation.y, yaw, clampf(8.0 * delta, 0.0, 1.0))
	_update_anim(delta)


func _behave(delta: float) -> void:
	var dist := 9999.0
	var to_player := Vector3.ZERO
	if _player:
		to_player = _player.global_position - global_position
		dist = to_player.length()

	# bandits close in and shoot
	if role == Role.BANDIT and dist < 42.0 and _alert > 0.0:
		_state = "attack"
		var flat := to_player
		flat.y = 0
		yaw = lerp_angle(yaw, atan2(flat.x, flat.z), clampf(4.0 * delta, 0.0, 1.0))
		if dist > 12.0:
			speed = move_toward(speed, run_speed * 0.6, 8.0 * delta)
		else:
			speed = move_toward(speed, 0.0, 10.0 * delta)
		if dist < 34.0 and _attack_cd <= 0.0 and _has_los(_player):
			_attack_cd = randf_range(1.1, 2.0)
			_npc_shoot(_player)
		return

	# armed NPCs defend the town
	if (role == Role.SHERIFF) and _alert > 0.0 and dist < 40.0:
		var flat := to_player
		flat.y = 0
		yaw = lerp_angle(yaw, atan2(flat.x, flat.z), clampf(3.0 * delta, 0.0, 1.0))
		if dist > 18.0:
			speed = move_toward(speed, run_speed * 0.5, 6.0 * delta)
		else:
			speed = move_toward(speed, 0.0, 8.0 * delta)
		if _attack_cd <= 0.0 and _has_los(_player):
			_attack_cd = randf_range(1.4, 2.4)
			_npc_shoot(_player)
		return

	# civilians panic and run from gunfire
	if _state == "flee" and _alert > 0.0:
		speed = move_toward(speed, run_speed, 10.0 * delta)
		if _player:
			var away := global_position - _player.global_position
			away.y = 0
			if away.length() > 0.1:
				yaw = lerp_angle(yaw, atan2(away.x, away.z), clampf(3.5 * delta, 0.0, 1.0))
		return
	_state = "patrol"

	# friendly greeting when the player walks up
	if dist < 4.0 and _talk_timer <= 0.0 and role != Role.BANDIT and randf() < 0.4:
		_talk_timer = 14.0
		speed = move_toward(speed, 0.0, 6.0 * delta)
		var flat := to_player
		flat.y = 0
		yaw = lerp_angle(yaw, atan2(flat.x, flat.z), clampf(4.0 * delta, 0.0, 1.0))
		_play("Idle_Talking_Loop")
		return

	# schedule / patrol movement
	if _waypoints.is_empty():
		speed = move_toward(speed, 0.0, 4.0 * delta)
		return
	if _wait_timer > 0.0:
		speed = move_toward(speed, 0.0, 6.0 * delta)
		return
	var target := _waypoints[_waypoint_index % _waypoints.size()]
	var to_t := target - global_position
	to_t.y = 0
	if to_t.length() < 1.4:
		_waypoint_index += 1
		_wait_timer = randf_range(2.0, 7.0)
		speed = move_toward(speed, 0.0, 6.0 * delta)
		return
	yaw = lerp_angle(yaw, atan2(to_t.x, to_t.z), clampf(3.0 * delta, 0.0, 1.0))
	speed = move_toward(speed, walk_speed, 3.0 * delta)


func _update_anim(_delta: float) -> void:
	if anim == null:
		return
	if speed > run_speed * 0.65:
		_play("Jog_Fwd_Loop")
	elif speed > 0.25:
		_play("Walk_Loop")
	elif _talk_timer > 0.0 and _resolve_anim("Idle_Talking_Loop") != "":
		_play("Idle_Talking_Loop")
	else:
		_play(_idle_anim)
	if anim.current_animation in ["Walk", "Walk_Loop", "Run", "Jog_Fwd_Loop"]:
		anim.speed_scale = clampf(maxf(speed, 0.8) / maxf(1.2, walk_speed), 0.6, 1.6)


func _has_los(target: Node3D) -> bool:
	if target == null:
		return false
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0, 1.4, 0)
	var to := target.global_position + Vector3(0, 1.2, 0)
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 1
	return space.intersect_ray(q).is_empty()


func _npc_shoot(target: Node3D) -> void:
	if target == null:
		return
	var dir: Vector3 = (target.global_position + Vector3(0, 1.1, 0)) - (global_position + Vector3(0, 1.4, 0))
	var dist := dir.length()
	dir = dir.normalized()
	dir += Vector3(randf_range(-0.04, 0.04), randf_range(-0.03, 0.03), randf_range(-0.04, 0.04))
	AudioManager.play_sfx_3d("shot_revolver", global_position, get_parent(), 0.0, randf_range(0.92, 1.05), 140.0)
	FXManager.spawn_muzzle_flash(global_position + Vector3(0, 1.4, 0), dir)
	_play("Pistol_Shoot")
	if randf() < 0.55 and dist < 34.0:
		# aim error shrinks with skill
		var hit_roll := randf()
		if hit_roll < 0.6 and target.has_method("take_damage"):
			target.take_damage(randf_range(4.0, 9.0), global_position)
		else:
			FXManager.spawn_impact(target.global_position + Vector3(0, 1.0, 0) + dir * 0.5, -dir, "dirt")
	# Bandits shooting at you is not your crime — heat comes from _die()/take_damage().


func hear_gunshot(from: Vector3) -> void:
	if not alive:
		return
	var d := global_position.distance_to(from)
	if d > 80.0:
		return
	_alert = 8.0
	if role == Role.BANDIT or role == Role.SHERIFF:
		_state = "attack"
	else:
		_state = "flee"


func interact_prompt() -> String:
	if not alive:
		return ""
	match role:
		Role.SHOPKEEPER:
			return "Trade with %s  [E]" % display_name
		Role.SHERIFF:
			return "Talk to Sheriff %s  [E]" % display_name
		Role.BANDIT:
			return "%s (hostile)" % display_name
		_:
			return "Talk to %s  [E]" % display_name


func interact(player: Node) -> void:
	if not alive:
		return
	var mm := get_tree().get_first_node_in_group("mission_manager")
	if mm and mm.has_method("notify_talk"):
		mm.notify_talk(display_name)
	match role:
		Role.SHOPKEEPER:
			var ui := get_tree().get_first_node_in_group("hud")
			if ui and ui.has_method("open_shop"):
				ui.open_shop(self)
		Role.SHERIFF:
			GameState.notify("%s: \"Keep your nose clean, %s. I've got my eye on you.\"" % [display_name, GameState.PLAYER_NAME], 4.5)
		Role.BANDIT:
			_alert = 10.0
			_state = "attack"
			GameState.notify("%s: \"You picked the wrong trail, stranger!\"" % display_name, 3.0)
		_:
			var lines := [
				"Fine weather for riding, ain't it?",
				"Careful out past the ridge — wolves have been bold lately.",
				"The saloon's got the only warm fire in town.",
				"Bandits took the last stagecoach. Sheriff won't say it, but he's worried.",
				"Heard there's gold in the old mine east of here. Heard it's cursed, too.",
			]
			GameState.notify("%s: \"%s\"" % [display_name, lines[randi() % lines.size()]], 4.0)
	_talk_timer = 6.0
	if player and player.has_method("_play_anim"):
		pass


func take_damage(amount: float, _pos: Vector3 = Vector3.ZERO, _dir: Vector3 = Vector3.ZERO) -> void:
	if not alive:
		return
	health -= amount
	AudioManager.play_sfx_3d("impact_bullet", global_position, get_parent(), -2.0, 1.0, 40.0)
	if health <= 0.0:
		_die()
		return
	_alert = 10.0
	_state = "attack" if (role == Role.BANDIT or role == Role.SHERIFF) else "flee"
	if role == Role.BANDIT:
		_attack_cd = 0.4
	if role != Role.BANDIT:
		GameState.add_wanted(1)


func _die() -> void:
	alive = false
	speed = 0.0
	_play("Death01")
	collision_layer = 0
	collision_mask = 0
	remove_from_group("interactable")
	emit_signal("died", self)
	match role:
		Role.BANDIT:
			GameState.add_money(18)
			GameState.notify("Bandit down. $18 on the body.", 3.0)
			GameState.mission_flags["bandits_killed"] = int(GameState.mission_flags.get("bandits_killed", 0)) + 1
		Role.SHERIFF:
			GameState.set_wanted(5)
			GameState.notify("You killed the sheriff. The whole territory is hunting you.", 5.0)
		_:
			GameState.add_wanted(2)
			GameState.notify("%s has been killed." % display_name, 3.0)
	_dead_timer = 0.0
