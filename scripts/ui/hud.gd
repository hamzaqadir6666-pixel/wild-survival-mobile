extends CanvasLayer
## The whole in-game HUD: health/stamina/ammo, objectives, prompts, notifications,
## minimap, journal, shop, pause + settings menus and the death screen.

signal panel_closed(which: String)


var root: Control
var vignette: ColorRect
var health_bar: ProgressBar
var stamina_bar: ProgressBar
var horse_bar: ProgressBar
var ammo_label: Label
var weapon_label: Label
var money_label: Label
var objective_label: Label
var interact_label: Label
var notify_box: VBoxContainer
var compass: Control
var minimap: Control
var death_overlay: ColorRect
var panel_layer: Control

var _open_panel := ""
var _paused := false
var _toast_tweens: Array[Tween] = []
var _health_tween: Tween
var _minimap_texture: ImageTexture
var _minimap_time := 0.0
var _wanted_icons: Array[Control] = []
var _font_cache: Dictionary = {}
var _ui_theme: Theme
var panels: Node


func _ready() -> void:
	add_to_group("hud")
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ui_theme = _make_theme()
	_build_ui()
	_install_panels()
	_connect_state()
	refresh_all()


func _exit_tree() -> void:
	# a scene change from the paused menu must not leave the tree frozen
	var tree := get_tree()
	if tree == null:
		return
	if tree.paused:
		tree.paused = false


func _connect_state() -> void:
	GameState.health_changed.connect(_on_health)
	GameState.stamina_changed.connect(_on_stamina)
	GameState.horse_stamina_changed.connect(_on_horse_stamina)
	GameState.ammo_changed.connect(_on_ammo)
	GameState.weapon_changed.connect(_on_weapon)
	GameState.money_changed.connect(_on_money)
	GameState.notification.connect(_on_notify)
	GameState.objective_changed.connect(_on_objective)
	GameState.wanted_level_changed.connect(_on_wanted)
	GameState.inventory_changed.connect(refresh_all)


## Serif display face for headings, clean serif for body copy. Both are libre
## fonts shipped in ui/fonts with system fallbacks.
func display_font() -> Font:
	if _font_cache.has("display"):
		return _font_cache["display"]
	var f: Font = null
	var path := "res://ui/fonts/display_serif.ttf"
	if ResourceLoader.exists(path):
		f = load(path)
	if f == null:
		var sf := SystemFont.new()
		sf.font_names = PackedStringArray(["Georgia", "DejaVu Serif", "Times New Roman", "serif"])
		sf.font_weight = 700
		f = sf
	_font_cache["display"] = f
	return f


func body_font() -> Font:
	if _font_cache.has("body"):
		return _font_cache["body"]
	var f: Font = null
	var path := "res://ui/fonts/body_serif.ttf"
	if ResourceLoader.exists(path):
		f = load(path)
	if f == null:
		var sf := SystemFont.new()
		sf.font_names = PackedStringArray(["DejaVu Serif", "Georgia", "Times New Roman", "serif"])
		f = sf
	_font_cache["body"] = f
	return f


func _make_theme() -> Theme:
	var th := Theme.new()
	th.default_font = body_font()
	th.default_font_size = 20
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.13, 0.105, 0.08, 0.94)
	normal.border_color = Color(0.46, 0.35, 0.19)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(2)
	normal.content_margin_left = 14
	normal.content_margin_right = 14
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	var hover := normal.duplicate()
	hover.bg_color = Color(0.28, 0.21, 0.13, 0.98)
	hover.border_color = Color(0.86, 0.68, 0.34)
	var pressed := normal.duplicate()
	pressed.bg_color = Color(0.4, 0.28, 0.15, 1.0)
	var focus := hover.duplicate()
	focus.draw_center = false
	focus.set_border_width_all(3)
	th.set_stylebox("normal", "Button", normal)
	th.set_stylebox("hover", "Button", hover)
	th.set_stylebox("pressed", "Button", pressed)
	th.set_stylebox("focus", "Button", focus)
	th.set_stylebox("disabled", "Button", normal)
	th.set_color("font_color", "Button", Color(0.95, 0.89, 0.74))
	th.set_color("font_hover_color", "Button", Color(1.0, 0.97, 0.86))
	th.set_color("font_disabled_color", "Button", Color(0.6, 0.55, 0.46))
	th.set_font("font", "Button", display_font())
	th.set_font_size("font_size", "Button", 21)
	th.set_font("font", "Label", body_font())
	return th


func _mk_label(text: String, size: int, color: Color = Color(0.93, 0.88, 0.76)) -> Label:
	var l := Label.new()
	l.text = text
	l.theme = _ui_theme
	l.add_theme_font_override("font", display_font() if size >= 30 else body_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.06, 0.05, 0.04))
	l.add_theme_constant_override("outline_size", 5)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 3)
	return l


func _mk_bar(fill: Color, width: float = 210.0, height: float = 13.0) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(width, height)
	bar.show_percentage = false
	bar.max_value = 100.0
	bar.value = 100.0
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.04, 0.03, 0.72)
	bg.border_color = Color(0.55, 0.42, 0.22, 0.9)
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("background", bg)
	var fg := StyleBoxFlat.new()
	fg.bg_color = fill
	fg.set_corner_radius_all(1)
	bar.add_theme_stylebox_override("fill", fg)
	return bar


func _build_ui() -> void:
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# film-grain / vignette that intensifies at low health
	vignette = ColorRect.new()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.color = Color(0.0, 0.0, 0.0, 0.0)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(vignette)

	# ---- bottom-left status ----
	var status := VBoxContainer.new()
	status.position = Vector2(36, 0)
	status.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	status.position = Vector2(36, -168)
	status.add_theme_constant_override("separation", 6)
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(status)
	var name_lbl := _mk_label(GameState.PLAYER_NAME, 20, Color(0.98, 0.9, 0.72))
	status.add_child(name_lbl)
	health_bar = _mk_bar(Color(0.62, 0.16, 0.12))
	status.add_child(health_bar)
	stamina_bar = _mk_bar(Color(0.78, 0.66, 0.28))
	status.add_child(stamina_bar)
	var horse_row := HBoxContainer.new()
	horse_row.add_theme_constant_override("separation", 8)
	status.add_child(horse_row)
	var hl := _mk_label("🐎", 15, Color(0.85, 0.75, 0.55))
	horse_row.add_child(hl)
	horse_bar = _mk_bar(Color(0.36, 0.5, 0.28), 178.0, 9.0)
	horse_row.add_child(horse_bar)

	# ---- bottom-right weapon / ammo ----
	var wbox := VBoxContainer.new()
	wbox.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	wbox.position = Vector2(-330, -150)
	wbox.custom_minimum_size = Vector2(290, 0)
	wbox.alignment = BoxContainer.ALIGNMENT_END
	wbox.add_theme_constant_override("separation", 2)
	wbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(wbox)
	weapon_label = _mk_label("Cattleman Revolver", 22, Color(0.97, 0.88, 0.66))
	weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	weapon_label.custom_minimum_size = Vector2(290, 0)
	wbox.add_child(weapon_label)
	ammo_label = _mk_label("6 / 48", 34, Color(0.99, 0.93, 0.76))
	ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ammo_label.custom_minimum_size = Vector2(290, 0)
	wbox.add_child(ammo_label)
	money_label = _mk_label("$42", 22, Color(0.72, 0.86, 0.62))
	money_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	money_label.custom_minimum_size = Vector2(290, 0)
	wbox.add_child(money_label)

	# ---- top-centre objective ----
	objective_label = _mk_label("", 19, Color(0.95, 0.9, 0.72))
	objective_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	objective_label.position = Vector2(-320, 24)
	objective_label.custom_minimum_size = Vector2(640, 0)
	objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(objective_label)

	# ---- compass strip ----
	compass = Control.new()
	compass.set_anchors_preset(Control.PRESET_CENTER_TOP)
	compass.position = Vector2(-260, 64)
	compass.custom_minimum_size = Vector2(520, 34)
	compass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	compass.draw.connect(_draw_compass)
	root.add_child(compass)

	# ---- minimap (top-right) ----
	minimap = Control.new()
	minimap.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	minimap.position = Vector2(-232, 22)
	minimap.custom_minimum_size = Vector2(206, 206)
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap.draw.connect(_draw_minimap)
	root.add_child(minimap)

	# ---- interaction prompt ----
	interact_label = _mk_label("", 22, Color(0.99, 0.94, 0.8))
	interact_label.set_anchors_preset(Control.PRESET_CENTER)
	interact_label.position = Vector2(-260, 96)
	interact_label.custom_minimum_size = Vector2(520, 0)
	interact_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(interact_label)

	# ---- notifications ----
	notify_box = VBoxContainer.new()
	notify_box.set_anchors_preset(Control.PRESET_TOP_LEFT)
	notify_box.position = Vector2(44, 74)
	notify_box.add_theme_constant_override("separation", 6)
	notify_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(notify_box)

	# ---- wanted stars ----
	var wrow := HBoxContainer.new()
	wrow.set_anchors_preset(Control.PRESET_TOP_LEFT)
	wrow.position = Vector2(40, 24)
	wrow.add_theme_constant_override("separation", 4)
	root.add_child(wrow)
	for i in 5:
		var s := _mk_label("★", 26, Color(0.25, 0.22, 0.18))
		wrow.add_child(s)
		_wanted_icons.append(s)

	# ---- death overlay ----
	death_overlay = ColorRect.new()
	death_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	death_overlay.color = Color(0.28, 0.02, 0.02, 0.0)
	death_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(death_overlay)
	var dl := _mk_label("YOU DIED", 72, Color(0.85, 0.16, 0.12))
	dl.set_anchors_preset(Control.PRESET_CENTER)
	dl.position = Vector2(-260, -60)
	dl.custom_minimum_size = Vector2(520, 0)
	dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dl.name = "DeathText"
	dl.modulate.a = 0.0
	death_overlay.add_child(dl)

	# ---- panel layer (journal / map / shop / pause) ----
	panel_layer = Control.new()
	panel_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(panel_layer)


func refresh_all() -> void:
	_on_health(GameState.health, GameState.max_health)
	_on_stamina(GameState.stamina, GameState.max_stamina)
	_on_horse_stamina(GameState.horse_stamina, GameState.max_horse_stamina)
	_on_money(GameState.money)
	_on_weapon(GameState.current_weapon)


func _process(delta: float) -> void:
	compass.queue_redraw()
	_minimap_time += delta
	if _minimap_time > 0.12:
		_minimap_time = 0.0
		minimap.queue_redraw()
	var h := GameState.health / maxf(1.0, GameState.max_health)
	vignette.color = Color(0.35, 0.0, 0.0, clampf((0.55 - h) * 0.9, 0.0, 0.5))


func _on_health(cur: float, maxv: float) -> void:
	health_bar.max_value = maxv
	# rapid hits would otherwise stack one tween per point of damage
	if _health_tween and _health_tween.is_valid():
		_health_tween.kill()
	_health_tween = create_tween()
	_health_tween.tween_property(health_bar, "value", cur, 0.25)


func _on_stamina(cur: float, maxv: float) -> void:
	stamina_bar.max_value = maxv
	stamina_bar.value = cur


func _on_horse_stamina(cur: float, maxv: float) -> void:
	horse_bar.max_value = maxv
	horse_bar.value = cur


func _on_ammo(_id: String, clip: int, reserve: int) -> void:
	ammo_label.text = "%d  /  %d" % [clip, reserve]
	ammo_label.add_theme_color_override("font_color", Color(0.85, 0.3, 0.22) if clip == 0 else Color(0.99, 0.93, 0.76))


func _on_weapon(id: String) -> void:
	var w: Dictionary = GameState.weapons.get(id, {})
	weapon_label.text = str(w.get("name", id))
	ammo_label.text = "%d  /  %d" % [int(w.get("clip", 0)), int(w.get("reserve", 0))]


func _on_money(v: int) -> void:
	money_label.text = "$%d" % v


func _on_objective(text: String) -> void:
	objective_label.text = text
	objective_label.modulate.a = 1.0 if text != "" else 0.0


func _on_wanted(level: int) -> void:
	for i in _wanted_icons.size():
		var l: Label = _wanted_icons[i]
		if i < level:
			l.add_theme_color_override("font_color", Color(0.95, 0.78, 0.25))
		else:
			l.add_theme_color_override("font_color", Color(0.22, 0.2, 0.17, 0.75))


func _on_notify(text: String, seconds: float) -> void:
	var l := _mk_label(text, 19, Color(0.97, 0.92, 0.78))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(420, 0)
	notify_box.add_child(l)
	l.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(l, "modulate:a", 1.0, 0.22)
	tw.tween_interval(maxf(0.8, seconds))
	tw.tween_property(l, "modulate:a", 0.0, 0.6)
	tw.tween_callback(l.queue_free)
	_toast_tweens.append(tw)
	if notify_box.get_child_count() > 6:
		var first := notify_box.get_child(0)
		first.queue_free()


## ---- overlay menus (pause / journal / map / shop / settings) ----
func _install_panels() -> void:
	if panel_layer.has_node("OverlayRoot/Menus"):
		return
	var overlay := Control.new()
	overlay.name = "OverlayRoot"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel_layer.add_child(overlay)
	var menus := Node.new()
	menus.name = "Menus"
	menus.set_script(load("res://scripts/ui/hud_panels.gd"))
	overlay.add_child(menus)
	menus.setup(self, overlay)
	panels = menus


func open_panel(which: String) -> void:
	if panels == null:
		_install_panels()
	if panels:
		panels.toggle(which)


func toggle_pause() -> void:
	if panels == null:
		_install_panels()
	if panels:
		panels.toggle("pause")


func open_shop(_npc: Node = null) -> void:
	if panels == null:
		_install_panels()
	if panels:
		panels.open("shop")


func panels_open() -> bool:
	return panels != null and panels.is_open()


func set_interact_prompt(text: String) -> void:
	interact_label.text = text


func show_death() -> void:
	death_overlay.color = Color(0.3, 0.02, 0.02, 0.55)
	var t := death_overlay.get_node_or_null("DeathText")
	if t:
		var tw := create_tween()
		tw.tween_property(t, "modulate:a", 1.0, 0.7)


func hide_death() -> void:
	death_overlay.color = Color(0.3, 0.02, 0.02, 0.0)
	var t := death_overlay.get_node_or_null("DeathText")
	if t:
		t.modulate.a = 0.0


## ---------------------------------------------------------------- compass ----
func _draw_compass() -> void:
	var w := 520.0
	var h := 34.0
	var cam := get_viewport().get_camera_3d()
	var cam_yaw := 0.0
	if cam:
		cam_yaw = fposmod(cam.global_rotation.y, TAU)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.04, 0.03, 0.32)
	bg.border_color = Color(0.6, 0.46, 0.24, 0.45)
	bg.set_border_width_all(1)
	compass.draw_style_box(bg, Rect2(0, 0, w, h))
	var px_per_deg := w / 180.0
	var headings := {"N": 0.0, "NE": -PI / 4.0, "E": -PI / 2.0, "SE": -3 * PI / 4.0, "S": PI, "SW": 3 * PI / 4.0, "W": PI / 2.0, "NW": PI / 4.0}
	var font := ThemeDB.fallback_font
	for key in headings.keys():
		var ang: float = headings[key]
		var delta := wrapf(ang - cam_yaw, -PI, PI)
		if absf(delta) > PI * 0.55:
			continue
		var x := w * 0.5 + delta * (w / (PI * 1.1))
		compass.draw_line(Vector2(x, h * 0.62), Vector2(x, h), Color(0.85, 0.78, 0.6, 0.85), 1.5)
		var col := Color(0.95, 0.85, 0.6, 0.95) if key == "N" else Color(0.8, 0.74, 0.6, 0.8)
		compass.draw_string(font, Vector2(x - (7 if key.length() == 1 else 11), h * 0.55), key,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, col)
	# objective marker
	var player := get_tree().get_first_node_in_group("player")
	var mm := get_tree().get_first_node_in_group("mission_manager")
	if player and mm and not mm.active.is_empty():
		for id in mm.active.keys():
			var m: Dictionary = mm.active[id]
			var idx: int = m["progress"]
			var objs: Array = m["objectives"]
			if idx >= objs.size():
				continue
			var o: Dictionary = objs[idx]
			if str(o["type"]) != "reach":
				continue
			var target: Vector3 = o["pos"]
			var to := target - player.global_position
			var ang2 := atan2(-to.x, -to.z)
			var delta2 := wrapf(ang2 - cam_yaw, -PI, PI)
			if absf(delta2) > PI * 0.55:
				continue
			var x2 := w * 0.5 + delta2 * (w / (PI * 1.1))
			compass.draw_circle(Vector2(x2, 7), 5.0, Color(0.98, 0.82, 0.3))


## ---------------------------------------------------------------- minimap ----
func _draw_minimap() -> void:
	var s := 206.0
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.06, 0.08, 0.06, 0.62)
	bg.border_color = Color(0.62, 0.48, 0.26, 0.85)
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(4)
	minimap.draw_style_box(bg, Rect2(0, 0, s, s))
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var center := Vector2(player.global_position.x, player.global_position.z)
	var scale := s / 240.0   # metres shown across the minimap
	var font := ThemeDB.fallback_font
	# water bodies
	var world := get_tree().get_first_node_in_group("world")
	if world and world.terrain:
		var t = world.terrain
		if t.get("lake_center") != null:
			var lc: Vector2 = t.lake_center
			var lp := Vector2(s * 0.5, s * 0.5) + (lc - center) * scale
			minimap.draw_circle(lp, 34.0 * scale, Color(0.2, 0.38, 0.5, 0.8))
		if t.get("river_points") != null:
			var pts: PackedVector2Array = t.river_points
			var prev := Vector2.ZERO
			var first := true
			for p in pts:
				var q := Vector2(s * 0.5, s * 0.5) + (p - center) * scale
				if not first:
					minimap.draw_line(prev, q, Color(0.24, 0.44, 0.56, 0.85), 3.0)
				prev = q
				first = false
	# town
	for t in get_tree().get_nodes_in_group("town"):
		var tp := Vector2(s * 0.5, s * 0.5) + (Vector2(t.global_position.x, t.global_position.z) - center) * scale
		minimap.draw_rect(Rect2(tp - Vector2(6, 6), Vector2(12, 12)), Color(0.78, 0.6, 0.32, 0.9))
		minimap.draw_string(font, tp + Vector2(8, 5), "Dustwater", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.95, 0.9, 0.75))
	for bc in get_tree().get_nodes_in_group("bandit_camp"):
		var bp := Vector2(s * 0.5, s * 0.5) + (Vector2(bc.global_position.x, bc.global_position.z) - center) * scale
		minimap.draw_circle(bp, 5.0, Color(0.72, 0.14, 0.12))
	for a in get_tree().get_nodes_in_group("animals"):
		if not (a is Node3D):
			continue
		var ap := Vector2(s * 0.5, s * 0.5) + (Vector2(a.global_position.x, a.global_position.z) - center) * scale
		minimap.draw_circle(ap, 1.6, Color(0.85, 0.8, 0.55, 0.7))
	for n in get_tree().get_nodes_in_group("npcs"):
		if not (n is Node3D):
			continue
		var np := Vector2(s * 0.5, s * 0.5) + (Vector2(n.global_position.x, n.global_position.z) - center) * scale
		minimap.draw_circle(np, 2.0, Color(0.7, 0.85, 0.95, 0.75))
	for mk in get_tree().get_nodes_in_group("mission_markers"):
		if not (mk is Node3D):
			continue
		var mp := Vector2(s * 0.5, s * 0.5) + (Vector2(mk.global_position.x, mk.global_position.z) - center) * scale
		minimap.draw_circle(mp, 4.5, Color(0.98, 0.84, 0.3))
	# player arrow
	var c := Vector2(s * 0.5, s * 0.5)
	var dir := Vector2(0, 1).rotated(-player.get("yaw") if player.get("yaw") != null else 0.0)
	var p1 := c + dir * 8.0
	var p2 := c + dir.rotated(2.5) * 6.0
	var p3 := c + dir.rotated(-2.5) * 6.0
	minimap.draw_colored_polygon(PackedVector2Array([p1, p2, p3]), Color(0.98, 0.95, 0.8))
