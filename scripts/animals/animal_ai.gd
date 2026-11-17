extends CharacterBody3D
## Wildlife: deer, wolves, rabbits, bears, foxes and birds. Wanders and grazes,
## flees from the player, reacts to gunfire; bears and wolves can fight back.

enum Mood { WANDER, GRAZE, FLEE, ALERT, CHASE, DEAD }

@export var animal_name := "Deer"
@export var walk_speed := 1.6
@export var run_speed := 8.5
@export var is_predator := false
@export var max_health := 60.0
@export var flee_distance := 14.0
@export var detect_distance := 38.0

@onready var model_root: Node3D = $ModelRoot

var anim: AnimationPlayer
var mood := Mood.WANDER
var health := 60.0
var yaw := 0.0
var speed := 0.0
var _mood_timer := 2.0
var _target := Vector3.ZERO
var _graze_t := 0.0
var _player: Node3D
var _alert_timer := 0.0
var _attack_cd := 0.0
var _wander_center := Vector3.ZERO
var _idle_sfx := 20.0
var _dead_timer := 0.0


func _ready() -> void:
	add_to_group("animals")
	if is_predator:
		add_to_group("predators")
	collision_layer = 8
	collision_mask = 1 | 32
	health = max_health
	_wander_center = global_position
	randomize()


func setup(p_model: Node3D, p_name: String, p_predator: bool) -> void:
	animal_name = p_name
	is_predator = p_predator
	# the scene is parented before setup() runs, so seed the wander anchor and the
	# predator group here rather than relying on _ready() (which ran at the origin).
	_wander_center = global_position
	if p_predator:
		add_to_group("predators")
	model_root.add_child(p_model)
	var aps := p_model.find_children("*", "AnimationPlayer", true, false)
	if not aps.is_empty():
		anim = aps[0]
		for clip in anim.get_animation_library("").get_animation_list():
			var a := anim.get_animation(clip)
			if clip in ["Idle", "Idle_2", "Idle_Headlow", "Walk", "Gallop", "Eating"]:
				a.loop_mode = Animation.LOOP_LINEAR
		_play("Idle")
	var bb := Vector3.ZERO
	var meshes := model_root.find_children("*", "MeshInstance3D", true, false)
	if not meshes.is_empty():
		var mi: MeshInstance3D = meshes[0]
		if mi.mesh:
			bb = mi.mesh.get_aabb().size * mi.scale
	if bb.y > 3.0:
		var target_h := 1.5
		if animal_name == "Bear":
			target_h = 1.3
		elif animal_name == "Rabbit":
			target_h = 0.4
		p_model.scale = p_model.scale * (target_h / bb.y)


func _physics_process(delta: float) -> void:
	if mood == Mood.DEAD:
		_dead_timer += delta
		if _dead_timer > 30.0:
			queue_free()
		return
	if not is_on_floor():
		velocity.y -= 20.0 * delta
	else:
		velocity.y = -0.2
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	_attack_cd -= delta
	_alert_timer -= delta
	_think(delta)
	var forward := Vector3(-sin(yaw), 0, -cos(yaw))
	var target_vel := forward * speed
	velocity.x = move_toward(velocity.x, target_vel.x, 14.0 * delta)
	velocity.z = move_toward(velocity.z, target_vel.z, 14.0 * delta)
	move_and_slide()
	model_root.rotation.y = lerp_angle(model_root.rotation.y, yaw, clampf(7.0 * delta, 0.0, 1.0))
	_update_anim()
	if _idle_sfx > 0.0:
		_idle_sfx -= delta
		if _idle_sfx <= 0.0:
			_idle_sfx = randf_range(25.0, 70.0)
			var cam := get_viewport().get_camera_3d()
			if cam and cam.global_position.distance_to(global_position) < 45.0:
				if animal_name == "Wolf":
					AudioManager.play_sfx_3d("wolf_howl", global_position, get_parent(), -6.0, randf_range(0.9, 1.1), 120.0)
				elif animal_name == "Deer" or animal_name == "Stag":
					AudioManager.play_sfx_3d("deer_call", global_position, get_parent(), -10.0, randf_range(0.9, 1.1), 70.0)


func _think(delta: float) -> void:
	var player_dist := 9999.0
	var to_player := Vector3.ZERO
	if _player:
		to_player = _player.global_position - global_position
		player_dist = to_player.length()
	if not is_predator and player_dist < flee_distance and _has_line_of_sight(_player):
		mood = Mood.FLEE
		_alert_timer = 3.0
		var away := -to_player
		away.y = 0
		yaw = lerp_angle(yaw, atan2(away.x, away.z), clampf(6.0 * delta, 0.0, 1.0))
		speed = move_toward(speed, run_speed, 20.0 * delta)
		return
	if is_predator and _alert_timer > 0.0 and player_dist < detect_distance:
		mood = Mood.CHASE
		var dirp := to_player
		dirp.y = 0
		if dirp.length() > 0.1:
			yaw = lerp_angle(yaw, atan2(dirp.x, dirp.z), clampf(3.5 * delta, 0.0, 1.0))
		speed = move_toward(speed, run_speed * 0.85, 16.0 * delta)
		if player_dist < 2.8 and _attack_cd <= 0.0:
			_attack_cd = 1.8
			_play("Attack" if animal_name == "Wolf" else "Attack_Headbutt")
			if _player.has_method("take_damage"):
				_player.take_damage(12.0, global_position)
		return
	match mood:
		Mood.FLEE:
			speed = move_toward(speed, 0.0, 8.0 * delta)
			if _alert_timer <= 0.0 and speed < 0.3:
				mood = Mood.WANDER
				_mood_timer = 1.0
		Mood.GRAZE:
			speed = move_toward(speed, 0.0, 8.0 * delta)
			_graze_t -= delta
			if _graze_t <= 0.0:
				mood = Mood.WANDER
				_mood_timer = 0.2
		_:
			_mood_timer -= delta
			if _mood_timer <= 0.0:
				_mood_timer = randf_range(4.0, 11.0)
				if randf() < 0.45:
					mood = Mood.GRAZE
					_graze_t = randf_range(3.0, 8.0)
					speed = 0.0
				else:
					mood = Mood.WANDER
					_pick_target()
			if mood == Mood.WANDER and speed > 0.05:
				var to_t := _target - global_position
				to_t.y = 0
				if to_t.length() < 1.2:
					speed = move_toward(speed, 0.0, 6.0 * delta)
				else:
					yaw = lerp_angle(yaw, atan2(to_t.x, to_t.z), clampf(2.6 * delta, 0.0, 1.0))
					speed = move_toward(speed, walk_speed, 3.0 * delta)


func _pick_target() -> void:
	var ang := randf() * TAU
	var dist := randf_range(6.0, 22.0)
	_target = _wander_center + Vector3(cos(ang) * dist, 0, sin(ang) * dist)
	var world := get_tree().get_first_node_in_group("world")
	if world and world.has_method("terrain_height"):
		_target.y = world.terrain_height(_target.x, _target.z)


func _has_line_of_sight(target: Node3D) -> bool:
	if target == null:
		return false
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0, 1.0, 0)
	var to := target.global_position + Vector3(0, 1.2, 0)
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 1
	var hit := space.intersect_ray(q)
	return hit.is_empty()


func _update_anim() -> void:
	if anim == null:
		return
	var name := "Idle"
	if mood == Mood.DEAD:
		name = "Death"
	elif mood == Mood.GRAZE:
		name = "Eating"
	elif speed > run_speed * 0.6:
		name = "Gallop"
	elif speed > 0.3:
		name = "Walk"
	elif mood == Mood.ALERT:
		name = "Idle_2"
	_play(name)
	if anim and anim.current_animation in ["Walk", "Gallop"]:
		var base := walk_speed if anim.current_animation == "Walk" else run_speed
		anim.speed_scale = clampf(speed / maxf(0.4, base), 0.55, 1.8)


func _play(name: String) -> void:
	if anim == null or not anim.has_animation(name):
		return
	if anim.current_animation != name:
		anim.play(name, 0.2)


func hear_gunshot(from: Vector3) -> void:
	if global_position.distance_to(from) > 90.0:
		return
	if is_predator:
		_alert_timer = 6.0
		mood = Mood.CHASE
		_play("Idle_2")
	else:
		mood = Mood.FLEE
		_alert_timer = 5.0
		var away := global_position - from
		away.y = 0
		yaw = atan2(away.x, away.z)
		speed = run_speed


func take_damage(amount: float, _pos: Vector3 = Vector3.ZERO, _dir: Vector3 = Vector3.ZERO) -> void:
	if mood == Mood.DEAD:
		return
	health -= amount
	AudioManager.play_sfx_3d("impact_bullet", global_position, get_parent(), -4.0, 1.2, 40.0)
	if health <= 0.0:
		_die()
		return
	if is_predator and randf() < 0.7:
		_alert_timer = 8.0
		mood = Mood.CHASE
	else:
		mood = Mood.FLEE
		_alert_timer = 7.0
		var p := get_tree().get_first_node_in_group("player")
		if p:
			var away: Vector3 = global_position - p.global_position
			away.y = 0
			yaw = atan2(away.x, away.z)
		speed = run_speed


func _die() -> void:
	mood = Mood.DEAD
	speed = 0.0
	_play("Death")
	collision_layer = 0
	collision_mask = 0
	var value := 8
	match animal_name:
		"Bear": value = 45
		"Wolf": value = 22
		"Deer", "Stag": value = 18
		"Rabbit": value = 6
		"Fox": value = 12
	GameState.add_hunting_score(animal_name, value)
	var marker := Label3D.new()
	marker.text = "%s\n$%d" % [animal_name, value]
	marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	marker.font_size = 48
	marker.modulate = Color(1, 0.95, 0.7)
	marker.position = Vector3(0, 1.4, 0)
	add_child(marker)
