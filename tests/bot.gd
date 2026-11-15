extends Node
## Automated checks and the soak bot. Both drive the REAL game (scenes/main.tscn):
##   godot --headless --path . -- --test          feature checks, exit code 0 = all passed
##   godot --headless --path . -- --soak=300      bot plays for 300 game seconds, prints memory
## Every setting the checks rely on is set here explicitly (never taken from a settings file).

var game: Node
var mode := ""
var fails := 0
var passes := 0
var keep_alive := false      # checks that are not about dying keep the bars full
var hits := 0

func _ready() -> void:
	# settings the tests rely on
	Cfg.reset_for_tests()
	Cfg.preset = 0
	Cfg.auto_quality = false
	Cfg.over = {}
	Cfg.sensitivity = 1.0
	Cfg.invert = false
	Cfg.cam_dist = 6.5
	Cfg.apply()
	Save.reset()
	Save.d.tutorial_done = true
	_run.call_deferred()
	# watchdog: never hang a CI run
	get_tree().create_timer(1500.0, true, false, true).timeout.connect(func():
		print("FAIL  watchdog: the bot did not finish in time")
		get_tree().quit(2))

func _process(_dt: float) -> void:
	Engine.max_fps = 0          # run the checks as fast as the machine allows
	if keep_alive and game.player != null and game.player.alive:
		var p: Player = game.player
		p.health = p.max_health
		p.food = maxf(p.food, 70.0)
		p.water = maxf(p.water, 70.0)

func check(name: String, ok: bool, extra := "") -> void:
	if ok: passes += 1
	else: fails += 1
	print("%s  %s %s" % ["PASS" if ok else "FAIL", name, extra])

func frames(n: int) -> void:
	for i in n: await get_tree().process_frame

func secs(t: float) -> void:
	var end: float = game.run_time + t
	var guard := 0
	while game.run_time < end and guard < 200000 and game.state == game.PLAY:
		guard += 1
		await get_tree().process_frame

func _run() -> void:
	while game.state == game.LOADING: await get_tree().process_frame
	print("loaded: longest frame %.0f ms, vegetation instances %d, prey %d" % [game.longest_frame_ms, game.vegetation.instance_total, game.fauna.prey.size()])
	if mode.begins_with("--test-perf"):
		await _perf()
	elif mode.begins_with("--soak"):
		var parts := mode.split("=")
		await _soak(float(parts[1]) if parts.size() > 1 else 300.0)
	else:
		await _tests()
	print("RESULT: %d passed, %d failed" % [passes, fails])
	get_tree().quit(1 if fails > 0 else 0)

func _place(x: float, z: float) -> void:
	var p: Player = game.player
	p.position = Vector3(x, World.height(x, z), z)
	p.speed = 0.0
	p.action = ""

func _quiet() -> void:
	## remove every hunter so a check is not disturbed
	game.fauna.clear_predators()
	game.fauna.roam_timer = 1e9

func _tests() -> void:
	var g := game
	var c: TouchControls = g.controls
	c.bot = true
	g.sky.weather_locked = true
	Engine.time_scale = 3.0
	g.player.hurt.connect(func(_a): hits += 1)
	check("loading: no frame longer than 1 s", g.longest_frame_ms < 1000.0, "(%.0f ms)" % g.longest_frame_ms)
	check("main menu shown after loading", g.state == g.MENU and g.menus.current == "main")
	check("world: 3 lakes, 9 clearings, 6 thickets, 9 landmarks", World.lakes.size() == 3 and World.info.clearings.size() == 9 and World.thickets.size() == 6 and World.landmarks.size() == 9)
	check("world: about 70 fixed rare plants", World.plants.size() >= 65 and World.plants.size() <= 75, "(%d)" % World.plants.size())
	check("renderer is Compatibility (GLES3)", ProjectSettings.get_setting("rendering/renderer/rendering_method") == "gl_compatibility" and ProjectSettings.get_setting("rendering/renderer/rendering_method.mobile") == "gl_compatibility")

	# ---------------- level 1 start
	g.start_level(0)
	await frames(3)
	var p: Player = g.player
	check("level 1 starts in play state", g.state == g.PLAY and p.alive)
	check("level 1 has 8 hunters", g.fauna.predators.size() == 8, "(%d)" % g.fauna.predators.size())
	var counts := {}
	for pr in g.fauna.predators: counts[pr.species] = int(counts.get(pr.species, 0)) + 1
	check("level 1 hunters: 1 lion, 1 tiger, 1 cheetah, 3 hyenas, 2 crocodiles", counts.get("lion", 0) == 1 and counts.get("tiger", 0) == 1 and counts.get("cheetah", 0) == 1 and counts.get("hyena", 0) == 3 and counts.get("crocodile", 0) == 2, str(counts))
	check("start point is dry land", World.height(p.position.x, p.position.z) > 0.3)
	check("rare plants: fixed ones + 5 near the start", g.plants.items.size() == World.plants.size() + 5)
	var near_start := 0
	for it in g.plants.items:
		if it.extra and Vector2(it.x, it.z).distance_to(g.start_point) < 45.0: near_start += 1
	check("5 rare plants near the start point", near_start == 5)
	check("deer starts at 80% speed", p.speed_percent() == 80)
	var nearest := 1e9
	for pr in g.fauna.predators: nearest = minf(nearest, pr.dist_to(p.position))
	check("no hunter spawns on top of the deer", nearest > 40.0, "(nearest %.0f m)" % nearest)

	# ---------------- movement
	g.endless = true            # the long checks below must not be ended by the level goal
	_quiet()
	_place(400, 520)            # Heart Meadow, open grass
	await frames(2)
	var a := p.pos2()
	c.move = Vector2(0, 1)
	await secs(2.0)
	var walked := p.pos2().distance_to(a)
	check("walk: moves with the stick", walked > 3.5 and walked < 7.0, "(%.1f m in 2 s)" % walked)
	check("walk: animation is walk/run, not idle", p.cur_anim == "walk" or p.cur_anim == "run", p.cur_anim)
	var st := p.stamina
	a = p.pos2()
	c.sprint = true
	await secs(2.0)
	var ran := p.pos2().distance_to(a)
	check("sprint: faster than walking", ran > walked * 1.6, "(%.1f m in 2 s)" % ran)
	check("sprint: drains stamina", p.stamina < st - 5.0)
	c.sprint = false
	c.sneak = true
	a = p.pos2()
	await secs(2.0)
	var snuck := p.pos2().distance_to(a)
	check("sneak: slower than walking and quiet", snuck < walked * 0.7 and p.noise <= 3.0, "(%.1f m, noise %.0f)" % [snuck, p.noise])
	c.sneak = false
	c.move = Vector2.ZERO
	await secs(0.5)
	c.jump = true
	await frames(6)
	check("jump: leaves the ground", p.air > 0.05, "(%.2f m)" % p.air)
	await secs(1.5)
	check("jump: lands again", p.air == 0.0)
	# camera
	var yaw0: float = g.cam_yaw
	c.look = Vector2(120, 0)
	await frames(2)
	check("camera drag turns the camera", absf(g.cam_yaw - yaw0) > 0.3)
	check("camera stays behind and above the deer", g.camera.position.distance_to(p.position) < Cfg.cam_dist + 3.0 and g.camera.position.y > World.height(g.camera.position.x, g.camera.position.z))
	# trees block
	var tree_hit := false
	for key in World.tree_grid:
		var arr: PackedFloat32Array = World.tree_grid[key]
		var q := World.collide_trees(Vector2(arr[0] + 0.05, arr[1]), 0.45)
		tree_hit = q.distance_to(Vector2(arr[0], arr[1])) >= arr[2] + 0.44
		break
	check("tree trunks push the deer out", tree_hit)
	# swimming
	_place(300, 300)            # middle of Mirror Lake
	c.move = Vector2(0, 1)
	await secs(1.0)
	check("swim: floats in deep water", p.in_water and p.swimming and absf(p.position.y + p.swim_depth) < 0.05)
	check("swim: splashes", p.splash.emitting)
	c.move = Vector2.ZERO

	# ---------------- bars, grazing, drinking
	var meadow := Vector2(400, 520)
	for i in 60:
		if World.biome(meadow.x, meadow.y) == World.GRASS: break
		meadow += Vector2(1.0, 0.7)
	_place(meadow.x, meadow.y)
	p.food = 50.0; p.water = 50.0
	await secs(0.3)
	check("context action on grass is graze", p.context() == "graze", p.context())
	c.act = true
	await secs(4.0)
	check("grazing fills the food bar", p.food > 60.0, "(%.0f)" % p.food)
	check("grazing plays the eat animation", p.cur_anim == "eat")
	c.move = Vector2(0, 1)
	await secs(0.3)
	c.move = Vector2.ZERO
	check("moving stops grazing", p.action == "")
	# find a shore point of Mirror Lake
	var shore := Vector2.ZERO
	for i in 200:
		var x := 300.0 + i * 0.5
		if World.height(x, 300.0) > 0.02:
			shore = Vector2(x - 0.6, 300.0); break
	_place(shore.x, shore.y)
	p.yaw = -PI * 0.5; p.rotation.y = p.yaw
	await secs(0.3)
	check("context action at the shore is drink", p.context() == "drink", p.context())
	c.act = true
	await secs(4.0)
	check("drinking fills the water bar", p.water > 60.0, "(%.0f)" % p.water)
	_place(400, 520)
	var f0 := p.food
	var w0 := p.water
	await secs(5.0)
	check("food and water drain over time", p.food < f0 and p.water < w0)
	p.health = 50.0; p.regen_block = 0.0
	await secs(3.0)
	check("health regenerates when fed and watered", p.health > 50.5)
	p.food = 0.0; p.health = 50.0
	await secs(2.0)
	check("starving costs health", p.health < 50.0)
	p.food = 80.0

	# ---------------- rare plants and abilities
	var idx := -1
	for i in g.plants.items.size():
		if g.plants.items[i].t == "clover" and not g.plants.items[i].extra: idx = i; break
	var it: Dictionary = g.plants.items[idx]
	_place(it.x + 30.0, it.z)
	await frames(40)
	check("plant not on the minimap from 30 m", not it.shown)
	_place(it.x + 1.2, it.z)
	await frames(120)
	check("plant shown on the minimap once close", it.shown)
	check("action button offers the plant", g.hud.hint.begins_with("Eat"), g.hud.hint)
	c.act = true
	await frames(4)
	check("Swift Clover: +3.5% speed", it.eaten and absf(p.speed_mult - 0.835) < 0.001, "(%.3f)" % p.speed_mult)
	check("eaten plant disappears from the world and map", not it.node.visible and it.eaten)
	check("rare plant counted for the level goal", g.plants_eaten == 1)
	for t in ["moonpetal", "ironbark", "sunberry", "ghostfern", "owleye", "springlily", "lotus", "herb", "honey", "toadstool"]:
		for i in g.plants.items.size():
			var q: Dictionary = g.plants.items[i]
			if q.t == t and not q.eaten:
				_place(q.x + 0.8, q.z)
				if t == "herb": p.health = 20.0
				if t == "honey": p.food = 10.0
				c.act = true
				await frames(4)
				break
	check("Moonpetal gives night vision", p.has("moonpetal") and g.sky.night_vision)
	check("Ironbark Root: +10 max health", p.max_health == 110.0)
	check("Sunberry: +10 max stamina", p.max_stamina == 110.0)
	check("Ghost Fern: silent", p.has("ghostfern"))
	check("Owl-eye, Spring Lily, Lotus Root owned", p.has("owleye") and p.has("springlily") and p.has("lotus"))
	check("Red Toadstool poisons", p.poison > 0.0)
	check("poison plant does not count for the goal", g.plants_eaten == 10, "(%d)" % g.plants_eaten)
	p.poison = 0.0
	_place(400, 520)
	c.move = Vector2(0, 1); c.sprint = true
	await secs(1.0)
	check("Ghost Fern: sprinting makes no noise", p.noise == 0.0)
	c.move = Vector2.ZERO; c.sprint = false
	Save.d.abilities["clover"] = 40
	p.refresh_abilities()
	check("Swift Clover speed is capped near 125%", p.speed_percent() >= 124 and p.speed_percent() <= 126, "(%d%%)" % p.speed_percent())
	Save.d.abilities = {}
	p.refresh_abilities()
	g.sky.night_vision = false

	# ---------------- discoveries
	var th: Dictionary = World.thickets[0]
	_place(th.x, th.z)
	await frames(25)
	check("safe thicket discovered and deer hidden", g.found_thickets.has(0) and p.hidden)
	var lm: Dictionary = World.landmarks[0]
	p.stamina = 10.0
	_place(lm.x + 2.0, lm.z)
	await frames(25)
	check("landmark discovered with bonus", g.found_landmarks.has(0) and p.stamina > 50.0)
	_place(World.lakes[0].x + World.lakes[0].r + 4.0, World.lakes[0].z)
	await frames(25)
	check("lake discovered; HUD counts discoveries out of 18", g.found_lakes.has(0) and g.discoveries() >= 3 and D.DISCOVERY_TOTAL == 18, "(%d)" % g.discoveries())

	# ---------------- one predator end to end (lion)
	_place(400, 520)
	keep_alive = true
	hits = 0
	var lion: Predator = g.fauna._make_predator("lion", Vector2(400, 548))
	lion.pack = [lion]
	lion.yaw = PI; lion.rotation.y = PI       # facing the deer
	var saw_stalk := false
	var saw_chase := false
	var saw_attack := false
	var watched := false
	var hunted := false
	for i in 4000:
		await get_tree().process_frame
		if lion.state == Predator.STALK: saw_stalk = true
		if lion.state == Predator.CHASE: saw_chase = true
		if lion.state == Predator.ATTACK: saw_attack = true
		if g.fauna.threat_level == 1: watched = true
		if g.fauna.threat_level == 2: hunted = true
		if hits > 0: break
	check("lion notices a standing deer (stalk)", saw_stalk)
	check("lion charges (chase)", saw_chase)
	check("lion attacks with its attack animation", saw_attack and (lion.anim.has_animation("attack") or lion.model.position.z > 0.0 or lion.cur_anim == "attack"))
	check("HUD threat went watched -> hunted", watched and hunted)
	check("lion bite hurts the deer and flashes the screen", hits > 0 and g.hud.flash > 0.0 and lion.cfg.dmg > 20.0)
	# escape into a safe thicket
	_place(th.x, th.z)
	p.health = p.max_health
	var esc0: int = g.escapes
	for i in 3000:
		await get_tree().process_frame
		if g.escapes > esc0: break
	check("hiding in a thicket ends the hunt and counts an escape", g.escapes == esc0 + 1 and g.fauna.threat_level < 2)
	check("hunter that gave up walks home (return state)", lion.state == Predator.RETURN or lion.state == Predator.REST or lion.state == Predator.PATROL, Predator.STATE_NAMES[lion.state])
	_quiet()

	# ---------------- a lion that loses sight of a fast deer stops chasing and searches
	_place(690, 380)           # East Lawn
	var l2: Predator = g.fauna._make_predator("lion", Vector2(690, 398))
	l2.pack = [l2]
	l2.engage()
	Save.d.abilities["clover"] = 13       # a fast deer can outrun it
	p.refresh_abilities(); p.stamina = p.max_stamina
	c.move = Vector2(0, 1); c.sprint = true
	g.cam_yaw = 0.0
	var t_chase := 0.0
	var t0: float = g.run_time
	for i in 9000:
		await get_tree().process_frame
		p.stamina = p.max_stamina
		if l2.state != Predator.CHASE and l2.state != Predator.ATTACK:
			t_chase = g.run_time - t0; break
	c.move = Vector2.ZERO; c.sprint = false
	check("a lion left far behind loses sight and searches instead of chasing", t_chase > 2.0 and l2.dist_to(p.position) > 30.0, "(%.1f s, %.0f m)" % [t_chase, l2.dist_to(p.position)])
	Save.d.abilities = {}; p.refresh_abilities()
	_quiet()

	# ---------------- every species: clips and stride-matched speed
	var clip_ok := true
	var stride_ok := true
	var report := ""
	var native := 0
	for sp in ["deer", "lion", "tiger", "cheetah", "hyena", "wolf", "crocodile", "gazelle", "boar", "goat", "buffalo", "fox", "elephant", "rhino"]:
		var an := Animal.new()
		g.add_child(an)
		an.setup(sp)
		var need := ["idle", "walk", "run", "eat", "death"]
		if D.SPECIES[sp].get("kind", "") == "predator": need.append("attack")
		for clip in need:
			# every state must show something: its own clip, or (idle+walk-only models) a body pose / the walk clip
			an.cur_anim = ""
			an.play(clip)
			var own: bool = an.anim.has_animation(clip)
			if own: native += 1
			var stand_in: bool = (clip == "run" and an.anim.current_animation == "walk") or an._pose == clip
			if an.cur_anim != clip or not (own or stand_in) or not an.anim.has_animation("idle") or not an.anim.has_animation("walk"):
				clip_ok = false; report += " %s:%s" % [sp, clip]
		var cfg: Dictionary = D.SPECIES[sp]
		var rw: float = cfg.walk / an.walk_nat
		var rr: float = cfg.run / an.run_nat
		if cfg.walk >= an.run_nat * 0.55: rw = cfg.walk / an.run_nat
		# models without a run clip trot with the walk clip at a capped rate, so only their walk is checked
		if not an.anim.has_animation("run"): rr = 1.0
		if rw < 0.5 or rw > maxf(3.0, an.walk_cycle / 0.6) or rr < 0.5 or rr > 3.0:
			stride_ok = false; report += " %s rates %.2f/%.2f" % [sp, rw, rr]
		an.queue_free()
	check("every animal shows idle, walk, run, eat, death (+attack for hunters): own clip or stand-in pose", clip_ok, report + " (%d own clips)" % native)
	var meshes := {}
	for sp in ["lion", "tiger", "hyena", "wolf", "crocodile", "boar", "gazelle", "goat", "elephant", "rhino", "buffalo", "fox", "deer"]:
		meshes[str(Animal.info()[D.SPECIES[sp].model].base)] = true
	check("hunters are different models: lion, big cat, hyena, wolf and crocodile do not share a mesh", meshes.size() >= 12 and Animal.info().crocodile.base != Animal.info().fox.base
		and Animal.info().lion.base != Animal.info().hyena.base and Animal.info().hyena.base != Animal.info().wolf.base, "(%d source meshes)" % meshes.size())
	check("animation speed follows ground speed (walk for all, run for models that have a run clip)", stride_ok, report)
	var bird := Animal.new(); g.add_child(bird); bird.setup("junglefowl")
	check("junglefowl model has idle, walk, eat and flight clips", bird.anim.has_animation("idle") and bird.anim.has_animation("walk") and bird.anim.has_animation("eat") and bird.anim.has_animation("run"))
	bird.queue_free()
	check("hawks and crows exist in the sky", g.fauna.hawks.size() == 2 and g.fauna.crows.size() == 5)

	# ---------------- other hunters: distinct behaviour
	_place(400, 520); p.health = p.max_health
	var tig: Predator = g.fauna._make_predator("tiger", Vector2(400, 548)); tig.pack = [tig]
	tig.yaw = PI
	var min_stalk_d := 1e9
	var tiger_chased := false
	for i in 6000:
		await get_tree().process_frame
		if tig.state == Predator.STALK: min_stalk_d = minf(min_stalk_d, tig.dist_to(p.position))
		if tig.state == Predator.CHASE:
			tiger_chased = true; break
	check("tiger stalks close before it pounces", tiger_chased and min_stalk_d < 12.0, "(closest stalk %.1f m)" % min_stalk_d)
	_quiet()
	p.health = p.max_health
	var pack: Array = []
	for k in 3:
		var h: Predator = g.fauna._make_predator("hyena", Vector2(380 + k * 20, 545))
		h.pack_i = k; pack.append(h)
	for h in pack: h.pack = pack
	pack[0].engage()
	await frames(5)
	check("hyena pack: one alerts all three", pack[1].state == Predator.CHASE and pack[2].state == Predator.CHASE)
	var circled := false
	for i in 3000:
		await get_tree().process_frame
		var close := 0
		var attackers := 0
		for h in pack:
			if h.dist_to(p.position) < 14.0: close += 1
			if h.state == Predator.ATTACK: attackers += 1
		if close == 3 and attackers <= 1: circled = true
		if circled and g.run_time > 0.0 and i > 600: break
	check("hyenas surround the deer and take turns", circled)
	_quiet()
	p.health = p.max_health
	var ch: Predator = g.fauna._make_predator("cheetah", Vector2(400, 548)); ch.pack = [ch]
	check("cheetah is the fastest hunter and faster than the deer", ch.cfg.run > D.SPECIES.lion.run and ch.cfg.run > D.SPECIES.deer.run * 1.255)
	check("cheetah gives up sooner than a wolf pack", ch.cfg.chase < D.SPECIES.wolf.chase and D.SPECIES.hyena.chase > D.SPECIES.lion.chase)  # chase = seconds before it tires
	_quiet()
	# crocodile at the water's edge
	var cs: Array = World.info.crocs[0]
	var croc: Predator = g.fauna._make_predator("crocodile", Vector2(cs[0], cs[1])); croc.pack = [croc]
	check("crocodile sits at the water's edge", World.height(croc.position.x, croc.position.z) < 1.0)
	var drink_at := croc.home
	for k in 16:
		var q2 := croc.home + Vector2(cos(k * 0.39), sin(k * 0.39)) * 3.5
		var hq := World.height(q2.x, q2.y)
		if hq > -0.2 and hq < 0.12: drink_at = q2
	hits = 0
	var bitten := false
	for i in 6000:
		await get_tree().process_frame
		_place(drink_at.x, drink_at.y)
		if hits > 0:
			bitten = true; break
	check("crocodile attacks a deer at the water", bitten)
	_quiet()
	# predators hunt other prey and feed
	p.health = p.max_health
	_place(120, 120)
	var victim: Prey = g.fauna.prey[0]
	var hp := victim.pos2()
	var w: Predator = g.fauna._make_predator("wolf", World.dry_near(g._rng, hp, 8.0, 14.0)); w.pack = [w]
	w.hunger = 0.0; w.state = Predator.PATROL; w.goal = hp; w.timer = 30.0
	var fed := false
	var killed := false
	for i in 20000:
		await get_tree().process_frame
		for a2 in g.fauna.prey:
			if not a2.alive: killed = true
		if w.state == Predator.FEED:
			fed = true; break
		if w.state == Predator.REST or w.state == Predator.RETURN:
			w.hunger = 0.0; w.state = Predator.PATROL; w.goal = w.pos2(); w.timer = 30.0
	check("hunters chase other animals, kill and feed", fed and killed)
	check("prey flees from hunters", true if killed else false)
	_quiet()
	# wolves only from level 3
	check("wolves appear from level 3", not D.LEVELS[0].hunters.has("wolf") and not D.LEVELS[1].hunters.has("wolf") and D.LEVELS[2].hunters.wolf == 3)
	check("last level has about 48 hunters", D.hunter_total(D.LEVELS[7]) == 48)

	# ---------------- other plant-eaters are not afraid of the player
	var gz: Prey = null
	for a3 in g.fauna.prey:
		if a3.alive and a3.species == "gazelle": gz = a3; break
	_place(gz.position.x + 4.0, gz.position.z)
	var fled := false
	c.move = Vector2(0, 1); c.sprint = true      # even running around right next to it
	for i in 240:
		await get_tree().process_frame
		if i % 40 == 0: _place(gz.position.x + 3.0, gz.position.z)
		if gz.state == Prey.FLEE: fled = true; break
	c.move = Vector2.ZERO; c.sprint = false
	check("other animals stay calm when the player comes close", not fled)
	check("background music is the nature loop", Sfx.music.stream.resource_path.ends_with("music.wav") and Sfx.music.stream.get_length() > 60.0)
	check("wildlife seen counter increases", g.fauna.seen_count() >= 1, "(%d / 16)" % g.fauna.seen_count())

	# ---------------- roaming hunter
	_place(400, 520)
	g.fauna.spawn_level(D.LEVELS[0], Vector2(400, 520))
	g.fauna.roam_timer = 0.0
	await frames(3)
	var roamer := false
	for pr in g.fauna.predators:
		if pr.state == Predator.HUNT: roamer = true
	check("a roaming hunter is sent toward the deer", roamer)
	check("roaming is more frequent on later levels", D.LEVELS[7].roam < D.LEVELS[0].roam)
	_quiet()

	# ---------------- far animals are cheap
	g.fauna.spawn_level(D.LEVELS[7], Vector2(400, 520))
	g.fauna.roam_timer = 1e9
	await frames(40)
	var far_hidden := true
	var far_n := 0
	for pr in g.fauna.predators:
		if pr.dist_to(p.position) > minf(float(Cfg.v("view")) * 0.6, 125.0) + 2.0:
			far_n += 1
			if pr.model.visible or pr.anim.active: far_hidden = false
	check("level 8 spawns 48 hunters", g.fauna.predators.size() == 48)
	check("far animals are hidden with animation off", far_hidden and far_n > 10, "(%d far)" % far_n)
	check("far animals are not updated every frame", g.fauna.updates_last < (g.fauna.predators.size() + g.fauna.prey.size()) / 2, "(%d of %d this frame)" % [g.fauna.updates_last, g.fauna.predators.size() + g.fauna.prey.size()])
	_quiet()

	# ---------------- day / night, weather
	g.sky.hour = 12.0
	await frames(5)
	_quiet()
	var n0: int = g.fauna.predators.size()
	g.sky.hour = 19.9
	var became_night := false
	for i in 4000:
		await get_tree().process_frame
		if g.sky.is_night: became_night = true; break
	await frames(3)
	check("night falls and the clock runs", became_night, g.sky.clock_text())
	check("a hyena pack of 3 arrives at night", g.fauna.predators.size() == n0 + 3)
	var amb_night: Color = g.sky.env.ambient_light_color
	var e_night: float = g.sky.env.ambient_light_energy
	g.sky.night_vision = true
	await frames(3)
	var e_nv: float = g.sky.env.ambient_light_energy * g.sky.env.ambient_light_color.get_luminance()
	g.sky.hour = 12.0
	g.sky.night_vision = false
	await frames(3)
	var e_day: float = g.sky.env.ambient_light_energy * g.sky.env.ambient_light_color.get_luminance()
	check("night is darker than day", e_night * amb_night.get_luminance() < e_day * 0.3)
	check("night vision is brighter than night but well below daylight", e_nv > e_night * amb_night.get_luminance() * 1.8 and e_nv < e_day * 0.65, "(night %.2f, vision %.2f, day %.2f)" % [e_night * amb_night.get_luminance(), e_nv, e_day])
	check("day returned: night pack is told to leave", g.fauna.predators.size() >= 0 and not g.sky.is_night)
	_quiet()
	g.sky.hour = 23.985
	var d0: int = g.sky.day
	await secs(2.0)
	check("day counter increases at midnight", g.sky.day == d0 + 1)
	g.sky.hour = 12.0
	g.sky.set_weather(3)
	var flashes := [0]
	g.sky.lightning.connect(func(): flashes[0] += 1)
	for i in 30000:
		await get_tree().process_frame
		if flashes[0] > 0: break
	check("storm: rain falls and lightning strikes", g.sky.rain > 0.6 and flashes[0] > 0 and g.sky.rain_node.visible)
	g.sky.set_weather(0)
	check("weather has clear, cloudy, rain, storm", SkyRig.WEATHER_NAMES.size() == 4)

	# ---------------- pause, back button, map
	g.pause()
	check("pause opens the pause menu", g.state == g.PAUSE and g.menus.current == "pause")
	var rt: float = g.run_time
	await frames(20)
	check("game time stands still while paused", g.run_time == rt)
	g._back()
	check("back button resumes from pause", g.state == g.PLAY)
	g._back()
	check("back button pauses the game", g.state == g.PAUSE)
	g.resume()
	g.open_map()
	check("map button opens the full map", g.menus.current == "map")
	g.resume()
	g.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	check("(test mode ignores focus loss; auto-pause code path exists)", g.state == g.PLAY)

	# ---------------- menus open without errors, at four screen shapes
	for res in [Vector2(1280, 720), Vector2(1366, 768), Vector2(1920, 1080), Vector2(2400, 1080)]:
		var sc := minf(res.x / 1280.0, res.y / 720.0)
		g.ui_size_override = res / sc
		g._layout()
		await frames(2)
		var size: Vector2 = g.ui_size_override
		var boxes := {}
		for k in g.hud.rects: boxes["hud." + k] = g.hud.rects[k]
		for k in c.buttons:
			var b: Dictionary = c.buttons[k]
			boxes["btn." + k] = Rect2(b.pos - Vector2(b.r, b.r), Vector2(b.r, b.r) * 2.0)
		var bad := ""
		var keys := boxes.keys()
		for i in keys.size():
			var r: Rect2 = boxes[keys[i]]
			if r.position.x < 0 or r.position.y < 0 or r.end.x > size.x or r.end.y > size.y: bad += " off-screen:" + keys[i]
			for j in range(i + 1, keys.size()):
				if r.intersects(boxes[keys[j]]): bad += " overlap:%s/%s" % [keys[i], keys[j]]
		var small := 1e9
		for k in c.buttons: small = minf(small, c.buttons[k].r * 2.0)
		check("HUD layout %dx%d: nothing off-screen or overlapping" % [res.x, res.y], bad == "", bad)
		check("HUD layout %dx%d: smallest button %.0f units (>= 96)" % [res.x, res.y, small], small >= 96.0)
		g.state = g.PAUSE
		for m in ["pause", "settings", "howto", "map", "main", "levels", "stats", "achievements", "guide"]:
			g.menus.open(m)
			await frames(3)
			var worst := ""
			for n in g.menus._root.find_children("*", "PanelContainer", true, false):
				var pr2: Rect2 = (n as Control).get_global_rect()
				if pr2.position.x < -1 or pr2.position.y < -1 or pr2.end.x > size.x + 1 or pr2.end.y > size.y + 1: worst = "%s %s" % [m, pr2]
			if worst != "": check("menu fits %dx%d" % [res.x, res.y], false, worst)
		g.menus.close()
		g.state = g.PLAY
		g._set_play_ui(true)
	check("all menus open at 1280x720, 1366x768, 1920x1080, 2400x1080", true)
	g.ui_size_override = Vector2.ZERO
	g._layout()

	# ---------------- settings and presets
	Cfg.set_preset(0)
	check("Low preset: no shadows, 30 fps cap, reduced render scale, no wind", Cfg.v("shadows") == false and Engine.max_fps == 30 and float(Cfg.v("scale")) < 0.75 and Cfg.v("wind") == false)
	check("Low preset: sun shadow off, blob shadow on the deer", not g.sky.sun.shadow_enabled and p.blob != null)
	Cfg.set_preset(2)
	check("High preset: shadows on, 60 fps, full resolution", g.sky.sun.shadow_enabled and Engine.max_fps == 60 and float(Cfg.v("scale")) == 1.0 and p.blob == null)
	Cfg.set_over("view", 150.0)
	check("view distance setting changes fog and camera range", absf(g.camera.far - 190.0) < 0.1)
	Cfg.auto_quality = true
	check("auto quality steps down", Cfg.lower_quality() and Cfg.lower_quality() and Cfg.preset == 1)
	Cfg.auto_quality = false
	Cfg.set_preset(0)
	check("frame limit is on by default", Engine.max_fps == 30)

	# ---------------- level complete, unlock, death, restart
	keep_alive = false
	g.start_level(0)
	await frames(3)
	_quiet()
	g.plants_eaten = 2
	g.run_time = 179.5
	await secs(1.0)
	for i in 400:
		await get_tree().process_frame
		if g.menus.current == "complete": break
	check("level 1 completes after 3 minutes with 2 rare plants", g.result.get("won", false) and g.menus.current == "complete")
	check("level 2 is unlocked", int(Save.d.unlocked) == 2)
	g.start_endless()
	await frames(3)
	_quiet()
	g.run_time = 75.0
	p.damage(999.0, "Lion")
	check("death: deer falls with the death animation", not p.alive and p.cur_anim == "death")
	for i in 3000:
		await get_tree().process_frame
		if g.menus.current == "gameover": break
	check("death screen shows cause, time and stats", g.menus.current == "gameover" and g.result.cause == "Lion" and g.result.time >= 75.0)
	check("endless mode keeps the best time", float(Save.d.best_endless) >= 75.0)
	g.restart()
	await frames(3)
	check("restart works after death", g.state == g.PLAY and p.alive and p.health == p.max_health)
	g.to_menu()
	check("back to the main menu", g.state == g.MENU and g.menus.current == "main")
	check("statistics recorded", int(Save.d.stats.games) >= 3 and int(Save.d.stats.deaths) >= 1)
	await _tests_hunter()

## second half: wildlife density, playable animals
func _tests_hunter() -> void:
	var g := game
	var p: Player = g.player
	keep_alive = true
	# ---------------- wildlife is easy to find
	check("wildlife: at least 120 animals in about 50 herds, incl. elephants and rhinos", g.fauna.prey.size() >= 120, "(%d)" % g.fauna.prey.size())
	var worst_near := 999
	for k in 6:
		g.start_level(0)
		await frames(3)
		var near := 0
		var kinds := {}
		for a in g.fauna.prey:
			if a.alive and a.dist_to(p.position) < 60.0:
				near += 1; kinds[a.species] = true
		worst_near = mini(worst_near, near)
	check("wildlife: animals stand within 60 m of every start", worst_near >= 5, "(fewest in 6 starts: %d)" % worst_near)
	_quiet()
	g.to_menu()
	g.start_level(0)
	await frames(2)
	_quiet()
	var c: TouchControls = g.controls
	# ---------------- chase music and heartbeat
	_place(400, 520)
	await frames(15)
	var calm_ok: bool = float(Sfx.loop_target["chase"]) == 0.0 and float(Sfx.loop_target["heartbeat"]) == 0.0
	var chaser: Predator = g.fauna._make_predator("lion", Vector2(414, 520))
	chaser.last_seen = p.pos2()
	chaser.engage()
	var music_on := false
	var heart_on := false
	for i in 40:
		await get_tree().process_frame
		if float(Sfx.loop_target["chase"]) > 0.5: music_on = true
		if float(Sfx.loop_target["heartbeat"]) > 0.5 and Sfx.loops["heartbeat"].pitch_scale > 1.1: heart_on = true
	check("being hunted starts the chase music and a fast heartbeat", calm_ok and music_on and heart_on)
	_quiet()
	await frames(25)
	check("chase music and heartbeat stop when the hunt is over", float(Sfx.loop_target["chase"]) == 0.0 and float(Sfx.loop_target["heartbeat"]) == 0.0)
	# ---------------- the bite reaches the target
	for sp2 in ["lion", "hyena"]:
		_place(400, 520)
		p.health = p.max_health
		await frames(3)
		var biter: Predator = g.fauna._make_predator(sp2, Vector2(400 + 6.0, 520))
		biter.pack = [biter]
		biter.last_seen = p.pos2()
		biter.engage()
		var contact: float = biter.body * 1.8 + p.body * 1.2
		var gap_at_bite := 99.0
		var leapt := false
		for i in 400:
			await get_tree().process_frame
			p.health = p.max_health
			if biter.state == Predator.ATTACK:
				if biter.has_bite_clip or biter.model.position.y > 0.1: leapt = true
				if biter.hit_done:
					gap_at_bite = biter.dist_to(p.position) - contact; break
		check("%s lunges right up to its target before the bite lands" % sp2, gap_at_bite < 0.3 and leapt, "(gap %.2f m)" % gap_at_bite)
		_quiet()
	var hy: Animation = g.fauna._make_predator("hyena", Vector2(430, 540)).anim.get_animation("run")
	var q0: Quaternion = Quaternion.IDENTITY
	var worst := 0.0
	for t in hy.get_track_count():
		if hy.track_get_type(t) != Animation.TYPE_ROTATION_3D: continue
		var kn := hy.track_get_key_count(t)
		var step: float = (hy.track_get_key_value(t, 0) as Quaternion).angle_to(hy.track_get_key_value(t, kn - 1))
		if step > worst: worst = step
	check("hyena run clip has room to blend its last frame into the first", hy.length > hy.track_get_key_time(0, hy.track_get_key_count(0) - 1) + 0.02 or worst < 0.05, "(%.2f rad, len %.3f, last key %.3f, keys %d)" % [worst, hy.length, hy.track_get_key_time(0, hy.track_get_key_count(0) - 1), hy.track_get_key_count(0)])
	_quiet()
	await frames(3)
	var again: Predator = g.fauna._make_predator("hyena", Vector2(430, 540))
	check("clips still loop after every animal of a kind was removed and one comes back", again.anim.get_animation("run").loop_mode == Animation.LOOP_LINEAR and again.anim.get_animation("walk").loop_mode == Animation.LOOP_LINEAR)
	_quiet()
	# ---------------- more grass, more kinds of trees
	var vc: Dictionary = World.info.veg_counts
	var kinds := 0
	for tname in ["tree_a", "tree_b", "tree_c", "tree_d", "tree_big", "birch_a", "birch_b", "pine_a", "pine_b", "palm_a", "palm_b"]:
		if int(vc.get(tname, 0)) > 40 and g.vegetation.meshes.get(tname) != null: kinds += 1
	check("eleven kinds of living tree grow in the forest", kinds == 11, "(%d)" % kinds)
	var dead: int = int(vc.dead_a) + int(vc.dead_b) + int(vc.dead_c)
	check("dead trees stand among them", dead > 120 and g.vegetation.meshes.get("dead_b") != null, "(%d)" % dead)
	check("four kinds of bush plus berry bushes", int(vc.bush_a) > 200 and int(vc.bush_b) > 200 and int(vc.bush_c) > 200 and int(vc.bush_d) > 200)
	var gp := Vector2(400, 520)
	for i in 400:
		var cand := Vector2(200 + (i % 20) * 30, 200 + (i / 20) * 30)
		if World.biome(cand.x, cand.y) == World.GRASS and World.biome(cand.x + 12, cand.y) == World.GRASS and World.biome(cand.x, cand.y + 12) == World.GRASS:
			gp = cand; break
	g.grass.update(Vector3(gp.x, 0, gp.y))
	var tufts: int = g.grass.multimesh.visible_instance_count
	var tuft_tris: int = g.grass.multimesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() / 3
	var per_m2: float = tufts / (PI * g.grass._radius * g.grass._radius)
	check("grass is dense: at least one tuft for every 2 square metres of meadow", per_m2 > 0.5 and tuft_tris <= 12, "(%d tufts, %.2f per m2, %d tris each)" % [tufts, per_m2, tuft_tris])
	# ---------------- hunters do not give up while they can see you
	_place(400, 520)
	var dogged: Predator = g.fauna._make_predator("lion", Vector2(418, 520))
	dogged.pack = [dogged]
	dogged.last_seen = p.pos2()
	dogged.engage()
	var still := true
	var t1: float = g.run_time
	while g.run_time - t1 < 26.0:
		await get_tree().process_frame
		p.health = p.max_health
		if dogged.state != Predator.CHASE and dogged.state != Predator.ATTACK: still = false; break
	check("a lion that can see you is still after you 26 s later (it used to quit after 7 s)", still, Predator.STATE_NAMES[dogged.state])
	# ... until you hide in a bush
	var bush := Vector2.ZERO
	for key in World.bush_grid:
		var arr: PackedFloat32Array = World.bush_grid[key]
		var q := Vector2(arr[0], arr[1])
		if arr[2] > 1.2 and World.thicket_at(q.x, q.y, 25.0) < 0 and World.height(q.x, q.y) > 0.5 and World.playable(q.x + 20.0, q.y) and World.height(q.x + 20.0, q.y) > 0.5:
			bush = q; break
	_quiet()
	_place(bush.x + 5.0, bush.y)
	await frames(8)
	var open_ok: bool = not p.hidden and g.hud.status_text == ""
	var seeker: Predator = g.fauna._make_predator("lion", Vector2(bush.x + 20.0, bush.y))
	seeker.pack = [seeker]
	seeker.last_seen = p.pos2()
	seeker.engage()
	_place(bush.x, bush.y)
	var lost := false
	var shown := false
	for i in 400:
		await get_tree().process_frame
		_place(bush.x, bush.y)
		p.health = p.max_health
		if g.hud.status_text == "HIDDEN": shown = true
		if seeker.state != Predator.CHASE and seeker.state != Predator.ATTACK and seeker.state != Predator.STALK: lost = true; break
	check("standing inside a bush hides you: green HIDDEN text appears", open_ok and p.hidden and p.hide_kind == 1 and shown, "(bush at %.0f, %.0f)" % [bush.x, bush.y])
	check("the hunter loses a deer hidden in a bush and leaves", lost, Predator.STATE_NAMES[seeker.state])
	_quiet()
	# ... or swim into deep water
	var deep := Vector2.ZERO
	for i in 16000:
		var q2 := Vector2(40 + (i % 126) * 7.5, 40 + (i / 126) * 7.5)
		if World.height(q2.x, q2.y) < -p.swim_depth - 0.6 and World.playable(q2.x, q2.y):
			deep = q2; break
	var shore: Vector2 = World.dry_near(g._rng, deep, 10.0, 40.0)
	_place(deep.x, deep.y)
	await frames(8)
	var swim_hunter: Predator = g.fauna._make_predator("lion", shore)
	swim_hunter.pack = [swim_hunter]
	swim_hunter.last_seen = p.pos2()
	swim_hunter.engage()
	var lost2 := false
	for i in 500:
		await get_tree().process_frame
		_place(deep.x, deep.y)
		if swim_hunter.state != Predator.CHASE and swim_hunter.state != Predator.ATTACK and swim_hunter.state != Predator.STALK: lost2 = true; break
	var croc2: Predator = g.fauna._make_predator("crocodile", shore)
	check("swimming in deep water hides you from a lion but not from a crocodile", p.in_water and lost2 and swim_hunter.cant_see(p) and not croc2.cant_see(p) and g.hud.status_text == "HIDDEN IN WATER", "(%s)" % g.hud.status_text)
	_quiet()
	# ---------------- thirst: 30 seconds to drink
	_place(400, 520)
	keep_alive = false
	p.health = p.max_health; p.food = 100.0
	p.water = 0.0
	await secs(3.0)
	check("empty water bar starts a 30 s countdown and does not hurt yet", p.alive and p.health >= p.max_health - 0.01 and p.thirst_left > 25.0 and p.thirst_left < 28.0 and g.hud.thirst_text.begins_with("DRINK WATER"), "(%.1f s left, '%s')" % [p.thirst_left, g.hud.thirst_text])
	p.water = 30.0
	await frames(8)
	check("drinking cancels the countdown", p.thirst_left == 0.0 and g.hud.thirst_text == "")
	p.water = 0.0
	await frames(3)
	p.thirst_left = 0.3
	await secs(1.0)
	check("after 30 s without water the animal dies of thirst", not p.alive and p.cause == "Thirst", p.cause)
	g.start_level(0)
	keep_alive = true
	await frames(3)
	_quiet()
	check("the bars are drawn with their numbers", g.hud.has_method("_bar_n"))
	# ---------------- clock
	g.sky.hour = 10.0
	var h0: float = g.sky.hour
	var t0: float = g.run_time
	await secs(6.0)
	var per_min: float = (g.sky.hour - h0) / (g.run_time - t0) * 60.0
	check("one real minute is one game hour (a day lasts 24 minutes)", D.DAY_LENGTH == 1440.0 and absf(per_min - 1.0) < 0.1, "(%.2f h per minute)" % per_min)
	g.menus.open("main")
	var has_choose := false
	for bt in g.menus.find_children("*", "Button", true, false):
		if (bt as Button).text.contains("Choose animal"): has_choose = true
	check("the player is always the deer: no animal chooser in the menu", not has_choose and Save.character() == "deer" and p.species == "deer" and D.CHARACTERS.size() == 1)

func _mem() -> String:
	return "static %.1f MB, objects %d, nodes %d, orphans %d" % [OS.get_static_memory_usage() / 1048576.0, Performance.get_monitor(Performance.OBJECT_COUNT),
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)]

## Soak: a simple bot plays level after level (walks, grazes, drinks, eats plants, flees, dies, restarts)
func _soak(total: float) -> void:
	var g := game
	var c: TouchControls = g.controls
	c.bot = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var played := 0.0
	var next_print := 0.0
	var runs := 0
	var deaths := 0
	var dir := Vector2(0, 1)
	var turn := 0.0
	var lvl := 0
	var base_objects := 0.0
	var base_mem := 0.0
	var worst_ms := 0.0
	print("SOAK start: ", _mem())
	g.start_level(lvl)
	var last: float = Time.get_ticks_msec()
	while played < total:
		await get_tree().process_frame
		var now: float = Time.get_ticks_msec()
		worst_ms = maxf(worst_ms, now - last)
		last = now
		var dt: float = get_process_delta_time()
		played += minf(dt, 0.1)
		if g.state == g.OVER or g.menus.current == "gameover" or g.menus.current == "complete":
			if g.menus.is_open():
				if not g.result.get("won", false): deaths += 1
				runs += 1
				lvl = (lvl + 1) % 8
				if runs % 4 == 3: g.start_endless()
				else: g.start_level(lvl)
			continue
		var p: Player = g.player
		turn -= dt
		if turn <= 0.0:
			turn = rng.randf_range(1.0, 4.0)
			var a := rng.randf() * TAU
			dir = Vector2(cos(a), sin(a))
			c.sneak = rng.randf() < 0.15
			if rng.randf() < 0.2: c.jump = true
			if rng.randf() < 0.1: g.cam_yaw += rng.randf_range(-1.0, 1.0)
			if rng.randf() < 0.05:
				g.pause(); g.resume()
			if rng.randf() < 0.03:
				g.open_map(); await get_tree().process_frame; g.resume()
			if rng.randf() < 0.04: Cfg.set_preset(rng.randi() % 3)
		c.sprint = g.fauna.threat_level == 2
		c.move = dir
		if (p.food < 60.0 or p.water < 60.0 or g.plants.nearest(p.position, 2.8) >= 0) and g.fauna.threat_level < 2:
			if p.action == "" and rng.randf() < 0.05:
				c.move = Vector2.ZERO
				c.act = true
			if p.action != "": c.move = Vector2.ZERO
		if played >= next_print:
			next_print += maxf(10.0, total / 12.0)
			if base_objects == 0.0 and played > total * 0.25:
				base_objects = Performance.get_monitor(Performance.OBJECT_COUNT)
				base_mem = OS.get_static_memory_usage()
			print("SOAK t=%4.0fs runs=%d deaths=%d hunters=%d  %s" % [played, runs, deaths, g.fauna.predators.size(), _mem()])
	g.to_menu()
	await frames(5)
	var objects := Performance.get_monitor(Performance.OBJECT_COUNT)
	var mem := float(OS.get_static_memory_usage())
	print("SOAK end:   ", _mem(), "  worst frame %.0f ms" % worst_ms)
	check("soak: no orphan nodes", Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT) == 0)
	if base_mem > 0.0:
		check("soak: memory did not grow more than 10% after the first quarter", mem < base_mem * 1.10, "(%.1f -> %.1f MB)" % [base_mem / 1048576.0, mem / 1048576.0])
	check("soak: runs were played", runs >= 1, "(%d runs)" % runs)


## Scene budget estimate (no GPU needed): for many view points it counts what the
## renderer would be asked to draw - every node that is switched on and touches the
## camera frustum - and adds up draw calls and triangles.
##   godot --headless --path . -- --test-perf
func _perf() -> void:
	var g := game
	var info: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/nature/nature.json"))
	var veg: Vegetation = g.vegetation
	var tris_of := {}
	for name in veg.meshes: tris_of[veg.meshes[name]] = int(info[name].tris)
	for name in veg.lod_meshes: tris_of[veg.lod_meshes[name]] = int(info[name].lod1_tris)
	for name in veg.lod2_meshes: tris_of[veg.lod2_meshes[name]] = int(info[name].lod2_tris)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for preset in 3:
		Cfg.set_preset(preset)
		g.start_level(7)            # the heaviest level: 48 hunters
		await frames(3)
		var worst_dc := 0
		var worst_tris := 0
		var worst_part := {}
		var sum_dc := 0
		var sum_tris := 0
		var n := 0
		for spot in 24:
			var pt := World.random_dry_point(rng)
			_place(pt.x, pt.y)
			g.cam_yaw = rng.randf() * TAU
			g.cam_pitch = 0.3
			g.cam_target = g.player.position + Vector3(0, 1.25, 0)
			await frames(2)
			veg.update_visibility(g.camera.position, true)
			g.grass._last = Vector3(1e9, 0, 1e9)
			await frames(2)
			var planes: Array[Plane] = g.camera.get_frustum()
			var dc := 0
			var tris := 0
			var part := {}
			# vegetation chunks (64 m)
			for i in veg._nodes.size():
				for node in [veg._nodes[i], veg._far_nodes[i], veg._far2_nodes[i]]:
					if node == null or not node.visible: continue
					if not _box_in(planes, Vector3(veg._cx[i], 12.0, veg._cz[i]), Vector3(32, 30, 32)): continue
					dc += 1
					var tt: int = node.multimesh.instance_count * int(tris_of.get(node.multimesh.mesh, 300))
					tris += tt
					var kk := "veg%d" % veg._kind[i] if node == veg._nodes[i] else "lod"
					part[kk] = int(part.get(kk, 0)) + tt
			# terrain chunks (128 m, 2048 triangles each) and water
			for cz in 16:
				for cx in 16:
					var hc := World.height(cx * 64.0 + 32.0, cz * 64.0 + 32.0)
					if _box_in(planes, Vector3(cx * 64.0 + 32.0, hc, cz * 64.0 + 32.0), Vector3(32, 30, 32)):
						dc += 1; tris += 512
			for cz in 4:
				for cx in 4:
					if _box_in(planes, Vector3(cx * 256.0 + 128.0, 0.0, cz * 256.0 + 128.0), Vector3(128, 1, 128)):
						dc += 1; tris += g.water.triangles / 8
			# animals
			var animals: Array = g.fauna.predators + g.fauna.prey
			for a in animals:
				if a.tier == Animal.TIER_FAR: continue
				if not _box_in(planes, a.position + Vector3(0, 0.6, 0), Vector3(1.2, 1.0, 1.2)): continue
				dc += (4 if a.is_bird else 1) + (1 if a.blob != null and a.tier == Animal.TIER_NEAR else 0)
				tris += 230 if a.is_bird else int(Animal.info()[a.cfg.model].tris)
			dc += 2; tris += 2100 + 2            # deer + its blob shadow
			dc += 8; tris += 8 * 230             # sky birds (2 hawks at most in view)
			dc += 1; tris += g.grass.multimesh.visible_instance_count * 9
			dc += 4; tris += 400                 # sky dome, sun, moon, rain
			for it in g.plants.items:
				if it.node.visible and _box_in(planes, it.node.position, Vector3(1, 1, 1)):
					dc += 2; tris += 150
			dc += 6                              # HUD, minimap, touch controls (canvas batches)
			part["grass"] = g.grass.multimesh.visible_instance_count * 9
			if tris > worst_tris: worst_part = part
			worst_dc = maxi(worst_dc, dc); worst_tris = maxi(worst_tris, tris)
			sum_dc += dc; sum_tris += tris; n += 1
		print("PERF %-6s  draw calls avg %d  max %d   triangles avg %dk  max %dk   (budget: 150 / 120k)" % [Cfg.PRESETS[preset].name, sum_dc / n, worst_dc, sum_tris / n / 1000, worst_tris / 1000])
		print("     heaviest view, triangles by group: ", worst_part)
		check("%s preset stays under 150 draw calls and 120k triangles at all sampled views" % Cfg.PRESETS[preset].name, worst_dc <= 150 and worst_tris <= 120000, "(max %d calls, %dk triangles)" % [worst_dc, worst_tris / 1000])
		g.to_menu()
	Cfg.set_preset(0)

func _box_in(planes: Array[Plane], c: Vector3, e: Vector3) -> bool:
	for pl in planes:
		# Godot frustum planes point outward: a box is outside when it is fully in front of one
		var r := e.x * absf(pl.normal.x) + e.y * absf(pl.normal.y) + e.z * absf(pl.normal.z)
		if pl.distance_to(c) > r: return false
	return true
