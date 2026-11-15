class_name Predator
extends Animal
## A hunter. One state machine for all six species; `cfg.style` selects how it
## approaches (ambush, stalk, sprint, pack_circle, pack_chase, water).

enum { REST, PATROL, STALK, HUNT, CHASE, ATTACK, FEED, RETURN }
const STATE_NAMES := ["rest", "patrol", "stalk", "hunt", "chase", "attack", "feed", "return"]

var state := REST
var timer := 3.0
var target: Animal = null          # the deer or a prey animal
var on_deer := false               # current target is the player
var aware := 0.0                   # 0..1 suspicion of the deer
var last_seen := Vector2.ZERO
var unseen := 0.0
var blocked := 0.0
var chase_time := 0.0
var tired := 0.0
var hunger := 30.0
var goal := Vector2.ZERO
var hit_done := false
var attack_len := 1.0
var has_bite_clip := false
var pack: Array = []
var pack_i := 0
var style := ""
var night_only := false
var leaving := false
var voice := 0.0
var rng := RandomNumberGenerator.new()

func start(h: Vector2) -> void:
	home = h
	style = cfg.style
	rng.randomize()
	place(h.x, h.y)
	yaw = rng.randf() * TAU; rotation.y = yaw
	timer = rng.randf_range(1.0, 8.0)
	hunger = rng.randf_range(25.0, 90.0)
	# the bite lands at attack_len * 0.4 / 1.25: for the pounce pose that is the moment the animal comes down
	has_bite_clip = anim != null and anim.has_animation("attack")
	attack_len = anim.get_animation("attack").length if has_bite_clip else 1.15
	if style == "water": leap = 0.3
	set_state(REST)

func set_state(s: int) -> void:
	state = s
	match s:
		REST: timer = rng.randf_range(5.0, 12.0)
		PATROL:
			goal = _patrol_point()
			timer = 30.0
		ATTACK:
			timer = 0.0
			hit_done = false
			cur_anim = ""
			play("attack", 1.25)
		FEED: timer = 14.0
		CHASE:
			chase_time = 0.0
			unseen = 0.0
			blocked = 0.0

func _patrol_point() -> Vector2:
	if style == "water":
		for i in 8:
			var p := home + Vector2(rng.randf_range(-7, 7), rng.randf_range(-7, 7))
			if can_enter(p.x, p.y): return p
		return home
	return World.dry_near(rng, home, 6.0, 42.0)

func can_enter(x: float, z: float) -> bool:
	if not World.playable(x, z): return false
	if World.thicket_at(x, z, 1.5) >= 0: return false
	var h := World.height(x, z)
	if style == "water": return h < 1.0
	return h > -0.45

## deer sensing: sight (cone, shorter when the deer sneaks, at night or in rain) and hearing
## the player is out of this hunter's sight: in a safe thicket, or swimming where a land hunter cannot follow
func cant_see(deer: Animal) -> bool:
	if deer.hide_kind == 2: return true
	return deer.in_water and style != "water"

func senses_deer() -> bool:
	var deer: Player = fauna.deer
	if deer == null or not deer.alive or cant_see(deer): return false
	var d := dist_to(deer.position)
	if style == "water":
		return d < cfg.sight and World.height(deer.position.x, deer.position.z) < 0.7
	var vis: float = cfg.sight * fauna.sight_mult(species)
	if deer.sneaking: vis *= 0.5
	if d < vis:
		var to := Vector2(deer.position.x - position.x, deer.position.z - position.z) / maxf(d, 0.01)
		if forward().dot(to) > -0.25 or d < vis * 0.4: return true
	return d < deer.noise * cfg.hear

func threat() -> int:
	if on_deer and (state == CHASE or state == ATTACK): return 2
	if state == STALK: return 1
	if state == HUNT and on_deer and aware > 0.3: return 1
	return 0

func alert(deer_pos: Vector2) -> void:
	if state == CHASE or state == ATTACK or tired > 0.0 or not alive: return
	last_seen = deer_pos
	engage()

func engage() -> void:
	target = fauna.deer
	on_deer = true
	aware = 1.0
	set_state(CHASE)
	if voice <= 0.0:
		voice = 6.0
		fauna.animal_sound(self, cfg.sound, cfg.pitch, 1.0)
	for p in pack:
		if p != self and is_instance_valid(p) and p.dist_to(position) < 90.0: p.alert(last_seen)

func give_up(rest_time: float) -> void:
	var was_deer := on_deer
	target = null
	on_deer = false
	aware = 0.0
	tired = rest_time
	set_state(RETURN)
	if was_deer: fauna.hunter_gave_up(self)

func tick(delta: float) -> void:
	voice -= delta
	tired = maxf(0.0, tired - delta)
	hunger -= delta
	var deer: Player = fauna.deer
	var sensed := false
	if state != ATTACK and state != CHASE and tired <= 0.0 and not leaving:
		sensed = senses_deer()
		if sensed:
			var d := dist_to(deer.position)
			var gain := 0.55 + 1.6 * clampf(1.0 - d / float(cfg.sight), 0.0, 1.0)
			if state == FEED: gain *= 0.3
			aware = minf(1.0, aware + gain * delta)
			last_seen = deer.pos2()
			unseen = 0.0
		else:
			unseen += delta
			if unseen > cfg.memory: aware = maxf(0.0, aware - delta * 0.25)
	match state:
		REST:
			speed = 0.0
			play("idle2" if pack_i % 2 == 1 else "idle")
			timer -= delta
			if aware > 0.3: _begin_stalk()
			elif timer <= 0.0:
				if leaving: set_state(RETURN)
				else: set_state(PATROL)
		PATROL:
			var left := _go(goal, cfg.walk, delta)
			timer -= delta
			if aware > 0.3: _begin_stalk()
			elif hunger <= 0.0 and _find_prey(): pass
			elif left < 1.0 or timer <= 0.0 or speed == 0.0: set_state(REST)
		STALK: _stalk(delta, sensed)
		HUNT:
			var left2 := _go(goal, cfg.walk * 2.4, delta)
			timer -= delta
			if aware > 0.3 and sensed: _begin_stalk()
			elif left2 < 3.0 or timer <= 0.0 or speed == 0.0:
				on_deer = false
				timer = 4.0
				state = REST
		CHASE: _chase(delta)
		ATTACK: _attack(delta)
		FEED:
			speed = 0.0
			play("eat")
			timer -= delta
			if aware >= 1.0 and deer.alive: engage()
			elif timer <= 0.0:
				hunger = rng.randf_range(80.0, 160.0)
				set_state(RETURN)
		RETURN:
			var left3 := _go(home, cfg.walk * 1.5, delta)
			if aware >= 0.6 and tired <= 0.0: _begin_stalk()
			elif left3 < 2.0 or speed == 0.0: set_state(REST)

func _begin_stalk() -> void:
	target = fauna.deer
	on_deer = true
	state = STALK
	timer = 0.0

func _stalk(delta: float, sensed: bool) -> void:
	var deer: Player = fauna.deer
	var d := dist_to(deer.position)
	if not deer.alive or aware <= 0.05 or (cant_see(deer) and unseen > 2.0):
		on_deer = false
		target = null
		aware = 0.0
		set_state(PATROL)
		return
	var charge: float = cfg.charge
	match style:
		"ambush":       # creep closer, then a short explosive charge
			if d > charge: _go(last_seen, cfg.walk * 0.9, delta)
			else: _hold(deer, delta)
			if sensed and ((d <= charge and aware >= 0.75) or d < charge * 0.6): engage()
		"stalk":        # stay silent until very close, then pounce
			if d > charge: _go(last_seen, cfg.walk * (1.5 if deer.speed > 1.0 else 1.1), delta)
			else: _hold(deer, delta)
			if sensed and d <= charge: engage()
		"sprint":
			if d > charge: _go(last_seen, cfg.walk * 1.6, delta)
			else: _hold(deer, delta)
			if sensed and aware >= 0.8 and d <= charge: engage()
		"water":
			_hold(deer, delta)
			if sensed and d <= charge: engage()
		_:              # packs: commit as soon as they are sure
			if d > charge: _go(last_seen, cfg.walk * 1.8, delta)
			else: _hold(deer, delta)
			if sensed and aware >= 0.9: engage()

func _hold(deer: Animal, delta: float) -> void:
	speed = 0.0
	face(deer.pos2() - pos2(), delta, 5.0)
	play("idle")

func _chase(delta: float) -> void:
	if target == null or not is_instance_valid(target) or not target.alive:
		give_up(2.0); return
	chase_time += delta
	var tp := target.pos2()
	var d := pos2().distance_to(tp)
	if on_deer:
		var deer := target
		if cant_see(deer):
			# it hid: the hunter searches for a moment, then leaves
			unseen += delta
			if unseen > (3.0 if deer.in_water else 1.5):
				give_up(8.0); return
			# slows to a walk and noses around where it last saw you
			if pos2().distance_to(last_seen) > 2.5: _go(last_seen, float(cfg.walk) * 1.6, delta)
			else: _hold(deer, delta)
			return
		elif d > float(cfg.sight) * 1.6:
			unseen += delta
			if unseen > cfg.memory:
				# lost it: go and search the last place it was seen
				state = HUNT; goal = last_seen; timer = 20.0; aware = 0.4
				fauna.hunter_gave_up(self)
				return
		else:
			unseen = 0.0
			last_seen = tp
		if style == "water" and pos2().distance_to(home) > 16.0:
			give_up(5.0); return
	elif chase_time > 9.0 or d > 60.0:
		hunger = 30.0
		give_up(3.0); return
	var spd: float = cfg.run
	# a hunter no longer gives up while it can see its prey, but it tires: after its best
	# effort (cfg.chase seconds) it slows down, which is the chance to get out of sight
	if on_deer and chase_time > float(cfg.chase): spd *= lerpf(1.0, 0.8, clampf((chase_time - float(cfg.chase)) / 6.0, 0.0, 1.0))
	if style == "stalk" and chase_time < 1.6: spd *= 1.3          # the pounce
	if style == "pack_circle" and on_deer and pack.size() > 1:
		# circle the deer; one pack member at a time darts in
		var turn := int(chase_time / 3.2) % pack.size()
		if turn != pack_i and d < 22.0:
			var ang := chase_time * 0.5 + pack_i * TAU / pack.size()
			var ring := tp + Vector2(cos(ang), sin(ang)) * 8.5
			_go(ring, spd, delta)
			return
	if d < float(cfg.reach) + target.body * 0.5:
		set_state(ATTACK); return
	var before := pos2()
	_go(tp, spd, delta)
	if speed == 0.0 and before.distance_to(pos2()) < 0.01:
		# blocked by something it cannot cross: pace, and leave if that lasts
		blocked += delta
		if blocked > 5.0:
			give_up(6.0); return
		face(tp - pos2(), delta, 6.0)
		play("idle")

func _attack(delta: float) -> void:
	speed = 0.0
	timer += delta
	var valid := target != null and is_instance_valid(target)
	# jaws meet the target: this animal's front end against the target's body
	var contact := body * 1.8 + (target.body * 1.2 if valid else 0.0)
	if valid:
		var tp := target.pos2()
		# the lunge: keep closing in until the bite lands, instead of snapping at the air from a distance
		if not hit_done and target.alive and pos2().distance_to(tp) > contact:
			var to := tp - pos2()
			var d0 := to.length()
			var stepd := minf(d0 - contact, float(cfg.run) * 1.15 * delta)
			var np := pos2() + to / d0 * stepd
			if can_enter(np.x, np.y): place(np.x, np.y)
		face(tp - pos2(), delta, 14.0)
	if not has_bite_clip and timer > 0.9 and cur_anim == "attack": play("idle")
	if not hit_done and timer >= attack_len * 0.4 / 1.25:
		hit_done = true
		if valid and target.alive and dist_to(target.position) < contact + 0.9:
			if on_deer:
				if target.hide_kind != 2: fauna.hit_deer(self, cfg.dmg)
			else:
				(target as Prey).kill()
				fauna.animal_sound(self, "thud", 1.0, 0.7)
	if timer >= attack_len / 1.25 + float(cfg.cool) * 0.5:
		if not valid: give_up(2.0)
		elif not target.alive:
			goal = target.pos2()
			on_deer = false
			set_state(FEED)
		elif on_deer:
			var keep := chase_time
			set_state(CHASE)
			chase_time = keep
		else: give_up(2.0)

func _find_prey() -> bool:
	hunger = 20.0
	if style == "water" or leaving: return false
	var best: Animal = null
	var bd: float = float(cfg.sight)
	for p in fauna.prey:
		if p.alive and not p.giant:
			var d: float = p.dist_to(position)
			if d < bd:
				bd = d; best = p
	if best == null: return false
	target = best
	on_deer = false
	set_state(CHASE)
	return true

## moves toward a point, sliding around water and thickets; returns distance left
func _go(to: Vector2, spd: float, delta: float) -> float:
	var off := to - pos2()
	var d := off.length()
	if d < 0.3:
		speed = 0.0
		locomotion(0.0)
		return d
	var dir := off / d
	var stepd := minf(d, spd * delta)
	var moved := false
	for a in [0.0, 0.7, -0.7, 1.4, -1.4]:
		var dd := dir.rotated(a)
		var nx := position.x + dd.x * stepd
		var nz := position.z + dd.y * stepd
		if can_enter(nx, nz):
			face(dd, delta, 7.0)
			place(nx, nz)
			moved = true
			break
	speed = spd if moved else 0.0
	locomotion(speed)
	return d - stepd
