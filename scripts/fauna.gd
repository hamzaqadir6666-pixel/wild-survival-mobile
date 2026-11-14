class_name Fauna
extends Node3D
## Owns every animal except the deer: spawning, cheap distance-tiered updates,
## threat level, roaming hunters, the night hyena pack and the birds in the sky.

signal deer_hit(pred: Predator, dmg: float)
signal escaped
signal species_seen(sp: String)
signal night_pack_came

var deer: Animal
var sky: SkyRig
var predators: Array = []
var prey: Array = []
var hawks: Array = []
var crows: Array = []
var threat_level := 0
var nearest_hunter: Predator = null
var nearest_hunter_dist := 1e9
var roam_interval := 50.0
var roam_timer := 30.0
var call_timer := 9.0
var frame := 0
var updates_last := 0
var rng := RandomNumberGenerator.new()
var _prey_queue: Array = []
var _hawk_center := Vector2(180, 180)
var _crow_pos := Vector2.ZERO
var _crow_dir := Vector2.RIGHT
var _crow_wait := 12.0
var _hunted_time := 0.0
var _clearings: Array = []

func setup(p_deer: Animal, p_sky: SkyRig) -> void:
	deer = p_deer
	sky = p_sky
	rng.randomize()
	_clearings = World.info.clearings
	var herds: Array = World.info.herds
	for i in herds.size():
		var sp: String = D.PREY_ORDER[i % D.PREY_ORDER.size()]
		for k in int(D.SPECIES[sp].herd): _prey_queue.append([sp, Vector2(herds[i][0], herds[i][1])])
	sky.night_started.connect(_on_night)
	sky.day_started.connect(_on_day)

## creates a few prey animals per call so loading never blocks; true when finished
func build_some(budget_ms: int) -> bool:
	var t0 := Time.get_ticks_msec()
	while not _prey_queue.is_empty():
		var e: Array = _prey_queue.pop_back()
		var a := Prey.new()
		a.fauna = self
		add_child(a)
		a.setup(e[0])
		a.start(e[1])
		prey.append(a)
		if Time.get_ticks_msec() - t0 >= budget_ms: return false
	if hawks.is_empty(): _make_sky_birds()
	return true

func _make_sky_birds() -> void:
	for i in 2:
		var h := Animal.make_bird("hawk"); add_child(h); hawks.append(h)
	for i in 5:
		var c := Animal.make_bird("crow"); add_child(c); crows.append(c)
		c.visible = false

func clear_predators() -> void:
	for p in predators: p.queue_free()
	predators.clear()
	threat_level = 0
	nearest_hunter = null

func spawn_level(level: Dictionary, start: Vector2) -> void:
	clear_predators()
	roam_interval = level.roam
	roam_timer = roam_interval
	_hunted_time = 0.0
	var dens: Array = World.info.dens.duplicate()
	var crocs: Array = World.info.crocs.duplicate()
	var di := 0
	var ci := 0
	for sp in level.hunters:
		var n := int(level.hunters[sp])
		var pack_size := int(D.SPECIES[sp].get("pack", 1))
		var made := 0
		while made < n:
			var group: Array = []
			var spot := Vector2.ZERO
			if sp == "crocodile":
				spot = Vector2(crocs[ci % crocs.size()][0], crocs[ci % crocs.size()][1]); ci += 1
			else:
				for tries in dens.size():
					spot = Vector2(dens[di % dens.size()][0], dens[di % dens.size()][1]); di += 1
					if spot.distance_to(start) > 85.0: break
			for k in mini(pack_size, n - made):
				var off := Vector2(k * 2.5, (k % 2) * 2.0)
				var pr := _make_predator(sp, spot + off)
				pr.pack_i = k
				group.append(pr)
				made += 1
			for g in group: g.pack = group
	for a in prey:
		if not a.alive: a.respawn()

func _make_predator(sp: String, at: Vector2) -> Predator:
	var pr := Predator.new()
	pr.fauna = self
	add_child(pr)
	pr.setup(sp)
	if not pr.can_enter(at.x, at.y):
		at = World.dry_near(rng, at, 1.0, 8.0) if sp != "crocodile" else at
	pr.start(at)
	predators.append(pr)
	return pr

func apply_quality() -> void:
	for a in predators: a.apply_quality()
	for a in prey: a.apply_quality()

func sight_mult(sp: String) -> float:
	var m := 1.0
	if sky.is_night and sp != "hyena" and sp != "wolf": m *= 0.7
	if sky.rain > 0.4: m *= 0.85
	return m

func far_from_deer(p: Vector3, d: float) -> bool:
	return deer.dist_to(p) > d

func animal_sound(a: Node3D, sound: String, pitch: float, vol: float) -> void:
	if sound == "": return
	Sfx.play(sound, vol, pitch, deer.dist_to(a.position), 95.0)

func hit_deer(pred: Predator, dmg: float) -> void:
	deer_hit.emit(pred, dmg)

func hunter_gave_up(_pred: Predator) -> void:
	pass

## x, y = position of the danger, z > 0 when there is one
func threat_near(a: Prey) -> Vector3:
	var d := a.dist_to(deer.position)
	if deer.alive and (d < 7.0 or (d < 15.0 and deer.speed > 5.0)):
		return Vector3(deer.position.x, deer.position.z, 1.0)
	for p in predators:
		var pd: float = p.dist_to(a.position)
		if pd < 10.0 or (pd < 32.0 and p.target == a):
			return Vector3(p.position.x, p.position.z, 1.0)
	return Vector3.ZERO

func update(delta: float, cam: Camera3D) -> void:
	frame += 1
	var near := float(Cfg.v("anim_near"))
	var mid := minf(float(Cfg.v("view")) * 0.6, 125.0)        # beyond this animals are not drawn at all
	var dp := deer.position
	var level := 0
	nearest_hunter = null
	nearest_hunter_dist = 1e9
	updates_last = 0
	var i := 0
	for p in predators:
		i += 1
		p.acc_dt += delta
		var d: float = p.dist_to(dp)
		if d < nearest_hunter_dist:
			nearest_hunter_dist = d; nearest_hunter = p
		var t := Animal.TIER_NEAR if d < near else (Animal.TIER_MID if d < mid else Animal.TIER_FAR)
		p.set_tier(t)
		if t == Animal.TIER_NEAR or (t == Animal.TIER_MID and (frame + i) % 4 == 0) or (frame + i) % 30 == 0:
			p.tick(minf(p.acc_dt, 1.5))
			p.acc_dt = 0.0
			updates_last += 1
		level = maxi(level, p.threat())
		if d < 40.0: _see(p.species, p.position, cam)
	for a in prey:
		i += 1
		a.acc_dt += delta
		var d2: float = a.dist_to(dp)
		var t2 := Animal.TIER_NEAR if d2 < near else (Animal.TIER_MID if d2 < mid else Animal.TIER_FAR)
		a.set_tier(t2)
		if t2 == Animal.TIER_NEAR or (t2 == Animal.TIER_MID and (frame + i) % 4 == 0) or (frame + i) % 30 == 0:
			a.tick(minf(a.acc_dt, 1.5))
			a.acc_dt = 0.0
			updates_last += 1
		if d2 < 40.0: _see(a.species, a.position, cam)
	if level == 2: _hunted_time += delta
	if threat_level == 2 and level < 2 and deer.alive and _hunted_time > 1.5:
		escaped.emit()
	if level < 2: _hunted_time = 0.0
	threat_level = level
	_roam(delta)
	_calls(delta)
	_sky_birds(delta, cam)
	# night pack and other leavers disappear once out of sight
	for k in range(predators.size() - 1, -1, -1):
		var q: Predator = predators[k]
		if q.leaving and q.dist_to(dp) > 95.0:
			predators.remove_at(k)
			q.queue_free()

func _see(sp: String, at: Vector3, cam: Camera3D) -> void:
	if Save.d.seen.has(sp): return
	if cam and cam.is_position_behind(at): return
	Save.d.seen[sp] = true
	species_seen.emit(sp)

func seen_count() -> int:
	var n := 0
	for sp in D.WILDLIFE_ORDER:
		if Save.d.seen.has(sp): n += 1
	return n

## every so often one resting hunter wanders toward the deer
func _roam(delta: float) -> void:
	roam_timer -= delta
	if roam_timer > 0.0 or not deer.alive: return
	roam_timer = roam_interval * rng.randf_range(0.8, 1.2)
	var best: Predator = null
	var bd := 1e9
	for p in predators:
		if p.style == "water" or p.tired > 0.0 or p.leaving: continue
		if p.state != Predator.REST and p.state != Predator.PATROL: continue
		var d: float = p.dist_to(deer.position)
		if d > 45.0 and d < bd:
			bd = d; best = p
	if best == null: return
	send_toward_deer(best, bd)

func send_toward_deer(p: Predator, d: float) -> void:
	var dp := deer.pos2()
	var far := minf(float(Cfg.v("view")) * 0.75, 125.0)
	if d > far + 15.0:
		var at := World.dry_near(rng, dp, far - 10.0, far + 10.0)
		if at.distance_to(dp) > 60.0 and p.can_enter(at.x, at.y): p.place(at.x, at.y)
	p.goal = World.dry_near(rng, dp, 8.0, 28.0)
	p.timer = 70.0
	p.aware = 0.0
	p.on_deer = true
	p.state = Predator.HUNT
	for other in p.pack:
		if other != p and is_instance_valid(other) and (other.state == Predator.REST or other.state == Predator.PATROL):
			var op := World.dry_near(rng, p.pos2(), 2.0, 7.0)
			if other.dist_to(p.position) > 40.0 and other.can_enter(op.x, op.y): other.place(op.x, op.y)
			other.goal = World.dry_near(rng, dp, 8.0, 28.0)
			other.timer = 70.0; other.on_deer = true; other.state = Predator.HUNT

func _on_night() -> void:
	if not deer.alive or deer.get_parent() == null: return
	var dp := deer.pos2()
	var spot := World.dry_near(rng, dp, 75.0, 100.0)
	var group: Array = []
	for k in 3:
		var at := World.dry_near(rng, spot, 1.0, 6.0)
		var pr := _make_predator("hyena", at)
		pr.night_only = true
		pr.pack_i = k
		group.append(pr)
	for g in group:
		g.pack = group
		g.home = spot
		g.goal = World.dry_near(rng, dp, 6.0, 20.0)
		g.timer = 90.0; g.on_deer = true; g.state = Predator.HUNT
	animal_sound(group[0], "laugh", 1.25, 1.0)
	night_pack_came.emit()

func _on_day() -> void:
	for p in predators:
		if p.night_only:
			p.leaving = true
			if p.state != Predator.CHASE and p.state != Predator.ATTACK:
				p.home = World.dry_near(rng, p.pos2(), 110.0, 150.0)
				p.set_state(Predator.RETURN)

func _calls(delta: float) -> void:
	call_timer -= delta
	if call_timer > 0.0: return
	call_timer = rng.randf_range(7.0, 16.0)
	var pool: Array = prey if rng.randf() < 0.6 else predators
	if pool.is_empty(): return
	var a: Animal = pool[rng.randi() % pool.size()]
	var s: String = a.cfg.get("sound", "")
	if s != "" and a.alive and a.dist_to(deer.position) < 90.0:
		animal_sound(a, s, float(a.cfg.get("pitch", 1.0)) * rng.randf_range(0.94, 1.06), 0.45)

func _sky_birds(delta: float, cam: Camera3D) -> void:
	var t := Time.get_ticks_msec() * 0.001
	var dp := deer.pos2()
	# hawks circle over the clearing nearest to the deer
	if frame % 120 == 1:
		var bd := 1e9
		for c in _clearings:
			var cd := dp.distance_to(Vector2(c.x, c.z))
			if cd < bd:
				bd = cd; _hawk_center = Vector2(c.x, c.z)
	for i in hawks.size():
		var h: Node3D = hawks[i]
		var ang := t * 0.22 * (1.0 if i == 0 else -0.8) + i * 2.4
		var r := 24.0 + i * 9.0
		var x := _hawk_center.x + cos(ang) * r
		var z := _hawk_center.y + sin(ang) * r
		h.position = Vector3(x, maxf(World.height(_hawk_center.x, _hawk_center.y), 0.0) + 30.0 + i * 5.0, z)
		h.rotation.y = atan2(-sin(ang), cos(ang)) * (1.0 if i == 0 else -1.0) + (0.0 if i == 0 else PI)
		var vis := deer.dist_to(h.position) < float(Cfg.v("view"))
		h.visible = vis
		var ap: AnimationPlayer = h.get_node("Anim")
		ap.active = vis
		if vis:
			Animal.bird_fly(ap, 0.55)
			if deer.dist_to(h.position) < 120.0: _see("hawk", h.position, cam)
	# a crow flock crosses the sky near the deer now and then
	if _crow_wait > 0.0:
		_crow_wait -= delta
		if _crow_wait <= 0.0:
			var a := rng.randf() * TAU
			_crow_dir = Vector2(cos(a), sin(a))
			_crow_pos = dp - _crow_dir * 150.0 + _crow_dir.orthogonal() * rng.randf_range(-25.0, 25.0)
			for c in crows: c.visible = true
	else:
		_crow_pos += _crow_dir * 11.0 * delta
		var gone := _crow_pos.distance_to(dp) > 170.0
		for i in crows.size():
			var c: Node3D = crows[i]
			var side := _crow_dir.orthogonal() * (i - 2) * 3.5 - _crow_dir * absf(i - 2) * 3.0
			var p := _crow_pos + side
			c.position = Vector3(p.x, maxf(World.height(p.x, p.y), 0.0) + 21.0 + sin(t * 1.3 + i) * 1.2, p.y)
			c.rotation.y = atan2(_crow_dir.x, _crow_dir.y)
			var ap2: AnimationPlayer = c.get_node("Anim")
			ap2.active = not gone
			Animal.bird_fly(ap2, 1.25)
			if gone: c.visible = false
		var cd2 := _crow_pos.distance_to(dp)
		if cd2 < 100.0:
			_see("crow", crows[0].position, cam)
			if frame % 75 == 0: Sfx.play("crow", 0.6, rng.randf_range(0.9, 1.1), cd2, 110.0)
		if gone: _crow_wait = rng.randf_range(35.0, 70.0)
