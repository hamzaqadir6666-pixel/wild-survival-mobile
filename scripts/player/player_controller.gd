extends CharacterBody3D
## Third-person cowboy controller: walking, sprinting, crouching, jumping,
## aiming, shooting, reloading, mounting a horse and interacting with the world.

signal interacted(target: Node)
signal mounted_changed(mounted: bool)

const WALK_SPEED := 2.6
const RUN_SPEED := 5.4
const SPRINT_SPEED := 8.2
const CROUCH_SPEED := 1.5
const AIM_WALK_SPEED := 2.2
const ACCEL := 12.0
const AIR_ACCEL := 3.0
const JUMP_VELOCITY := 5.2
const GRAVITY := 16.0
const TURN_SPEED := 10.0
const MOUSE_SENS := 0.0026
const SPRINT_DRAIN := 11.0
const STAMINA_REGEN := 16.0

@onready var model_root: Node3D = $ModelRoot
@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D
@onready var collision: CollisionShape3D = $Collision

var anim: AnimationPlayer
var anim_tree: AnimationTree
var animation_state: String = "Idle_Loop"
var yaw := 0.0
var pitch := -0.14
var is_sprinting := false
var is_crouching := false
var is_aiming := false
var is_firing := false
var mounted := false
var horse: Node3D = null
var camera_mode := 0
var _fire_cooldown := 0.0
var _reload_timer := 0.0
var _reloading := false
var _jump_hold := 0.0
var _step_timer := 0.0
var _camera_shake := 0.0
var _recoil := 0.0
var _interact_target: Node = null
var _attack_cooldown := 0.0
var _death_timer := 0.0
var _footstep_index := 0
var weapon_models: Dictionary = {}
var current_weapon_node: Node3D = null
var _last_gunshot_alert := 0.0


func _ready() -> void:
	add_to_group("player")
	collision_layer = 2
	collision_mask = 1 | 32
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	camera_mode = clampi(GameState.camera_mode, 0, 2)
	_apply_camera_mode(camera_mode, true)
	GameState.weapon_changed.connect(_on_weapon_changed)
	GameState.player_died.connect(_on_player_died)
	GameState.game_loaded.connect(_on_game_loaded)


func setup(p_model: Node3D) -> void:
	model_root.add_child(p_model)
	_build_weapons()
	_build_animation_player(p_model)
	_on_weapon_changed(GameState.current_weapon)


func _build_weapons() -> void:
	# Simple-but-readable weapon silhouettes parented to the right hand bone when
	# available, otherwise to a fixed socket in front of the chest.
	var hand := _find_bone("hand_r")
	var holder := Node3D.new()
	holder.name = "WeaponHolder"
	if hand:
		hand.add_child(holder)
		holder.position = Vector3(0.0, 0.02, 0.03)
		holder.rotation_degrees = Vector3(-72, 0, 0)
	else:
		add_child(holder)
		holder.position = Vector3(0.22, 1.28, -0.32)
	weapon_models["revolver"] = _make_weapon_mesh("revolver", Color(0.10, 0.10, 0.11))
	weapon_models["rifle"] = _make_weapon_mesh("rifle", Color(0.13, 0.09, 0.05))
	weapon_models["shotgun"] = _make_weapon_mesh("shotgun", Color(0.11, 0.08, 0.06))
	for k in weapon_models.keys():
		var n: Node3D = weapon_models[k]
		holder.add_child(n)
		n.visible = false
	weapon_models["_holder"] = holder


func _find_bone(bone_name: String) -> Node3D:
	var skel := _find_skel(model_root)
	if skel == null:
		return null
	var idx := skel.find_bone(bone_name)
	if idx < 0:
		return null
	var att := BoneAttachment3D.new()
	att.bone_name = bone_name
	skel.add_child(att)
	return att


func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skel(c)
		if r:
			return r
	return null


func _make_weapon_mesh(kind: String, color: Color) -> Node3D:
	var root := Node3D.new()
	root.name = kind.capitalize()
	var metal := StandardMaterial3D.new()
	metal.albedo_color = color
	metal.metallic = 0.85
	metal.roughness = 0.32
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.28, 0.16, 0.08)
	wood.roughness = 0.6
	match kind:
		"revolver":
			_add_box(root, Vector3(0.05, 0.06, 0.24), Vector3(0, 0.02, -0.09), metal)
			_add_box(root, Vector3(0.04, 0.10, 0.05), Vector3(0, -0.05, 0.02), wood, Vector3(0.28, 0, 0))
			_add_cyl(root, 0.032, 0.07, Vector3(0, 0.005, -0.03), metal)
		"rifle":
			_add_box(root, Vector3(0.055, 0.07, 0.62), Vector3(0, 0.02, -0.2), metal)
			_add_box(root, Vector3(0.05, 0.09, 0.26), Vector3(0, -0.02, 0.16), wood)
			_add_box(root, Vector3(0.045, 0.05, 0.30), Vector3(0, 0.02, -0.55), metal)
			_add_cyl(root, 0.016, 0.5, Vector3(0, 0.05, -0.42), metal, Vector3(PI / 2, 0, 0))
		"shotgun":
			_add_box(root, Vector3(0.06, 0.075, 0.5), Vector3(0, 0.02, -0.16), metal)
			_add_box(root, Vector3(0.055, 0.085, 0.28), Vector3(0, -0.03, 0.2), wood)
			_add_cyl(root, 0.022, 0.62, Vector3(-0.016, 0.045, -0.42), metal, Vector3(PI / 2, 0, 0))
			_add_cyl(root, 0.022, 0.62, Vector3(0.016, 0.045, -0.42), metal, Vector3(PI / 2, 0, 0))
	return root


func _add_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _add_cyl(parent: Node3D, radius: float, height: float, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 12
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _build_animation_player(p_model: Node3D) -> void:
	anim = AnimationPlayer.new()
	anim.name = "AnimPlayer"
	p_model.add_child(anim)
	var ap := p_model.find_children("*", "AnimationPlayer", true, false)
	if not ap.is_empty():
		anim = ap[0]
	anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	_configure_animation(anim)
	var first := _resolve_anim("Idle_Loop")
	if first != "":
		anim.play(first)


## Godot already set loop_mode from the glTF "_Loop" suffixes on import, so only
## correct the handful of clips it could not decide (and the walking variants
## the exporter marks as one-shots).
const LOOPING_CLIPS := [
	"Idle", "Walk", "Jog_Fwd", "Sprint", "Crouch_Idle", "Crouch_Fwd",
	"Pistol_Idle", "Idle_FoldArms", "Idle_Talking", "Walk_Formal",
	"Sitting_Idle", "Consume",
]


func _configure_animation(player: AnimationPlayer) -> void:
	for clip in LOOPING_CLIPS:
		var a := player.get_animation(clip) if player.has_animation(clip) else null
		if a:
			a.loop_mode = Animation.LOOP_LINEAR
	for one_shot in ["Pistol_Shoot", "Pistol_Reload", "Jump_Start", "Jump_Land",
			"Interact", "Hit_Chest", "Hit_Head", "Hit_Knockback", "Death01", "Roll", "Yes"]:
		var b := player.get_animation(one_shot) if player.has_animation(one_shot) else null
		if b:
			b.loop_mode = Animation.LOOP_NONE


func _unhandled_input(event: InputEvent) -> void:
	# while a HUD panel owns the screen, the panel handles its own keys
	var hud_node := get_tree().get_first_node_in_group("hud")
	if hud_node and hud_node.has_method("panels_open") and hud_node.panels_open():
		if event is InputEventMouseMotion:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not mounted:
		yaw -= event.relative.x * MOUSE_SENS * GameState.mouse_sensitivity
		pitch = clampf(pitch - event.relative.y * MOUSE_SENS * GameState.mouse_sensitivity, -1.15, 0.85)
	elif event.is_action_pressed("camera_toggle"):
		_cycle_camera()
	elif event.is_action_pressed("pause"):
		if hud_node and hud_node.has_method("toggle_pause"):
			hud_node.toggle_pause()
	elif event.is_action_pressed("aim_hold"):
		if not mounted:
			is_aiming = true
	elif event.is_action_released("aim_hold"):
		is_aiming = false
	elif event.is_action_pressed("weapon_1"):
		GameState.select_weapon("revolver")
	elif event.is_action_pressed("weapon_2"):
		GameState.select_weapon("rifle")
	elif event.is_action_pressed("weapon_3"):
		GameState.select_weapon("shotgun")
	elif event.is_action_pressed("weapon_next"):
		GameState.cycle_weapon(1)
	elif event.is_action_pressed("reload"):
		_start_reload()
	elif event.is_action_pressed("interact"):
		_try_interact()
	elif event.is_action_pressed("crouch"):
		if not mounted:
			is_crouching = not is_crouching
	elif event.is_action_pressed("map"):
		_toggle_ui("map")
	elif event.is_action_pressed("journal"):
		_toggle_ui("journal")
	elif event.is_action_pressed("inventory"):
		_toggle_ui("journal")
	elif event.is_action_pressed("quick_save"):
		SaveSystem.save_game(0)


func _toggle_ui(which: String) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("open_panel"):
		hud.open_panel(which)


func _physics_process(delta: float) -> void:
	if _death_timer > 0.0:
		return
	_fire_cooldown -= delta
	_reload_timer -= delta
	_attack_cooldown -= delta
	_handle_gravity(delta)
	if mounted and horse and horse.has_method("drive_from_player"):
		horse.drive_from_player(self, delta)
		_set_camera()
		_update_aiming(delta)
		return
	_handle_movement(delta)
	_handle_shooting(delta)
	_update_animation(delta)
	_update_interaction()
	_set_camera()
	_update_aiming(delta)


func _handle_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		if velocity.y < 0.0:
			velocity.y = -0.2


func _handle_movement(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := Vector3(input.x, 0, input.y).rotated(Vector3.UP, yaw).normalized()
	var moving := input.length() > 0.05
	var want_sprint := Input.is_action_pressed("sprint") and not is_aiming and not is_crouching
	if want_sprint and moving and GameState.stamina > 1.0 and is_on_floor():
		is_sprinting = true
	else:
		is_sprinting = false

	var target_speed := WALK_SPEED
	if is_crouching:
		target_speed = CROUCH_SPEED
	elif is_sprinting:
		target_speed = SPRINT_SPEED
	elif is_aiming:
		target_speed = AIM_WALK_SPEED
	elif Input.is_action_pressed("move_forward") or moving:
		target_speed = RUN_SPEED if moving else WALK_SPEED
	if not moving:
		target_speed = 0.0

	var desired := dir * target_speed
	var accel := ACCEL if is_on_floor() else AIR_ACCEL
	velocity.x = move_toward(velocity.x, desired.x, accel * delta * 6.0)
	velocity.z = move_toward(velocity.z, desired.z, accel * delta * 6.0)

	if is_on_floor():
		if Input.is_action_just_pressed("jump") and not is_crouching:
			velocity.y = JUMP_VELOCITY
			_play_anim("Jump_Start", 0.12)
			_jump_hold = 0.35
		if moving:
			if is_sprinting:
				GameState.use_stamina(SPRINT_DRAIN * delta)
			else:
				GameState.recover_stamina(STAMINA_REGEN * 0.4 * delta)
		else:
			GameState.recover_stamina(STAMINA_REGEN * delta)
	else:
		GameState.recover_stamina(STAMINA_REGEN * 0.15 * delta)

	move_and_slide()

	# face the movement direction
	if moving:
		var target_yaw := atan2(dir.x, dir.z)
		var body := model_root.global_rotation.y
		model_root.rotation.y = lerp_angle(body, target_yaw, clampf(TURN_SPEED * delta, 0.0, 1.0))
	if is_aiming or is_firing:
		model_root.rotation.y = lerp_angle(model_root.rotation.y, yaw, clampf(16.0 * delta, 0.0, 1.0))

	_footsteps(delta, moving)


func _footsteps(delta: float, moving: bool) -> void:
	if not moving or not is_on_floor():
		return
	var speed := Vector2(velocity.x, velocity.z).length()
	if speed < 0.5:
		return
	_step_timer -= delta * (speed / RUN_SPEED)
	if _step_timer <= 0.0:
		_step_timer = 0.55 if not is_sprinting else 0.36
		var sfx := "step_grass"
		var below := _ground_type()
		if below == "wood":
			sfx = "step_wood"
		elif below == "dirt":
			sfx = "step_dirt"
		AudioManager.play_sfx(sfx, randf_range(0.92, 1.08), -12.0 if not is_sprinting else -8.0)
		if is_sprinting or randf() < 0.25:
			FXManager.spawn_dust(global_position + Vector3(0, 0.05, 0), 0.3, 4)


func _ground_type() -> String:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0, 0.5, 0)
	var to := global_position + Vector3(0, -1.2, 0)
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return "grass"
	var c: Node = hit.get("collider")
	if c and c.has_meta("surface"):
		return str(c.get_meta("surface"))
	return "grass"


func _update_animation(delta: float) -> void:
	if anim == null:
		return
	var speed := Vector2(velocity.x, velocity.z).length()
	var target := "Idle_Loop"
	if not is_on_floor():
		target = "Jump_Loop" if velocity.y > 0.4 else "Jump_Land"
	elif is_crouching:
		target = "Crouch_Fwd_Loop" if speed > 0.4 else "Crouch_Idle_Loop"
	elif is_aiming or is_firing:
		target = "Pistol_Idle_Loop" if speed < 0.5 else "Walk_Loop"
	elif speed > 6.2:
		target = "Sprint_Loop"
	elif speed > 3.0:
		target = "Jog_Fwd_Loop"
	elif speed > 0.35:
		target = "Walk_Loop"
	if _reloading:
		target = "Pistol_Reload"
	if target != animation_state:
		_play_anim(target, 0.18)
	# playback speed matches movement so feet don't slide
	if anim.current_animation in ["Walk_Loop", "Jog_Fwd_Loop", "Sprint_Loop"]:
		var base_speed := {"Walk_Loop": 2.4, "Jog_Fwd_Loop": 4.6, "Sprint_Loop": 7.6}
		anim.speed_scale = clampf(speed / maxf(0.6, base_speed.get(anim.current_animation, 3.0)), 0.6, 1.8)
	else:
		anim.speed_scale = 1.0


## Godot's glTF importer strips a trailing "_Loop" from clip names and turns it
## into LOOP_LINEAR, so "Idle_Loop" arrives as "Idle". Resolve both spellings.
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

func _play_anim(name: String, blend: float = 0.2) -> void:
	var resolved := _resolve_anim(name)
	if resolved == "":
		# graceful fallback when a clip is named differently in the source rig
		var fallback := _fallback_for(name)
		resolved = _resolve_anim(fallback)
		if resolved == "":
			return
	if anim.current_animation == resolved:
		return
	anim.play(resolved, blend)
	animation_state = resolved


func _fallback_for(name: String) -> String:
	match name:
		"Jog_Fwd_Loop":
			return "Walk_Loop"
		"Sprint_Loop":
			return "Jog_Fwd_Loop"
		"Pistol_Idle_Loop":
			return "Idle_Loop"
		"Pistol_Shoot":
			return "Pistol_Idle_Loop"
		"Pistol_Reload":
			return "Idle_Loop"
		"Jump_Loop", "Jump_Land", "Jump_Start":
			return "Idle_Loop"
		"Crouch_Idle_Loop":
			return "Idle_Loop"
		"Crouch_Fwd_Loop":
			return "Walk_Loop"
		"Interact":
			return "Idle_Loop"
	return ""


func _update_aiming(delta: float) -> void:
	if current_weapon_node == null:
		return
	var target_rot := 0.0
	if is_aiming:
		target_rot = 0.25
	current_weapon_node.rotation.x = lerp_angle(current_weapon_node.rotation.x, target_rot, delta * 8.0)


func _set_camera() -> void:
	camera_pivot.global_position = global_position + Vector3(0, 1.62 if not is_crouching else 1.05, 0)
	# smooth the pivot so steps don't jolt the view
	var desired_pitch := pitch
	if camera_mode == 2:  # first person
		desired_pitch = clampf(pitch, -1.0, 0.9)
	camera_pivot.rotation = Vector3(desired_pitch, yaw, 0)
	if _recoil > 0.0:
		camera_pivot.rotation.x -= _recoil * 0.02
		_recoil = move_toward(_recoil, 0.0, 6.0 * get_physics_process_delta_time())
	match camera_mode:
		0:
			spring_arm.position = Vector3(0.42, 0.0, 0.0)
		1:
			spring_arm.position = Vector3(0.0, 0.15, 0.0)
		2:
			spring_arm.position = Vector3(0.0, 0.1, 0.0)
	camera.fov = lerpf(camera.fov, 62.0 if not is_aiming else 46.0, 0.12)
	if _camera_shake > 0.0:
		var t := Time.get_ticks_msec() / 1000.0
		camera.h_offset = sin(t * 47.0) * _camera_shake * 0.12
		camera.v_offset = cos(t * 39.0) * _camera_shake * 0.12
		_camera_shake = move_toward(_camera_shake, 0.0, 3.0 * get_physics_process_delta_time())
	else:
		camera.h_offset = 0.0
		camera.v_offset = 0.0
	if camera_mode == 2:
		spring_arm.spring_length = 0.0
		if model_root:
			model_root.visible = false
	else:
		if model_root:
			model_root.visible = true
		var target_len := 3.4 if not is_aiming else 2.0
		if is_aiming and camera_mode == 1:
			target_len = 1.5
		spring_arm.spring_length = lerpf(spring_arm.spring_length, target_len, 0.09)


func _cycle_camera() -> void:
	camera_mode = (camera_mode + 1) % 3
	GameState.camera_mode = camera_mode
	_apply_camera_mode(camera_mode)


func _apply_camera_mode(mode: int, force: bool = false) -> void:
	camera_mode = mode
	if mode == 2:
		# first person: hide the body so the head doesn't fill the screen
		spring_arm.spring_length = 0.0
		camera.near = 0.05
		camera.fov = 74.0 if not force else camera.fov
		if model_root:
			model_root.visible = false
	else:
		spring_arm.spring_length = 3.4
		camera.near = 0.08
		if model_root:
			model_root.visible = true


func _handle_shooting(delta: float) -> void:
	if mounted:
		return
	var trigger := Input.is_action_pressed("fire")
	if not trigger:
		return
	if _fire_cooldown > 0.0 or _reloading or _death_timer > 0.0:
		return
	var w: Dictionary = GameState.weapon_data()
	if w.is_empty():
		return
	if not w.get("auto", false):
		if not Input.is_action_just_pressed("fire"):
			return
	if int(w["clip"]) <= 0:
		AudioManager.play_sfx("dry_fire", randf_range(0.95, 1.05), -8.0)
		_fire_cooldown = 0.35
		_start_reload()
		return
	_fire()
	_fire_cooldown = float(w["rate"])


func _fire() -> void:
	var w: Dictionary = GameState.weapon_data()
	if not GameState.consume_ammo():
		return
	is_firing = true
	var shooter_origin := camera.global_position
	var aim_dir := -camera.global_basis.z
	var spread := float(w["spread"])
	if is_aiming:
		spread *= 0.35
	if not is_on_floor():
		spread *= 1.8
	var pellets := int(w["pellets"])
	var range_m := float(w["range"])
	var dmg := float(w["damage"])
	var space := get_world_3d().direct_space_state
	for p in pellets:
		var dir := aim_dir
		dir += camera.global_basis.x * randf_range(-spread, spread)
		dir += camera.global_basis.y * randf_range(-spread, spread)
		dir = dir.normalized()
		var from := shooter_origin
		var to := from + dir * range_m
		var q := PhysicsRayQueryParameters3D.create(from, to)
		q.collision_mask = 1 | 4 | 8 | 32 | 128
		q.exclude = [get_rid()]
		var hit := space.intersect_ray(q)
		var end := to
		if not hit.is_empty():
			end = hit["position"]
			var collider: Node = hit.get("collider")
			_on_bullet_hit(collider, hit, dir, dmg)
		if p == 0:
			FXManager.spawn_tracer(_muzzle_position(), end)
	# audio + recoil + flash
	AudioManager.play_sfx(str(w["sound"]), randf_range(0.94, 1.06), 2.0)
	FXManager.spawn_muzzle_flash(_muzzle_position(), aim_dir)
	_recoil += float(w.get("recoil", 2.0))
	_camera_shake = float(w.get("recoil", 2.0)) * 0.25
	_play_anim("Pistol_Shoot", 0.06)
	_alert_npcs()
	if int(GameState.weapon_data().get("clip", 0)) <= 0:
		_start_reload()
	var t := get_tree().create_timer(0.22)
	t.timeout.connect(func() -> void: is_firing = false)


func _muzzle_position() -> Vector3:
	if current_weapon_node:
		return current_weapon_node.global_position + -current_weapon_node.global_basis.z * 0.35
	return global_position + Vector3(0, 1.3, 0) - global_basis.z * 0.6


func _on_bullet_hit(collider: Node, hit: Dictionary, dir: Vector3, damage: float) -> void:
	var pos: Vector3 = hit["position"]
	var normal: Vector3 = hit["normal"]
	if collider and collider.has_method("take_damage"):
		collider.take_damage(damage, pos, dir)
		FXManager.spawn_blood(pos, dir)
		AudioManager.play_sfx("impact_bullet", randf_range(0.9, 1.1), -6.0)
		return
	var kind := "dirt"
	if collider and collider.has_meta("surface"):
		kind = str(collider.get_meta("surface"))
		if kind == "grass":
			kind = "dirt"
	FXManager.spawn_impact(pos, normal, kind)
	AudioManager.play_sfx("impact_bullet" if kind != "wood" else "impact_wood", randf_range(0.85, 1.15), -8.0)


func _alert_npcs() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_gunshot_alert < 0.4:
		return
	_last_gunshot_alert = now
	for n in get_tree().get_nodes_in_group("npcs"):
		if n is Node3D and n.global_position.distance_to(global_position) < 70.0 and n.has_method("hear_gunshot"):
			n.hear_gunshot(global_position)
	# firing inside the town limits wakes the law
	var town := get_tree().get_first_node_in_group("town")
	if town and global_position.distance_to(town.global_position) < 85.0:
		GameState.add_wanted(1)


func _start_reload() -> void:
	if _reloading:
		return
	var w: Dictionary = GameState.weapon_data()
	if w.is_empty() or int(w["clip"]) >= int(w["capacity"]) or int(w["reserve"]) <= 0:
		return
	_reloading = true
	_play_anim("Pistol_Reload", 0.1)
	AudioManager.play_sfx("reload_" + str(GameState.current_weapon), 1.0, -2.0)
	var t := get_tree().create_timer(float(w.get("reload", 0.9)))
	t.timeout.connect(func() -> void:
		GameState.start_reload()
		_reloading = false)


func _update_interaction() -> void:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0, 1.2, 0)
	var dir := -global_basis.z if is_aiming else Vector3(-sin(yaw), 0, -cos(yaw))
	var to := from + dir * 3.2
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 1 | 4 | 32
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	var found: Node = null
	if not hit.is_empty():
		var c: Node = hit.get("collider")
		while c and not c.is_in_group("interactable") and c.get_parent():
			c = c.get_parent()
		if c and c.is_in_group("interactable"):
			found = c
	if found != _interact_target:
		_interact_target = found
		var hud := get_tree().get_first_node_in_group("hud")
		if hud and hud.has_method("set_interact_prompt"):
			var label := "Interact"
			if found and found.has_method("interact_prompt"):
				label = found.interact_prompt()
			if found == null or label == "":
				label = ""
			hud.set_interact_prompt(label)


func _try_interact() -> void:
	if _interact_target and _interact_target.has_method("interact") and is_instance_valid(_interact_target):
		_interact_target.interact(self)
		emit_signal("interacted", _interact_target)
		_play_anim("Interact", 0.1)


func mount(p_horse: Node3D) -> void:
	if p_horse == null:
		return
	horse = p_horse
	mounted = true
	_play_anim("Sitting_Idle_Loop", 0.2)
	horse.mount(self)
	emit_signal("mounted_changed", true)
	camera_mode = 0
	_apply_camera_mode(0)
	GameState.notify("%s has been saddled." % GameState.HORSE_NAME, 2.5)
	AudioManager.play_sfx("horse_snort", 1.0, -4.0)


func dismount() -> void:
	if not mounted:
		return
	mounted = false
	if horse and horse.has_method("dismount"):
		horse.dismount(self)
	var offset := Vector3(1.4, 0, 0).rotated(Vector3.UP, horse.rotation.y if horse else 0.0)
	global_position = (horse.global_position if horse else global_position) + offset + Vector3(0, 0.4, 0)
	horse = null
	_play_anim("Jump_Land", 0.1)
	emit_signal("mounted_changed", false)


func _on_weapon_changed(id: String) -> void:
	for k in weapon_models.keys():
		if k == "_holder":
			continue
		var n: Node3D = weapon_models[k]
		n.visible = (k == id)
	current_weapon_node = weapon_models.get(id, null)


func _on_player_died() -> void:
	_death_timer = 5.0
	_play_anim("Death01", 0.2)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("show_death"):
		hud.show_death()
	var t := get_tree().create_timer(5.0)
	t.timeout.connect(_respawn)


func _respawn() -> void:
	GameState.health = GameState.max_health
	GameState.recover_stamina(GameState.max_stamina)
	GameState.set_wanted(0)
	var world := get_tree().get_first_node_in_group("world")
	var pos := Vector3(-34, 6, -14)
	if world and world.has_method("spawn_position"):
		pos = world.spawn_position()
	global_position = pos
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_death_timer = 0.0
	_play_anim("Idle_Loop", 0.3)
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("hide_death"):
		hud.hide_death()
	GameState.notify("You wake up on the edge of town. Your horse is nearby.", 4.0)
	var h := get_tree().get_first_node_in_group("horse")
	if h and h.has_method("summon_near"):
		h.summon_near(global_position)


func _on_game_loaded() -> void:
	global_position = GameState.player_position + Vector3(0, 1.0, 0)
	model_root.rotation.y = GameState.player_rotation
	yaw = GameState.player_rotation


func take_damage(amount: float, from: Vector3 = Vector3.ZERO) -> void:
	GameState.damage_player(amount)
	_camera_shake = clampf(amount * 0.08, 0.2, 1.2)
	AudioManager.play_sfx("impact_bullet", randf_range(0.8, 1.0), -3.0)
	if GameState.health < 30.0:
		AudioManager.play_sfx("heartbeat", 1.0, -8.0)


func heal(amount: float) -> void:
	GameState.heal_player(amount)
