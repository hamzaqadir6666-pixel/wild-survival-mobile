class_name Menus
extends Control
## All full-screen menus. Each screen is built when it is opened and freed when closed.

var game: Node
var current := ""
var screen := Vector2(1280, 720)
var safe := Rect2(0, 0, 1280, 720)
var _root: Control = null
var _tutorial_page := 0

const HOWTO := [
	["sprint", "Move with the left stick. Drag the right half of the screen to look around. Hold SPRINT to run - it drains stamina."],
	["leaf", "Keep four bars up: health, stamina, food and water. Stand on grass and press the leaf button to graze, stand at a shore to drink."],
	["eye", "Hunters find you by sight, sound and distance. SAFE: nobody knows. WATCHED: something noticed you. HUNTED: run!"],
	["sneak", "SNEAK makes you quiet and hard to see. Thick bushes marked on the map are safe thickets - no hunter follows you inside."],
	["wave", "A hunter that sees you does not give up: get out of sight. Swim into deep water (crocodiles still see you) or stand inside a bush until HIDDEN appears."],
	["clover", "Glowing rare plants give permanent abilities: speed, night vision, health, stamina, silent steps and more. Red toadstools are poison."],
	["flag", "Finish the goals at the top of the screen to complete a level. Find landmarks and thickets for bonuses."],
]

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func layout(p_screen: Vector2, p_safe: Rect2) -> void:
	screen = p_screen
	safe = p_safe
	if current != "": open(current)

func close() -> void:
	if _root: _root.queue_free()
	_root = null
	current = ""

func is_open() -> bool:
	return current != ""

func open(name: String) -> void:
	if _root:
		_root.queue_free()
		_root = null
	current = name
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.05, 0.03, 0.55 if name == "main" else 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)
	call("_build_" + name)

## centred panel with a title; returns the box to fill
func _frame(title: String, width := 560.0, scroll := false) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", int(safe.position.x + 16))
	margin.add_theme_constant_override("margin_right", int(screen.x - safe.end.x + 16))
	margin.add_theme_constant_override("margin_top", int(safe.position.y + 12))
	margin.add_theme_constant_override("margin_bottom", int(screen.y - safe.end.y + 12))
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(margin)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(center)
	var p := UI.panel(Color(0.06, 0.10, 0.07, 0.93), 16, 16)
	p.custom_minimum_size.x = minf(width, safe.size.x - 40.0)
	center.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	var t := UI.label(title, 30, UI.GOLD)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	if not scroll: return v
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(p.custom_minimum_size.x - 32.0, minf(safe.size.y - 190.0, 470.0))
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 8)
	sc.add_child(inner)
	inner.set_meta("outer", v)
	return inner

func _row(parent: Control) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	parent.add_child(h)
	return h

func _text(parent: Control, text: String, size := 17, color := Color.WHITE, width := 0.0) -> Label:
	var l := UI.label(text, size, color)
	if width > 0.0:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = width
	parent.add_child(l)
	return l

func _back(parent: Control, to: String) -> void:
	var outer: Control = parent.get_meta("outer") if parent.has_meta("outer") else parent
	var h := _row(outer)
	h.add_child(UI.button("Back", func(): _go_back(to), 20, Vector2(200, 58), "back"))

func _go_back(to: String) -> void:
	if to == "": game.resume()
	else: open(to)

func back_pressed() -> void:
	## Android back button / Escape
	match current:
		"main": pass
		"levels", "howto", "stats", "achievements", "guide": open("main" if not game.in_run() else "pause")
		"settings": open("main" if not game.in_run() else "pause")
		"pause", "map": game.resume()
		"tutorial": pass
		"gameover", "complete": game.to_menu()

## closes the game (progress is saved first)
func exit_game() -> void:
	Save.store()
	get_tree().quit()

# ---------------------------------------------------------------- main menu
func _build_main() -> void:
	var v := _frame("WILD SURVIVAL", 520.0)
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 10)
	g.add_theme_constant_override("v_separation", 8)
	v.add_child(g)
	var lvl := mini(int(Save.d.unlocked), D.LEVELS.size())
	var sz := Vector2(244, 58)
	g.add_child(UI.button("Continue: Level %d" % lvl, func(): game.start_level(lvl - 1), 21, sz, "play"))
	g.add_child(UI.button("Level select", func(): open("levels"), 21, sz, "flag"))
	g.add_child(UI.button("Endless mode", func(): game.start_endless(), 21, sz, "clock"))
	g.add_child(UI.button("How to play", func(): open("howto"), 21, sz, "eye"))
	g.add_child(UI.button("Animal & plant guide", func(): open("guide"), 19, sz, "leaf"))
	g.add_child(UI.button("Statistics", func(): open("stats"), 21, sz, "star"))
	g.add_child(UI.button("Achievements", func(): open("achievements"), 21, sz, "shield"))
	g.add_child(UI.button("Settings", func(): open("settings"), 21, sz, "gear"))
	var hx := _row(v)
	hx.add_child(UI.button("Exit game", exit_game, 21, sz, "back"))
	var cr := _text(v, "Elk model: WildMesh 3D (CC BY 4.0)  -  Music: Kevin MacLeod, incompetech.com (CC BY 4.0)  -  more in CREDITS.md", 11, Color(0.8, 0.85, 0.8), 500.0); cr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var best := float(Save.d.best_endless)
	if best > 0.0:
		var b := _text(v, "Endless best: %s" % D.fmt_time(best), 16, UI.GOLD); b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _build_levels() -> void:
	var v := _frame("LEVELS", 640.0)
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", 10)
	g.add_theme_constant_override("v_separation", 10)
	v.add_child(g)
	for i in D.LEVELS.size():
		var L: Dictionary = D.LEVELS[i]
		var open_ := i < int(Save.d.unlocked)
		var txt := "Level %d\n%s  +%d plants\n%d hunters" % [i + 1, D.fmt_time(L.time), L.plants, D.hunter_total(L)]
		var idx := i
		var b := UI.button(txt if open_ else "Level %d\nlocked" % (i + 1), func(): game.start_level(idx), 15, Vector2(144, 96), "" if open_ else "lock")
		b.disabled = not open_
		g.add_child(b)
	_text(v, "Abilities from rare plants are kept between levels.", 15, Color(0.8, 0.95, 0.8)).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_back(v, "main")

func _build_howto() -> void:
	var v := _frame("HOW TO PLAY", 760.0, true)
	for e in HOWTO:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 12)
		v.add_child(h)
		h.add_child(UI.icon_rect(e[0], 40.0, UI.GOLD))
		_text(h, e[1], 17, Color.WHITE, 640.0)
	_text(v, "Keyboard (desktop): WASD move, Shift sprint, C sneak, Space jump, E eat/drink, M map, Esc pause.", 14, Color(0.75, 0.8, 0.75), 690.0)
	_back(v, "main" if not game.in_run() else "pause")

# ---------------------------------------------------------------- settings
func _build_settings() -> void:
	var v := _frame("SETTINGS", 760.0, true)
	var h := _row(v)
	_text(h, "Quality", 18).custom_minimum_size.x = 150
	for i in Cfg.PRESETS.size():
		var idx := i
		var b := UI.button(Cfg.PRESETS[i].name, func():
			Cfg.set_preset(idx)
			open("settings"), 18, Vector2(130, 54))
		if i == Cfg.preset: b.add_theme_stylebox_override("normal", UI.box(Color(0.35, 0.55, 0.25, 1.0), 12, 10))
		h.add_child(b)
	_toggle(v, "Auto quality (lower when under 25 fps)", Cfg.auto_quality, func(on):
		Cfg.auto_quality = on
		Cfg.save_file())
	var h2 := _row(v)
	_text(h2, "Frame limit", 18).custom_minimum_size.x = 150
	for f in [30, 60]:
		var fv: int = f
		var b2 := UI.button("%d fps" % f, func():
			Cfg.set_over("fps", fv)
			open("settings"), 18, Vector2(130, 54))
		if int(Cfg.v("fps")) == f: b2.add_theme_stylebox_override("normal", UI.box(Color(0.35, 0.55, 0.25, 1.0), 12, 10))
		h2.add_child(b2)
	_toggle(v, "Shadows", bool(Cfg.v("shadows")), func(on): Cfg.set_over("shadows", on))
	_slider(v, "Render resolution", 0.5, 1.0, 0.05, float(Cfg.v("scale")), func(x): Cfg.set_over("scale", x), true)
	_slider(v, "Grass amount", 0.0, 1.0, 0.05, float(Cfg.v("grass")), func(x): Cfg.set_over("grass", x), true)
	_slider(v, "View distance (m)", 120.0, 300.0, 10.0, float(Cfg.v("view")), func(x): Cfg.set_over("view", x), false)
	for k in ["master", "music", "sfx", "ambience"]:
		var key: String = k
		_slider(v, {"master": "Master volume", "music": "Music volume", "sfx": "Effects volume", "ambience": "Ambience volume"}[k], 0.0, 1.0, 0.05, float(Cfg.vol[k]), func(x):
			Cfg.vol[key] = x
			Cfg.save_file()
			Sfx.apply_volumes(), true)
	_slider(v, "Touch sensitivity", 0.3, 2.5, 0.1, Cfg.sensitivity, func(x):
		Cfg.sensitivity = x
		Cfg.save_file(), false)
	_toggle(v, "Invert camera (up / down)", Cfg.invert, func(on):
		Cfg.invert = on
		Cfg.save_file())
	_slider(v, "Camera distance", 4.0, 10.0, 0.5, Cfg.cam_dist, func(x):
		Cfg.cam_dist = x
		Cfg.save_file(), false)
	_back(v, "main" if not game.in_run() else "pause")

func _toggle(parent: Control, text: String, on: bool, cb: Callable) -> void:
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = on
	c.focus_mode = Control.FOCUS_NONE
	c.custom_minimum_size.y = 52
	c.add_theme_font_size_override("font_size", 18)
	c.toggled.connect(func(v):
		Sfx.click()
		cb.call(v))
	parent.add_child(c)

func _slider(parent: Control, text: String, lo: float, hi: float, step: float, value: float, cb: Callable, percent: bool) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	parent.add_child(h)
	var l := _text(h, text, 18); l.custom_minimum_size.x = 250
	var s := HSlider.new()
	s.min_value = lo; s.max_value = hi; s.step = step; s.value = value
	s.custom_minimum_size = Vector2(300, 52)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.focus_mode = Control.FOCUS_NONE
	h.add_child(s)
	var val := _text(h, "", 17, UI.GOLD); val.custom_minimum_size.x = 64
	var show := func(x: float): val.text = ("%d%%" % int(round(x * 100.0))) if percent else ("%.1f" % x if hi < 20.0 else "%d" % int(x))
	show.call(value)
	s.value_changed.connect(func(x):
		show.call(x)
		cb.call(x))

# ---------------------------------------------------------------- pause, results
func _build_pause() -> void:
	var v := _frame("PAUSED", 420.0)
	_text(v, game.goal_text(), 17, Color(1, 0.93, 0.7)).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for e in [["Resume", "play", func(): game.resume()], ["Settings", "gear", func(): open("settings")], ["How to play", "eye", func(): open("howto")],
			["Restart", "back", func(): game.restart()], ["Main menu", "flag", func(): game.to_menu()]]:
		var h := _row(v)
		h.add_child(UI.button(e[0], e[2], 21, Vector2(300, 58), e[1]))

func _build_map() -> void:
	var v := _frame("MAP", 100.0)
	var side := minf(safe.size.y - 190.0, 520.0)
	var m := Minimap.new()
	m.game = game
	m.full = true
	m.custom_minimum_size = Vector2(side, side)
	var h := _row(v)
	h.add_child(m)
	var leg := VBoxContainer.new()
	leg.add_theme_constant_override("separation", 6)
	h.add_child(leg)
	_text(leg, "Discoveries %d / %d" % [game.discoveries(), D.DISCOVERY_TOTAL], 17, UI.GOLD)
	_text(leg, "Wildlife seen %d / %d" % [game.fauna.seen_count(), D.WILDLIFE_TOTAL], 17)
	_text(leg, "White arrow: you\nGreen ring: safe thicket\nStar: landmark\nDots: rare plants you passed", 15, Color(0.85, 0.9, 0.85))
	leg.add_child(UI.button("Close", func(): game.resume(), 20, Vector2(190, 60), "back"))

func _build_gameover() -> void:
	var r: Dictionary = game.result
	var v := _frame("YOU DIED", 520.0)
	_text(v, "Cause: %s" % r.cause, 22, UI.RED).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stats_block(v, r)
	var h := _row(v)
	h.add_child(UI.button("Try again", func(): game.restart(), 21, Vector2(220, 62), "play"))
	h.add_child(UI.button("Main menu", func(): game.to_menu(), 21, Vector2(220, 62), "flag"))

func _build_complete() -> void:
	var r: Dictionary = game.result
	var v := _frame("LEVEL %d COMPLETE" % (int(r.level) + 1), 540.0)
	_stats_block(v, r)
	var h := _row(v)
	if int(r.level) + 1 < D.LEVELS.size():
		h.add_child(UI.button("Next level", func(): game.start_level(int(r.level) + 1), 21, Vector2(220, 62), "play"))
	else:
		_text(v, "You finished the whole campaign!", 20, UI.GOLD).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	h.add_child(UI.button("Main menu", func(): game.to_menu(), 21, Vector2(220, 62), "flag"))

func _stats_block(v: Control, r: Dictionary) -> void:
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 30)
	v.add_child(g)
	var rows := [["Time survived", D.fmt_time(r.time)], ["Days", str(r.day)], ["Escapes", str(r.escapes)], ["Rare plants eaten", str(r.plants)],
		["Discoveries", "%d / %d" % [r.discoveries, D.DISCOVERY_TOTAL]], ["Wildlife seen", "%d / %d" % [r.wildlife, D.WILDLIFE_TOTAL]]]
	if r.endless: rows.append(["Best endless time", D.fmt_time(r.best)])
	for e in rows:
		_text(g, e[0], 18, Color(0.85, 0.9, 0.85)).custom_minimum_size.x = 250
		_text(g, e[1], 18, UI.GOLD)

# ---------------------------------------------------------------- extras
func _build_stats() -> void:
	var v := _frame("STATISTICS", 520.0)
	var s: Dictionary = Save.d.stats
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 30)
	v.add_child(g)
	for e in [["Games played", str(int(s.games))], ["Longest survival", D.fmt_time(s.best_time)], ["Endless best", D.fmt_time(Save.d.best_endless)], ["Escapes", str(int(s.escapes))],
			["Rare plants eaten", str(int(s.plants))], ["Levels completed", str(int(s.levels_done))], ["Nights survived", str(int(s.nights))], ["Deaths", str(int(s.deaths))],
			["Swift Clover speed", "%d%%" % int(round((0.8 + 0.035 * mini(Save.ability("clover"), D.CLOVER_MAX)) * 100.0))]]:
		_text(g, e[0], 18, Color(0.85, 0.9, 0.85)).custom_minimum_size.x = 260
		_text(g, e[1], 18, UI.GOLD)
	_back(v, "main")

func _build_achievements() -> void:
	var v := _frame("ACHIEVEMENTS", 640.0, true)
	for key in D.ACHIEVEMENTS:
		var got: bool = Save.d.ach.has(key)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 12)
		v.add_child(h)
		h.add_child(UI.icon_rect("star" if got else "lock", 34.0, UI.GOLD if got else Color(0.5, 0.5, 0.5)))
		var col := VBoxContainer.new()
		h.add_child(col)
		_text(col, D.ACHIEVEMENTS[key][0], 19, UI.GOLD if got else Color(0.7, 0.7, 0.7))
		_text(col, D.ACHIEVEMENTS[key][1], 15, Color(0.85, 0.9, 0.85))
	_back(v, "main")

func _build_guide() -> void:
	var v := _frame("GUIDE", 760.0, true)
	_text(v, "Animals (shown once you have seen them)", 18, UI.GOLD)
	for sp in D.WILDLIFE_ORDER:
		var seen: bool = Save.d.seen.has(sp)
		var c: Dictionary = D.SPECIES[sp]
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		v.add_child(h)
		h.add_child(UI.icon_rect("paw", 26.0, (UI.RED if c.get("kind", "") == "predator" else UI.GREEN) if seen else Color(0.4, 0.4, 0.4)))
		_text(h, ("%s - %s" % [c.name, c.info]) if seen else "???", 16, Color.WHITE if seen else Color(0.6, 0.6, 0.6), 650.0)
	_text(v, "Rare plants (shown once you have eaten one)", 18, UI.GOLD)
	for t in D.PLANT_ORDER:
		var found: bool = Save.d.plants_found.has(t)
		var pd: Dictionary = D.PLANTS[t]
		var h2 := HBoxContainer.new()
		h2.add_theme_constant_override("separation", 10)
		v.add_child(h2)
		var ic: String = Hud.ABILITY_ICON.get(t, Hud.PLANT_ICON.get(t, "leaf"))
		h2.add_child(UI.icon_rect(ic, 26.0, pd.glow if found else Color(0.4, 0.4, 0.4)))
		_text(h2, ("%s - %s" % [pd.name, pd.text]) if found else "???", 16, Color.WHITE if found else Color(0.6, 0.6, 0.6), 650.0)
	_back(v, "main")

func _build_tutorial() -> void:
	var pages: Array = HOWTO
	var e: Array = pages[_tutorial_page]
	var v := _frame("WELCOME TO THE WILD  (%d / %d)" % [_tutorial_page + 1, pages.size()], 640.0)
	var h := _row(v)
	h.add_child(UI.icon_rect(e[0], 64.0, UI.GOLD))
	_text(h, e[1], 19, Color.WHITE, 480.0)
	var h2 := _row(v)
	h2.add_child(UI.button("Skip", func(): _tutorial_done(), 19, Vector2(170, 58)))
	h2.add_child(UI.button("Next" if _tutorial_page < pages.size() - 1 else "Start", func():
		_tutorial_page += 1
		if _tutorial_page >= pages.size(): _tutorial_done()
		else: open("tutorial"), 21, Vector2(220, 58), "play"))

func start_tutorial() -> void:
	_tutorial_page = 0
	open("tutorial")

func _tutorial_done() -> void:
	Save.d.tutorial_done = true
	Save.store()
	game.resume()
