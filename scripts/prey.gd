class_name Prey
extends Animal
## Harmless wildlife: grazes, wanders near its home, flees from hunters and from the deer.

enum { GRAZE, WANDER, FLEE, DEAD }
var state := GRAZE
var timer := 0.0
var goal := Vector2.ZERO
var flee_from := Vector2.ZERO
var corpse_time := 0.0
var giant := false
var rng := RandomNumberGenerator.new()

func start(h: Vector2) -> void:
	home = h
	rng.randomize()
	respawn()

func respawn() -> void:
	alive = true
	giant = cfg.get("giant", false)
	state = GRAZE
	timer = rng.randf_range(2.0, 9.0)
	var p := World.dry_near(rng, home, 2.0, 16.0)
	place(p.x, p.y)
	yaw = rng.randf() * TAU; rotation.y = yaw
	if model: model.visible = tier != TIER_FAR
	cur_anim = ""
	play("idle")

func kill() -> void:
	if not alive: return
	alive = false
	state = DEAD
	corpse_time = 45.0
	speed = 0.0
	play("death")
	if is_bird and model:
		model.rotation.z = 1.5
		model.position.y = 0.12

func can_enter(x: float, z: float) -> bool:
	return World.playable(x, z) and World.height(x, z) > -0.3

func tick(delta: float) -> void:
	if state == DEAD:
		corpse_time -= delta
		if corpse_time <= 0.0 and fauna.far_from_deer(position, 70.0):
			if is_bird and model: model.rotation.z = 0.0
			respawn()
		return
	timer -= delta
	# danger check a few times per second
	if timer <= 0.0 or state != FLEE:
		var threat: Vector3 = Vector3.ZERO if giant else fauna.threat_near(self)
		if threat.z > 0.0:
			flee_from = Vector2(threat.x, threat.y)
			if state != FLEE:
				state = FLEE
				if cfg.sound != "" and rng.randf() < 0.5: fauna.animal_sound(self, cfg.sound, cfg.get("pitch", 1.0), 0.6)
			timer = rng.randf_range(2.5, 4.5)
	if is_bird and model and state != FLEE: model.position.y = move_toward(model.position.y, 0.0, delta * 3.0)
	match state:
		GRAZE:
			speed = 0.0
			play("eat" if (int(home.x) + get_index()) % 2 == 0 else "idle")
			if timer <= 0.0:
				state = WANDER
				goal = World.dry_near(rng, home, 4.0, 28.0)
				timer = 14.0
		WANDER:
			var left := step_to(goal, cfg.walk, delta, 4.0)
			locomotion(speed)
			if left < 0.5 or timer <= 0.0 or speed == 0.0:
				state = GRAZE
				timer = rng.randf_range(4.0, 14.0)
		FLEE:
			var away := pos2() - flee_from
			if away.length() < 0.1: away = Vector2(1, 0)
			var tgt := pos2() + away.normalized() * 12.0
			if not can_enter(tgt.x, tgt.y): tgt = pos2() + away.normalized().rotated(1.2) * 12.0
			step_to(tgt, cfg.run, delta, 9.0)
			locomotion(speed)
			if is_bird and model: model.position.y = move_toward(model.position.y, 1.6, delta * 3.0)
			if timer <= 0.0:
				state = GRAZE
				timer = rng.randf_range(3.0, 8.0)
				if pos2().distance_to(home) > 120.0: home = pos2()
