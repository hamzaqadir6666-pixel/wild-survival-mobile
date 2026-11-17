extends Node
## Overlay menus: pause, journal, world map, shop, settings and controls.
## Built procedurally so the panels adapt to any resolution and share the HUD theme.

signal closed
signal resumed

const GOLD := Color(0.83, 0.67, 0.32)
const PARCH := Color(0.93, 0.87, 0.72)

var hud: CanvasLayer
var host: Control
var current := ""
var _built_for := ""


func setup(hud_layer: CanvasLayer, host_control: Control) -> void:
	hud = hud_layer
	host = host_control


func font_display() -> Font:
	return hud.display_font() if hud and hud.has_method("display_font") else ThemeDB.fallback_font


func font_body() -> Font:
	return hud.body_font() if hud and hud.has_method("body_font") else ThemeDB.fallback_font


func _label(text: String, size: int, color: Color = PARCH) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font_display() if size >= 30 else font_body())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.05, 0.035, 0.02))
	l.add_theme_constant_override("outline_size", 5)
	return l


func _button(parent: Control, text: String, pos: Vector2, size: Vector2, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = size
	b.custom_minimum_size = size
	b.add_theme_font_override("font", font_display())
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(func() -> void:
		AudioManager.play_sfx("ui_click", 1.0, -6.0)
		cb.call())
	parent.add_child(b)
	return b


func is_open() -> bool:
	return current != ""


func toggle(which: String) -> void:
	if current == which:
		close()
	else:
		open(which)


func open(which: String) -> void:
	_clear()
	current = which
	if hud == null:
		return
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var frame := Control.new()
	frame.name = "Panel_" + which
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.add_child(frame)
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.03, 0.025, 0.02, 0.82)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	frame.add_child(shade)
	var board := Panel.new()
	board.name = "Board"
	board.set_anchors_preset(Control.PRESET_FULL_RECT)
	board.offset_left = 96
	board.offset_top = 58
	board.offset_right = -96
	board.offset_bottom = -58
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.115, 0.093, 0.068, 0.97)
	sb.border_color = GOLD
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(4)
	sb.shadow_color = Color(0, 0, 0, 0.65)
	sb.shadow_size = 30
	board.add_theme_stylebox_override("panel", sb)
	frame.add_child(board)
	match which:
		"journal":
			_build_journal(board)
		"map":
			_build_map(board)
		"shop":
			_build_shop(board)
		"settings":
			_build_settings(board)
		"controls":
			_build_controls(board)
		_:
			_build_pause(board)


func _clear() -> void:
	if host:
		for c in host.get_children():
			# only ever remove the panel frames this manager created
			if c != self and str(c.name).begins_with("Panel_"):
				c.queue_free()
	current = ""


func close() -> void:
	_clear()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if current == "":
		return
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		close()
	elif event.is_action_pressed("map") and current == "map":
		get_viewport().set_input_as_handled()
		close()
	elif event.is_action_pressed("journal") and current == "journal":
		get_viewport().set_input_as_handled()
		close()


func _title(board: Control, text: String, subtitle: String = "") -> void:
	var t := _label(text, 38, Color(0.97, 0.89, 0.7))
	t.position = Vector2(46, 24)
	board.add_child(t)
	if subtitle != "":
		var s := _label(subtitle, 16, Color(0.72, 0.64, 0.5))
		s.position = Vector2(50, 76)
		board.add_child(s)
	var line := ColorRect.new()
	line.color = Color(GOLD.r, GOLD.g, GOLD.b, 0.55)
	line.position = Vector2(48, 70 if subtitle == "" else 100)
	line.size = Vector2(board.size.x - 96, 2)
	line.anchor_right = 1.0
	line.offset_left = 48
	line.offset_right = -48
	board.add_child(line)


func _clock() -> String:
	var h := int(GameState.world_time / 3600.0) % 24
	var m := int((GameState.world_time / 60.0) % 60.0)
	return "%02d:%02d" % [h, m]


func _build_pause(board: Control) -> void:
	_title(board, "DUST & IRON", "Red Hollow Territory — Day %d, %s" % [GameState.day, _clock()])
	var x := 56.0
	var y := 150.0
	_button(board, "Resume", Vector2(x, y), Vector2(320, 50), close)
	_button(board, "Journal", Vector2(x, y + 60), Vector2(320, 50), func() -> void: open("journal"))
	_button(board, "World Map", Vector2(x, y + 120), Vector2(320, 50), func() -> void: open("map"))
	_button(board, "Settings", Vector2(x, y + 180), Vector2(320, 50), func() -> void: open("settings"))
	_button(board, "Controls", Vector2(x, y + 240), Vector2(320, 50), func() -> void: open("controls"))
	_button(board, "Save Game", Vector2(x, y + 300), Vector2(320, 50), func() -> void:
		var ok := SaveSystem.save_game(0)
		GameState.notify("Progress saved." if ok else "Save failed.", 2.5)
		close())
	_button(board, "Quit to Title", Vector2(x, y + 360), Vector2(320, 50), func() -> void:
		get_tree().paused = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn"))
	var hunted := 0
	for k in GameState.hunting_scores.keys():
		hunted += int(GameState.hunting_scores[k])
	var info := _label("%s   ·   $%d\nMissions complete: %d\nRelics recovered: %d / 12\nAnimals hunted: %d\nBounty: %d star%s" % [
		GameState.PLAYER_NAME, GameState.money, GameState.completed_missions.size(),
		GameState.collectibles.size(), hunted, GameState.wanted_level,
		"" if GameState.wanted_level == 1 else "s"], 19, Color(0.82, 0.76, 0.62))
	info.position = Vector2(430, 156)
	board.add_child(info)
	var tip := _label("Tip: hold SHIFT to sprint, tap E beside Juniper to ride, and whistle with F if she wanders off.", 16, Color(0.6, 0.55, 0.45))
	tip.position = Vector2(430, 320)
	tip.custom_minimum_size = Vector2(420, 0)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	board.add_child(tip)


func _build_journal(board: Control) -> void:
	_title(board, "JOURNAL", "Tasks, satchel and the hunting ledger")
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(48, 112)
	scroll.size = Vector2(board.size.x - 96, board.size.y - 200)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	board.add_child(scroll)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	box.add_child(_label("TASKS", 24, GOLD))
	var mm := get_tree().get_first_node_in_group("mission_manager")
	var listed := 0
	if mm and mm.has_method("mission_list"):
		for m in mm.mission_list():
			var status := str(m.get("status", "available"))
			var tag := "  ·  In progress" if status == "active" else ("  ·  Done" if status == "complete" else "  ·  Not started")
			var col := Color(0.96, 0.89, 0.7) if status == "active" else (Color(0.55, 0.62, 0.5) if status == "complete" else Color(0.72, 0.68, 0.58))
			box.add_child(_label("%s — %s%s" % [str(m.get("title", "")), str(m.get("giver", "")), tag], 21, col))
			var d := _label(str(m.get("desc", "")), 17, Color(0.7, 0.66, 0.56))
			d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			d.custom_minimum_size = Vector2(board.size.x - 200, 0)
			box.add_child(d)
			listed += 1
	if listed == 0:
		box.add_child(_label("No tasks yet. Follow the golden beacons in Dustwater to find work.", 18, Color(0.7, 0.66, 0.56)))
	box.add_child(_label("SATCHEL", 24, GOLD))
	var weapons_text := ""
	for id in GameState.weapon_order:
		var w: Dictionary = GameState.weapons.get(id, {})
		weapons_text += "  ·  %s — %d / %d rounds\n" % [str(w.get("name", id)), int(w.get("clip", 0)), int(w.get("reserve", 0))]
	box.add_child(_label(weapons_text if weapons_text != "" else "  ·  Empty", 19, Color(0.86, 0.82, 0.7)))
	box.add_child(_label("HUNTING LEDGER", 24, GOLD))
	var ledger := ""
	if GameState.hunting_scores.is_empty():
		ledger = "  No animals brought down yet.\n"
	else:
		for k in GameState.hunting_scores.keys():
			ledger += "  ·  %s — %d taken\n" % [str(k), int(GameState.hunting_scores[k])]
	box.add_child(_label(ledger, 19, Color(0.8, 0.78, 0.66)))
	_button(board, "Close", Vector2(board.size.x - 210, board.size.y - 72), Vector2(160, 46), close)


func _build_map(board: Control) -> void:
	_title(board, "RED HOLLOW TERRITORY", "Terrain, water, roads, camps and landmarks")
	var map := Control.new()
	map.name = "MapCanvas"
	map.position = Vector2(48, 118)
	map.size = Vector2(board.size.x - 96, board.size.y - 200)
	map.clip_contents = true
	map.draw.connect(func() -> void: _draw_world_map(map))
	board.add_child(map)
	map.set_meta("draw_ready", true)
	_button(board, "Close", Vector2(board.size.x - 210, board.size.y - 72), Vector2(160, 46), close)


func _map_transform(size: Vector2) -> Array:
	var extent := 576.0
	var s: float = minf(size.x, size.y) / extent
	var origin := Vector2(size.x * 0.5 - extent * 0.5 * s, size.y * 0.5 - extent * 0.5 * s)
	return [origin, s, extent]


func _draw_world_map(map: Control) -> void:
	var size := map.size
	var tr := _map_transform(size)
	var origin: Vector2 = tr[0]
	var s: float = tr[1]
	var extent: float = tr[2]
	var world := get_tree().get_first_node_in_group("world")
	# parchment base
	map.draw_rect(Rect2(origin, Vector2(extent, extent) * s), Color(0.19, 0.17, 0.12))
	var terrain = world.terrain if world and "terrain" in world else null
	var font := font_body()
	if terrain and terrain.has_method("height_at") and terrain.has_method("biome_at"):
		var steps := 46
		var cell := extent / steps
		var rocks: Array[Vector3] = []
		for i in steps:
			for j in steps:
				var wx := -extent * 0.5 + (i + 0.5) * cell
				var wz := -extent * 0.5 + (j + 0.5) * cell
				var hh: float = terrain.height_at(wx, wz)
				var b: Dictionary = terrain.biome_at(wx, wz)
				var col := Color(0.26, 0.31, 0.16)
				col = col.lerp(Color(0.55, 0.47, 0.26), clampf(float(b["desert"]) * 1.1, 0.0, 1.0))
				col = col.lerp(Color(0.15, 0.23, 0.13), clampf(float(b["forest"]) * 0.75, 0.0, 1.0))
				col = col.lerp(Color(0.42, 0.4, 0.36), clampf(float(b["rock"]) * 0.95, 0.0, 1.0))
				col = col.lerp(Color(0.85, 0.86, 0.88), clampf((hh - 95.0) / 70.0, 0.0, 1.0))
				if hh < 2.2:
					col = Color(0.19, 0.35, 0.46)
				var cell_rect := Rect2(origin + Vector2(i, j) * cell * s, Vector2(cell, cell) * s + Vector2(1.5, 1.5))
				map.draw_rect(cell_rect, col)
				if hh > 105.0 and i % 3 == 0 and j % 3 == 0:
					rocks.append(Vector3(origin.x + (i + 0.5) * cell * s, origin.y + (j + 0.5) * cell * s, hh))
		# mountain hatching
		for r in rocks:
			var p := Vector2(r.x, r.y)
			map.draw_line(p + Vector2(-3, 3), p + Vector2(0, -3), Color(0.72, 0.7, 0.66, 0.7), 1.5)
			map.draw_line(p + Vector2(0, -3), p + Vector2(3, 3), Color(0.72, 0.7, 0.66, 0.7), 1.5)
		# river
		if "river_points" in terrain:
			var pts: PackedVector2Array = terrain.river_points
			var prev := Vector2.ZERO
			var first := true
			for p in pts:
				var q := origin + (p + Vector2(extent, extent) * 0.5) * s
				if not first:
					map.draw_line(prev, q, Color(0.34, 0.55, 0.68), 3.0)
				prev = q
				first = false
		# road from town to ranch
		var town_pt := origin + (Vector2(-34, -14) + Vector2(extent, extent) * 0.5) * s
		var ranch_pt := origin + (Vector2(96, 34) + Vector2(extent, extent) * 0.5) * s
		var mine_pt := origin + (Vector2(210, -60) + Vector2(extent, extent) * 0.5) * s
		var gulch_pt := origin + (Vector2(170, -190) + Vector2(extent, extent) * 0.5) * s
		map.draw_dashed_line(town_pt, ranch_pt, Color(0.55, 0.45, 0.28, 0.9), 2.0, 6.0)
		map.draw_dashed_line(town_pt, mine_pt, Color(0.55, 0.45, 0.28, 0.7), 2.0, 6.0)
		map.draw_dashed_line(town_pt, gulch_pt, Color(0.55, 0.45, 0.28, 0.55), 2.0, 6.0)
	# points of interest
	if world and world.has_method("points_of_interest"):
		for poi in world.points_of_interest():
			var p: Vector3 = poi["pos"]
			var q := origin + (Vector2(p.x, p.z) + Vector2(extent, extent) * 0.5) * s
			var kind := str(poi["kind"])
			var col := Color(0.9, 0.86, 0.78)
			var rad := 4.5
			match kind:
				"bandit":
					col = Color(0.78, 0.16, 0.12)
					rad = 6.0
				"camp":
					col = Color(0.85, 0.58, 0.24)
				"mission":
					col = Color(0.97, 0.82, 0.3)
					rad = 6.0
				"mine":
					col = Color(0.62, 0.6, 0.58)
				"waterfall":
					col = Color(0.55, 0.75, 0.9)
				"ruin":
					col = Color(0.68, 0.66, 0.62)
			map.draw_circle(q, rad, col)
			map.draw_circle(q, rad, Color(0.08, 0.06, 0.04, 0.8), false, 1.0)
			map.draw_string(font, q + Vector2(9, 4), str(poi["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.97, 0.93, 0.82))
	# town label & player
	var player := get_tree().get_first_node_in_group("player")
	if player:
		var pp := origin + (Vector2(player.global_position.x, player.global_position.z) + Vector2(extent, extent) * 0.5) * s
		var dir := Vector2(0, 1).rotated(-float(player.get("yaw")) if player.get("yaw") != null else 0.0)
		map.draw_colored_polygon(PackedVector2Array([pp + dir * 9.0, pp + dir.rotated(2.4) * 7.0, pp + dir.rotated(-2.4) * 7.0]), Color(0.99, 0.96, 0.86))
	var legend := "▲ Mountains    ● Camps & landmarks    ● Missions    ◆ Dustwater    ● You"
	map.draw_string(font, Vector2(origin.x + 6, origin.y + extent * s - 8), legend, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.92, 0.88, 0.76))


func _build_shop(board: Control) -> void:
	_title(board, "DUSTWATER GENERAL STORE", "Walt the Clerk — %s" % ("\"Finest goods west of the Mesilla.\"" ))
	var items := [
		{"name": "Revolver rounds (24)", "price": 12, "id": "revolver", "amount": 24},
		{"name": "Rifle cartridges (15)", "price": 18, "id": "rifle", "amount": 15},
		{"name": "Shotgun shells (12)", "price": 16, "id": "shotgun", "amount": 12},
		{"name": "Bandages (restore 40 health)", "price": 10, "id": "heal", "amount": 40},
	]
	var y := 128.0
	for it in items:
		var row := Panel.new()
		row.position = Vector2(48, y - 6)
		row.size = Vector2(board.size.x - 96, 52)
		var rowsb := StyleBoxFlat.new()
		rowsb.bg_color = Color(0.16, 0.13, 0.095, 0.9)
		rowsb.border_color = Color(0.34, 0.27, 0.16)
		rowsb.set_border_width_all(1)
		row.add_theme_stylebox_override("panel", rowsb)
		board.add_child(row)
		var l := _label(str(it["name"]), 19, Color(0.92, 0.87, 0.74))
		l.position = Vector2(16, 13)
		row.add_child(l)
		var price_l := _label("$%d" % int(it["price"]), 19, Color(0.72, 0.86, 0.6))
		price_l.position = Vector2(row.size.x - 190, 13)
		row.add_child(price_l)
		var item := it
		_button(row, "Buy", Vector2(row.size.x - 100, 6), Vector2(88, 40), func() -> void:
			if GameState.money < int(item["price"]):
				GameState.notify("Not enough money.", 2.0)
				return
			if not GameState.spend_money(int(item["price"])):
				return
			if str(item["id"]) == "heal":
				GameState.heal_player(float(item["amount"]))
				GameState.notify("You bind your wounds.", 2.5)
			else:
				GameState.add_ammo(str(item["id"]), int(item["amount"]))
				GameState.notify("Bought %s." % str(item["name"]), 2.5)
			AudioManager.play_sfx("metal_click", 1.1, -4.0)
			open("shop"))
		y += 60.0
	var purse := _label("Your purse: $%d" % GameState.money, 21, Color(0.85, 0.9, 0.7))
	purse.position = Vector2(50, y + 6)
	board.add_child(purse)
	_button(board, "Leave", Vector2(board.size.x - 210, board.size.y - 72), Vector2(160, 46), close)


func _build_settings(board: Control) -> void:
	_title(board, "SETTINGS", "Audio and control preferences")
	var x := 56.0
	var y := 132.0
	board.add_child(_slider(board, "Master volume", x, y, AudioManager.master_volume, func(v: float) -> void:
		AudioManager.master_volume = v
		AudioManager.apply_volumes()))
	board.add_child(_slider(board, "Music volume", x, y + 74, AudioManager.music_volume, func(v: float) -> void:
		AudioManager.music_volume = v
		AudioManager.apply_volumes()))
	board.add_child(_slider(board, "Effects volume", x, y + 148, AudioManager.sfx_volume, func(v: float) -> void:
		AudioManager.sfx_volume = v
		AudioManager.apply_volumes()))
	board.add_child(_slider(board, "Ambience volume", x, y + 222, AudioManager.ambience_volume, func(v: float) -> void:
		AudioManager.ambience_volume = v
		AudioManager.apply_volumes()))
	board.add_child(_slider(board, "Mouse sensitivity", x, y + 296, clampf((GameState.mouse_sensitivity - 0.2) / 1.8, 0.0, 1.0), func(v: float) -> void:
		GameState.mouse_sensitivity = 0.2 + v * 1.8))
	_button(board, "Back", Vector2(board.size.x - 210, board.size.y - 72), Vector2(160, 46), func() -> void: open("pause"))


func _slider(board: Control, text: String, x: float, y: float, value: float, cb: Callable) -> Control:
	var box := VBoxContainer.new()
	box.position = Vector2(x, y)
	box.add_theme_constant_override("separation", 6)
	box.add_child(_label(text, 19, Color(0.9, 0.85, 0.7)))
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.02
	s.value = clampf(value, 0.0, 1.0)
	s.custom_minimum_size = Vector2(400, 22)
	s.value_changed.connect(cb)
	box.add_child(s)
	return box


func _build_controls(board: Control) -> void:
	_title(board, "CONTROLS", "Keyboard and mouse")
	var left := """W A S D ......... Move
SHIFT ........... Sprint
SPACE ........... Jump
CTRL ............ Crouch
MOUSE ........... Look
C ................ Change camera
RIGHT MOUSE ..... Aim
LEFT MOUSE ...... Fire"""
	var right := """R ................ Reload
E ................ Interact / mount / talk
1 / 2 / 3 ........ Revolver / rifle / shotgun
X ................ Cycle weapon
F ................ Whistle for Juniper
I ................ Journal
M ................ Map
ESC .............. Pause
F5 / F9 .......... Quick save / load"""
	var l := _label(left, 19, Color(0.9, 0.86, 0.74))
	l.position = Vector2(60, 132)
	board.add_child(l)
	var r := _label(right, 19, Color(0.9, 0.86, 0.74))
	r.position = Vector2(60 + board.size.x * 0.42, 132)
	board.add_child(r)
	_button(board, "Back", Vector2(board.size.x - 210, board.size.y - 72), Vector2(160, 46), func() -> void: open("pause"))
