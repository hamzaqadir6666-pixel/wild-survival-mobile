extends Node3D
## Wild Survival (Mobile Edition) - main scene script.
## Builds the world in small steps behind a progress bar, then runs menus and the game.

enum { LOADING, MENU, PLAY, PAUSE, OVER }
var state := LOADING
var terrain: Terrain
var water: Water
var vegetation: Vegetation
var grass: Grass
var sky: SkyRig
var plants: Plants
var fauna: Fauna
var player: Player
var fawn: Animal
var camera: Camera3D

var ui: CanvasLayer
var ui_root: Control
var hud: Hud
var minimap: Minimap
var controls: TouchControls
var menus: Menus
var loading: Control
var load_art: TextureRect
var load_tip: Label
var load_pct: Label
var load_time := 0.0
var load_shown := 0.0
var load_tip_i := 0
var load_tip_0 := randi() % 8
var load_bar: ProgressBar
var load_label: Label
var ui_size_override := Vector2.ZERO     # tests set this to check other screen shapes

# run state
var level_index := 0
var endless := false
var level := {}
var run_time := 0.0
var escapes := 0
var plants_eaten := 0
var found_thickets := {}
var found_landmarks := {}
var found_lakes := {}
var result := {}
var start_point := Vector2(400, 520)
var fawn_found := false
var night_alive := false

var cam_yaw := 0.0
var cam_pitch := 0.35
var cam_target := Vector3.ZERO
var shake := 0.0
var _load_step := 0
var _frame := 0
var _over_timer := 0.0
var _thunder := -1.0
var _fps_time := 0.0
var _fps_frames := 0
var _fps_cool := 20.0
var _water_near := 0.0
var _last_threat := 0
var _season := -1
var longest_frame_ms := 0.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	get_tree().set_auto_accept_quit(true)
	camera = Camera3D.new()
	camera.fov = 65.0
	camera.near = 0.25
	camera.position = Vector3(400, 30, 560)
	add_child(camera)
	camera.make_current()
	_build_ui()
	get_viewport().size_changed.connect(_layout)
	Cfg.changed.connect(apply_quality)
	_layout()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--test") or a.begins_with("--soak"):
			var bot: Node = load("res://tests/bot.gd").new()
			bot.name = "Bot"
			bot.game = self
			bot.mode = a
			add_child(bot)
			break

func _build_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)
	ui_root = Control.new()
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(ui_root)
	hud = Hud.new(); hud.game = self; hud.visible = false
	ui_root.add_child(hud)
	minimap = Minimap.new(); minimap.game = self; minimap.visible = false
	ui_root.add_child(minimap)
	controls = TouchControls.new(); controls.visible = false
	ui_root.add_child(controls)
	controls.map_pressed.connect(open_map)
	controls.pause_pressed.connect(pause)
	menus = Menus.new(); menus.game = self
	ui_root.add_child(menus)
	_build_loading()

const LOAD_TIPS := [
	"A hunter that sees you will not give up. Get out of sight.",
	"Deep water hides you from everything except crocodiles.",
	"Safe thickets are marked on the map. No hunter follows you inside.",
	"Sneak to move quietly. Sprinting is loud and drains stamina.",
	"When the water bar is empty you have 30 seconds to drink.",
	"Stand still for a while and the elk rests. Resting refills stamina faster.",
	"Rare plants give abilities that stay with you between levels.",
	"Listen: the music changes the moment a hunter charges.",
]

## Loading screen: painted key art that slowly drifts, the title, a tip that changes, a slim bar with its percentage.
func _build_loading() -> void:
	loading = Control.new()
	loading.set_anchors_preset(Control.PRESET_FULL_RECT)
	loading.clip_contents = true
	ui_root.add_child(loading)
	var back := ColorRect.new()
	back.color = Color(0.03, 0.05, 0.04)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	loading.add_child(back)
	load_art = TextureRect.new()
	load_art.texture = load("res://assets/ui/loading.jpg")
	load_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	load_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	load_art.set_anchors_preset(Control.PRESET_FULL_RECT)
	loading.add_child(load_art)
	# dark fade over the lower half so the text is always readable
	var grad := Gradient.new()
	grad.set_color(0, Color(0, 0, 0, 0.0)); grad.set_color(1, Color(0.01, 0.03, 0.02, 0.92))
	grad.set_offset(0, 0.42); grad.set_offset(1, 0.97)
	var gt := GradientTexture2D.new()
	gt.gradient = grad; gt.fill_from = Vector2(0, 0); gt.fill_to = Vector2(0, 1); gt.width = 8; gt.height = 128
	var shade := TextureRect.new()
	shade.texture = gt
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	loading.add_child(shade)
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]: m.add_theme_constant_override("margin_" + side, 70)
	m.add_theme_constant_override("margin_bottom", 44)
	loading.add_child(m)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_END
	v.add_theme_constant_override("separation", 6)
	m.add_child(v)
	var t := UI.label("WILD SURVIVAL", 68, UI.GOLD)
	t.add_theme_constant_override("outline_size", 14)
	t.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.0, 0.9))
	t.add_theme_constant_override("shadow_offset_y", 5)
	t.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	v.add_child(t)
	var sub := UI.label("Stay alert.  Stay hidden.  Stay alive.", 20, Color(0.92, 0.95, 0.88))
	v.add_child(sub)
	var gap := Control.new(); gap.custom_minimum_size = Vector2(0, 18)
	v.add_child(gap)
	load_tip = UI.label("Tip: " + LOAD_TIPS[randi() % LOAD_TIPS.size()], 17, Color(1.0, 0.93, 0.7))
	v.add_child(load_tip)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	v.add_child(row)
	load_label = UI.label("Loading...", 16, Color(0.85, 0.9, 0.85))
	load_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(load_label)
	load_pct = UI.label("0%", 16, UI.GOLD)
	row.add_child(load_pct)
	load_bar = ProgressBar.new()
	load_bar.custom_minimum_size = Vector2(0, 12)
	load_bar.max_value = 100.0
	load_bar.show_percentage = false
	load_bar.add_theme_stylebox_override("background", UI.box(Color(0, 0, 0, 0.65), 6, 0))
	load_bar.add_theme_stylebox_override("fill", UI.box(Color(1.0, 0.78, 0.25), 6, 0))
	v.add_child(load_bar)
	Sfx.set_loop("loading", 0.9)

## drift of the picture, tip rotation, smooth bar; called every frame while the loading screen is up
func _loading_anim(dt: float) -> void:
	load_time += dt
	load_art.pivot_offset = load_art.size * Vector2(0.62, 0.45)
	var z := 1.0 + 0.06 * minf(load_time / 12.0, 1.0) + 0.012 * sin(load_time * 0.5)
	load_art.scale = Vector2(z, z)
	load_shown = move_toward(load_shown, load_bar.value, dt * 90.0)
	load_pct.text = "%d%%" % int(load_shown)
	if int(load_time / 3.5) != load_tip_i:
		load_tip_i = int(load_time / 3.5)
		load_tip.text = "Tip: " + LOAD_TIPS[(load_tip_i + load_tip_0) % LOAD_TIPS.size()]

## loading done: chime, then the picture fades away over the menu
func _finish_loading() -> void:
	Sfx.set_loop("loading", 0.0)
	Sfx.play("ready", 0.8)
	load_pct.text = "100%"
	loading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tw := create_tween()
	tw.tween_property(loading, "modulate:a", 0.0, 0.7)
	tw.tween_callback(func(): loading.visible = false)

## canvas size and safe area (notch, rounded corners) in canvas units
func _layout() -> void:
	var size := get_viewport().get_visible_rect().size
	if ui_size_override != Vector2.ZERO: size = ui_size_override
	var safe := Rect2(Vector2.ZERO, size)
	if OS.has_feature("mobile") and ui_size_override == Vector2.ZERO:
		var win := get_window().size
		var sa := DisplayServer.get_display_safe_area()
		if win.x > 0 and win.y > 0 and sa.size.x > 0:
			var k := Vector2(size.x / win.x, size.y / win.y)
			var s2 := Rect2(Vector2(sa.position) * k, Vector2(sa.size) * k).intersection(Rect2(Vector2.ZERO, size))
			if s2.size.x > size.x * 0.6 and s2.size.y > size.y * 0.6: safe = s2
	ui_root.position = Vector2.ZERO
	ui_root.size = size
	var r0 := clampf(UI.mm(9.0, get_window()) * 0.5, 48.0, 66.0)
	hud.layout(size, safe, r0)
	controls.layout(size, safe, r0)
	menus.layout(size, safe)
	var mr: Rect2 = hud.rects.minimap
	minimap.position = mr.position
	minimap.size = mr.size

func apply_quality() -> void:
	if state == LOADING: return
	sky.apply_quality()
	vegetation.apply_quality()
	grass.apply_quality()
	fauna.apply_quality()
	player.apply_quality()
	if fawn: fawn.apply_quality()
	camera.far = float(Cfg.v("view")) + 40.0
	vegetation.update_visibility(camera.global_position, true)

# ------------------------------------------------------------------ loading
func _loading_step() -> void:
	var t0 := Time.get_ticks_msec()
	match _load_step:
		0:
			load_label.text = "Reading the map..."
			World.load_data()
			_load_step = 1
		1:
			terrain = Terrain.new(); add_child(terrain); terrain.setup()
			_load_step = 2
		2:
			load_label.text = "Shaping the land..."
			while Time.get_ticks_msec() - t0 < 14:
				if not terrain.build_next():
					_load_step = 3
					break
			load_bar.value = 5.0 + 30.0 * terrain.built / float(terrain.total())
		3:
			water = Water.new(); add_child(water); water.build()
			sky = SkyRig.new(); add_child(sky); sky.setup()
			load_bar.value = 38.0
			_load_step = 4
		4:
			load_label.text = "Growing the forest..."
			vegetation = Vegetation.new(); add_child(vegetation); vegetation.setup()
			_load_step = 5
		5:
			if not vegetation.build_some(14): _load_step = 6
			load_bar.value = 40.0 + 35.0 * vegetation.progress()
		6:
			grass = Grass.new(); add_child(grass); grass.setup(vegetation.material)
			plants = Plants.new(); add_child(plants); plants.setup()
			player = Player.new(); add_child(player); player.setup_player(Save.character())
			player.died.connect(_on_died)
			player.note.connect(hud.notify)
			player.plant_wanted.connect(_on_action)
			player.hurt.connect(_on_hurt)
			player.reset_run(start_point)
			load_bar.value = 80.0
			_load_step = 7
		7:
			load_label.text = "Waking the animals..."
			if fauna == null:
				fauna = Fauna.new(); add_child(fauna); fauna.setup(player, sky)
				fauna.deer_hit.connect(_on_deer_hit)
				fauna.escaped.connect(_on_escaped)
				fauna.species_seen.connect(_on_seen)
				fauna.night_pack_came.connect(func(): hud.notify("Night falls. A hyena pack is on the prowl!", 2))
				sky.lightning.connect(func(): _thunder = _rng.randf_range(0.3, 1.6))
				sky.weather_changed.connect(_on_weather)
				sky.day_started.connect(_on_dawn)
				sky.night_started.connect(func(): night_alive = player.alive)
			if fauna.build_some(12): _load_step = 8
			load_bar.value = 80.0 + 18.0 * minf(1.0, fauna.prey.size() / 140.0)
		8:
			fawn = Animal.new(); add_child(fawn); fawn.setup("fawn")
			var fp: Array = World.info.fawn
			fawn.place(fp[0], fp[1])
			load_bar.value = 100.0
			_load_step = 9
		9:
			state = MENU
			_finish_loading()
			sky.reset(9.0)
			apply_quality()
			Sfx.start_music()
			menus.open("main")

# ------------------------------------------------------------------ run control
func in_run() -> bool:
	return state == PLAY or state == PAUSE

func start_level(i: int) -> void:
	level_index = clampi(i, 0, D.LEVELS.size() - 1)
	endless = false
	level = D.LEVELS[level_index]
	_begin_run()

func start_endless() -> void:
	endless = true
	level = D.ENDLESS
	_begin_run()

## menu: put the chosen animal in front of the menu camera
func show_character() -> void:
	if state != MENU: return
	player.set_character(Save.character())
	player.apply_quality()
	player.reset_run(Vector2(400, 520))
	player.yaw = cam_yaw + 0.6; player.rotation.y = player.yaw

func restart() -> void:
	if endless: start_endless()
	else: start_level(level_index)

func _begin_run() -> void:
	start_point = World.random_dry_point(_rng)
	for tries in 30:
		if World.thicket_at(start_point.x, start_point.y, 20.0) < 0 and World.biome(start_point.x, start_point.y) != World.ROCK: break
		start_point = World.random_dry_point(_rng)
	player.set_character(Save.character())
	run_time = 0.0; escapes = 0; plants_eaten = 0
	found_thickets = {}; found_landmarks = {}; found_lakes = {}
	fawn_found = false; night_alive = false
	_over_timer = 0.0; _last_threat = 0; shake = 0.0
	var fp: Array = World.info.fawn
	fawn.place(fp[0], fp[1])
	player.reset_run(start_point)
	plants.reset(start_point)
	fauna.spawn_level(level, start_point)
	sky.reset(float(level.get("hour", D.START_HOUR)))
	sky.night_vision = player.has("moonpetal")
	cam_yaw = 0.0; cam_pitch = 0.35
	cam_target = player.position + Vector3(0, 1.25, 0)
	hud.clear()
	controls.reset()
	controls.sneak = false
	menus.close()
	_set_play_ui(true)
	state = PLAY
	Save.d.stats.games = int(Save.d.stats.games) + 1
	vegetation.update_visibility(player.position, true)
	if endless: hud.notify("Endless mode: survive as long as you can.", 0)
	else: hud.notify("Level %d: survive %s and eat %d rare plants." % [level_index + 1, D.fmt_time(level.time), level.plants], 0)
	if not bool(Save.d.tutorial_done) and not Cfg.test_mode:
		state = PAUSE
		_set_play_ui(false)
		menus.start_tutorial()

func _set_play_ui(on: bool) -> void:
	hud.visible = on or state == PAUSE or state == OVER
	minimap.visible = on
	controls.visible = on
	controls.enabled = on
	if not on: controls.reset()

func pause() -> void:
	if state != PLAY: return
	state = PAUSE
	_set_play_ui(false)
	menus.open("pause")

func open_map() -> void:
	if state != PLAY: return
	state = PAUSE
	_set_play_ui(false)
	menus.open("map")

func resume() -> void:
	if state != PAUSE: return
	menus.close()
	state = PLAY
	_set_play_ui(true)

func to_menu() -> void:
	state = MENU
	Save.store()
	fauna.clear_predators()
	_set_play_ui(false)
	hud.visible = false
	Sfx.silence_loops()
	menus.open("main")

func goal_text() -> String:
	if endless:
		return "Endless  %s    Best %s" % [D.fmt_time(run_time), D.fmt_time(maxf(float(Save.d.best_endless), run_time))]
	return "Survive %s / %s    Rare plants %d / %d" % [D.fmt_time(minf(run_time, level.time)), D.fmt_time(level.time), mini(plants_eaten, int(level.plants)), int(level.plants)]

func discoveries() -> int:
	return found_thickets.size() + found_landmarks.size() + found_lakes.size()

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			if state == PLAY and not Cfg.test_mode: pause()
			if what == NOTIFICATION_APPLICATION_PAUSED: Save.store()
		NOTIFICATION_WM_GO_BACK_REQUEST:
			_back()

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_ESCAPE: _back()

## Android back button: pause in game, go one screen back in menus, leave from the main menu
func _back() -> void:
	if state == PLAY: pause()
	elif state == LOADING: pass
	elif menus.current == "main": get_tree().quit()
	else: menus.back_pressed()

# ------------------------------------------------------------------ frame
func _process(delta: float) -> void:
	longest_frame_ms = maxf(longest_frame_ms, delta * 1000.0)
	_frame += 1
	if state == LOADING:
		_loading_step()
		if state == LOADING:
			_loading_anim(delta)
		return
	var dt := minf(delta, 0.1)
	if state == MENU:
		# slow fly-around behind the menu
		cam_yaw += dt * 0.05
		var c := Vector3(400.0 + sin(cam_yaw) * 60.0, 0, 520.0 + cos(cam_yaw) * 60.0)
		camera.position = Vector3(c.x, maxf(World.height(c.x, c.z), 0.0) + 16.0, c.z)
		camera.look_at(Vector3(400, 4, 520), Vector3.UP)
		sky.update(0.0, camera.position)
		vegetation.update_visibility(camera.position)
		grass.update(camera.position)
		return
	if state == PAUSE:
		return
	# ---- PLAY and OVER ----
	if state == PLAY:
		run_time += dt
		var jump := controls.jump
		var act := controls.act
		controls.jump = false
		controls.act = false
		player.update(dt, controls.move, cam_yaw, controls.sprint, controls.sneak, jump, act)
		_camera_input()
	else:
		player.update(dt, Vector2.ZERO, cam_yaw, false, false, false, false)
		_over_timer -= dt
		if _over_timer <= 0.0 and not menus.is_open():
			_set_play_ui(false)
			hud.visible = false
			menus.open("gameover" if not result.get("won", false) else "complete")
	_camera_update(dt)
	sky.update(dt, camera.position)
	fauna.update(dt, camera)
	plants.update(player.position)
	vegetation.update_visibility(camera.position)
	grass.update(player.position)
	_fawn_update(dt)
	if _thunder >= 0.0:
		_thunder -= dt
		if _thunder < 0.0: Sfx.play("thunder%d" % (1 + _rng.randi() % 2), 1.0, _rng.randf_range(0.85, 1.1))
	if _frame % 10 == 0: _slow_update()
	if state == PLAY:
		_goals()
		_fps_watch(delta)

func _camera_input() -> void:
	var l := controls.look
	controls.look = Vector2.ZERO
	if l == Vector2.ZERO: return
	var k := 0.0052 * Cfg.sensitivity
	cam_yaw -= l.x * k
	cam_pitch += l.y * k * 0.8 * (-1.0 if Cfg.invert else 1.0)
	cam_pitch = clampf(cam_pitch, -0.12, 1.15)

func _camera_update(dt: float) -> void:
	var want := player.position + Vector3(0, 1.25, 0)
	cam_target = cam_target.lerp(want, minf(1.0, dt * 10.0))
	var dist := Cfg.cam_dist
	var dir := Vector3(sin(cam_yaw) * cos(cam_pitch), sin(cam_pitch), cos(cam_yaw) * cos(cam_pitch))
	var pos := cam_target + dir * dist
	var ground := maxf(World.height(pos.x, pos.z), 0.0) + 0.6
	if pos.y < ground: pos.y = ground
	if shake > 0.0:
		shake = maxf(0.0, shake - dt * 2.5)
		pos += Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * shake * 0.18
	camera.position = pos
	camera.look_at(cam_target, Vector3.UP)

## things that do not need to run every frame
func _slow_update() -> void:
	var p := player.position
	# action button
	var near := plants.nearest(p, 2.8) if player.alive else -1
	if near >= 0:
		var t: String = plants.items[near].t
		controls.action_icon = Hud.ABILITY_ICON.get(t, Hud.PLANT_ICON.get(t, "leaf"))
		hud.hint = "Eat " + D.PLANTS[t].name
	else:
		var c := player.context()
		controls.action_icon = "leaf" if c == "graze" else ("drop" if c == "drink" else "")
		hud.hint = "Graze" if c == "graze" else ("Drink" if c == "drink" else "")
		if player.action != "": hud.hint = "Grazing..." if player.action == "graze" else "Drinking..."
	controls.queue_redraw()
	# discoveries
	if player.alive:
		var ti := World.thicket_at(p.x, p.z)
		if ti >= 0 and not found_thickets.has(ti):
			found_thickets[ti] = true
			hud.notify("Safe thicket found! Hunters cannot follow you in here.", 3)
		for i in World.landmarks.size():
			if found_landmarks.has(i): continue
			var l: Dictionary = World.landmarks[i]
			if Vector2(l.x - p.x, l.z - p.z).length() < 15.0:
				found_landmarks[i] = true
				Save.d.landmarks[str(i)] = true
				_landmark_bonus(l)
		for i in World.lakes.size():
			if found_lakes.has(i): continue
			var k: Dictionary = World.lakes[i]
			if Vector2(k.x - p.x, k.z - p.z).length() < float(k.r) + 8.0:
				found_lakes[i] = true
				hud.notify("Discovered: %s" % k.name, 3)
	# threat pop-ups
	var th := fauna.threat_level
	if th != _last_threat and player.alive:
		if th == 2: hud.notify("You are being hunted! Run!", 2)
		elif th == 1 and _last_threat == 0: hud.notify("Something is watching you...", 1)
		_last_threat = th
	# ambience mix
	if _frame % 30 == 0:
		_water_near = 0.0
		for a in 6:
			var q := Vector2(p.x + cos(a * 1.047) * 14.0, p.z + sin(a * 1.047) * 14.0)
			if World.height(q.x, q.y) < 0.0: _water_near = 0.55
		if World.height(p.x, p.z) < 0.3: _water_near = 0.85
	Sfx.set_loop("amb_day", sky.dayf * (1.0 - sky.rain * 0.8) * 0.8)
	Sfx.set_loop("amb_night", (1.0 - sky.dayf) * 0.8)
	Sfx.set_loop("amb_water", _water_near)
	Sfx.set_loop("amb_rain", sky.rain)
	Sfx.set_loop("amb_wind", clampf((sky.cover - 0.4) * 0.9, 0.0, 0.6))
	# being hunted: chase music takes over and the heart pounds, faster the closer the hunter and the lower the health
	var hunted := state == PLAY and player.alive and th == 2
	Sfx.set_loop("chase", 0.9 if hunted else 0.0)
	if hunted:
		var close := clampf(1.0 - fauna.nearest_hunter_dist / 40.0, 0.0, 1.0)
		var weak := 1.0 - player.health / player.max_health
		Sfx.set_loop("heartbeat", 0.55 + 0.45 * maxf(close, weak))
		Sfx.set_heart_rate(1.15 + 0.6 * close + 0.4 * weak)
	else:
		# after the chase the heart calms down; it also beats when badly hurt
		var low := player.alive and state == PLAY and player.health < player.max_health * 0.3
		Sfx.set_loop("heartbeat", 0.5 if low else 0.0)
		if low: Sfx.set_heart_rate(1.3)
	# seasons: a new one every two days, shown as a colour change of leaves and grass
	var season: int = ((sky.day - 1) / 2) % 4
	if season != _season:
		var first := _season == -1
		_season = season
		var tint: Vector3 = [Vector3(1, 1, 1), Vector3(1.06, 1.0, 0.86), Vector3(1.22, 0.92, 0.62), Vector3(0.88, 0.95, 0.98)][season]
		vegetation.material.set_shader_parameter("season", tint)
		terrain.material.set_shader_parameter("tint", tint)
		if not first: hud.notify("The season changes: %s" % ["Spring", "Summer", "Autumn", "Late rains"][season], 0)

func _landmark_bonus(l: Dictionary) -> void:
	match l.kind:
		"salt_lick":
			player.stamina = player.max_stamina; player.heal(30.0)
		"giant_tree": player.heal(25.0)
		"berry_glade": player.food = minf(100.0, player.food + 40.0)
		"banana_grove": player.food = 100.0
	hud.notify("Landmark: %s - %s" % [l.name, D.LANDMARK_BONUS[l.kind]], 3)
	if Save.d.landmarks.size() >= World.landmarks.size(): _achieve("landmarks")
	Save.store()

func _goals() -> void:
	if endless or not player.alive: return
	if run_time >= float(level.time) and plants_eaten >= int(level.plants):
		_finish(true, "")

func _on_action() -> void:
	var i := plants.nearest(player.position, 2.8)
	if i < 0:
		player.begin_context()
		return
	var t := plants.eat(i)
	var pd: Dictionary = D.PLANTS[t]
	Sfx.play("eat", 0.7, 1.0)
	Save.d.plants_found[t] = true
	Save.d.stats.plants = int(Save.d.stats.plants) + 1
	var msg := "%s: %s" % [pd.name, pd.text]
	var kind := 3
	match t:
		"clover":
			if Save.ability("clover") < D.CLOVER_MAX:
				Save.add_ability("clover")
				player.refresh_abilities()
				msg = "Swift Clover: speed now %d%%" % player.speed_percent()
			else: msg = "Swift Clover: you are already at top speed."
		"ironbark":
			Save.add_ability(t); player.refresh_abilities(); player.heal(10.0)
		"sunberry":
			Save.add_ability(t); player.refresh_abilities(); player.stamina = minf(player.max_stamina, player.stamina + 10.0)
		"moonpetal", "ghostfern", "owleye", "springlily", "lotus":
			Save.add_ability(t)
			sky.night_vision = player.has("moonpetal")
		"herb": player.heal(45.0)
		"honey":
			player.food = minf(100.0, player.food + 50.0); player.stamina = player.max_stamina
		"toadstool":
			player.poison = 8.0
			kind = 2
			msg = "Red Toadstool: you are poisoned!"
	if t != "toadstool": plants_eaten += 1
	hud.notify(msg, kind)
	var all := true
	for k in D.PLANT_ORDER:
		if not Save.d.plants_found.has(k): all = false
	if all: _achieve("plants")
	Save.store()

func _on_hurt(_amount: float) -> void:
	hud.flash = 1.0
	shake = 1.0

func _on_deer_hit(pred: Predator, dmg: float) -> void:
	if not player.alive: return
	Sfx.play("thud", 1.0, 0.9)
	Sfx.play(pred.cfg.sound, 0.8, pred.cfg.pitch)
	if not Cfg.test_mode: Input.vibrate_handheld(90)
	player.damage(dmg, pred.cfg.name)

func _on_escaped() -> void:
	escapes += 1
	Save.d.stats.escapes = int(Save.d.stats.escapes) + 1
	hud.notify("You escaped!", 3)
	_achieve("first_escape")

func _on_seen(sp: String) -> void:
	hud.notify("New wildlife: %s" % D.SPECIES[sp].name, 0)
	if fauna.seen_count() >= D.WILDLIFE_TOTAL: _achieve("wildlife")

func _on_weather(kind: int) -> void:
	if state == PLAY: hud.notify(["The sky clears.", "Clouds gather.", "It starts to rain.", "A storm is breaking!"][kind], 0)

func _on_dawn() -> void:
	if state == PLAY and night_alive and player.alive:
		Save.d.stats.nights = int(Save.d.stats.nights) + 1
		hud.notify("Dawn. You survived the night!", 3)
		_achieve("night")
	night_alive = false

func _achieve(key: String) -> void:
	if Save.unlock(key):
		hud.notify("Achievement: %s" % D.ACHIEVEMENTS[key][0], 3)
		Save.store()

func _on_died(cause: String) -> void:
	if not Cfg.test_mode: Input.vibrate_handheld(250)
	Save.d.stats.deaths = int(Save.d.stats.deaths) + 1
	_finish(false, cause)

func _finish(won: bool, cause: String) -> void:
	if state != PLAY: return
	var s: Dictionary = Save.d.stats
	s.best_time = maxf(float(s.best_time), run_time)
	if endless: Save.d.best_endless = maxf(float(Save.d.best_endless), run_time)
	if won:
		s.levels_done = int(s.levels_done) + 1
		Save.d.unlocked = clampi(maxi(int(Save.d.unlocked), level_index + 2), 1, D.LEVELS.size())
		if level_index == D.LEVELS.size() - 1: _achieve("campaign")
	result = {"won": won, "cause": cause, "time": run_time, "day": sky.day, "escapes": escapes, "plants": plants_eaten, "discoveries": discoveries(),
		"wildlife": fauna.seen_count(), "level": level_index, "endless": endless, "best": float(Save.d.best_endless)}
	Save.store()
	state = OVER
	Sfx.set_loop("chase", 0.0); Sfx.set_loop("heartbeat", 0.0)
	controls.enabled = false
	controls.visible = false
	_over_timer = 0.4 if won else 2.6

## extra: a lost fawn that follows you once found
func _fawn_update(dt: float) -> void:
	var d := fawn.dist_to(player.position)
	var tier := Animal.TIER_NEAR if d < float(Cfg.v("anim_near")) else Animal.TIER_FAR
	fawn.set_tier(tier)
	if tier != Animal.TIER_NEAR: return
	if not fawn_found:
		fawn.play("eat")
		if d < 7.0 and player.alive:
			fawn_found = true
			hud.notify("You found a lost fawn. It will follow you.", 3)
			_achieve("fawn")
		return
	if d > 3.2 and player.alive:
		var spd := clampf((d - 2.0) * 2.0, 1.0, maxf(player.speed * 1.05, 4.0))
		fawn.step_to(player.pos2() - player.forward() * 1.8, spd, dt, 8.0)
		fawn.locomotion(fawn.speed)
	else:
		fawn.speed = 0.0
		fawn.play("eat" if player.action != "" else "idle")

## auto quality: step down when the game stays under 25 fps
func _fps_watch(delta: float) -> void:
	if not Cfg.auto_quality: return
	_fps_cool -= delta
	if _fps_cool > 0.0: return
	_fps_time += delta
	_fps_frames += 1
	if _fps_time >= 6.0:
		var fps := _fps_frames / _fps_time
		_fps_time = 0.0; _fps_frames = 0
		if fps < 25.0 and Cfg.lower_quality():
			_fps_cool = 15.0
			hud.notify("Graphics quality lowered to keep the game smooth.", 0)
