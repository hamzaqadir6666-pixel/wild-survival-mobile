class_name Hud
extends Control
## In-game HUD, drawn by hand in one Control (cheap: one canvas item, redrawn ~10x per second).
## Every text has a dark outline or sits on a dark panel.

const THREAT_TEXT := ["SAFE", "WATCHED", "HUNTED"]
const THREAT_COL := [Color(0.45, 0.9, 0.45), Color(1.0, 0.8, 0.25), Color(1.0, 0.28, 0.22)]
const ABILITY_ICON := {"clover": "clover", "moonpetal": "moon", "ironbark": "shield", "sunberry": "sun", "ghostfern": "ghost", "owleye": "eye", "springlily": "jump", "lotus": "wave"}
const PLANT_ICON := {"herb": "cross", "honey": "honey", "toadstool": "skull"}
const WEATHER_ICON := ["sun", "cloud", "rain", "storm"]

var game: Node
var screen := Vector2(1280, 720)
var safe := Rect2(0, 0, 1280, 720)
var rects := {}
var notes: Array = []            # {text, kind, age}
var flash := 0.0
var hint := ""
var _acc := 0.0
var _font: Font

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_font = get_theme_default_font()

func layout(p_screen: Vector2, p_safe: Rect2, r0: float) -> void:
	screen = p_screen
	safe = p_safe
	var tl := safe.position
	var top_w := minf(340.0, safe.size.x - 246.0 - 172.0 - r0 * 4.6 - 30.0)
	var mid_x := tl.x + 256.0 + (safe.size.x - 256.0 - 172.0 - r0 * 4.6 - 10.0) * 0.5
	rects = {
		"bars": Rect2(tl + Vector2(10, 10), Vector2(236, 112)),
		"abilities": Rect2(tl + Vector2(10, 128), Vector2(8 * 31, 30)),
		"top": Rect2(Vector2(mid_x - top_w * 0.5, tl.y + 8), Vector2(top_w, 62)),
		"minimap": Rect2(Vector2(safe.end.x - 160, tl.y + 10), Vector2(150, 150)),
		"counts": Rect2(Vector2(safe.end.x - 160, tl.y + 164), Vector2(150, 46)),
		"notes": Rect2(Vector2(mid_x - 230, tl.y + 78), Vector2(460, 112)),
	}
	queue_redraw()

func notify(text: String, kind := 0) -> void:
	for n in notes:
		if n.text == text and n.age < 2.0: return
	notes.append({"text": text, "kind": kind, "age": 0.0})
	if notes.size() > 3: notes.pop_front()
	queue_redraw()

func clear() -> void:
	notes.clear(); flash = 0.0; hint = ""
	queue_redraw()

func _process(dt: float) -> void:
	if not is_visible_in_tree(): return
	_acc += dt
	flash = maxf(0.0, flash - dt * 1.6)
	for i in range(notes.size() - 1, -1, -1):
		notes[i].age += dt
		if notes[i].age > 4.0: notes.remove_at(i)
	if _acc >= 0.1 or flash > 0.0:
		_acc = 0.0
		queue_redraw()

func _text(at: Vector2, text: String, fs: int, col := Color.WHITE, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	draw_string_outline(_font, at, text, align, width, fs, maxi(4, fs / 3), Color(0, 0, 0, 0.95 * col.a))
	draw_string(_font, at, text, align, width, fs, col)

func _bar(r: Rect2, frac: float, col: Color, icon_name: String, low: bool) -> void:
	UI.draw_icon(self, icon_name, r.position + Vector2(11, r.size.y * 0.5), 20.0, col.lightened(0.25))
	var b := Rect2(r.position + Vector2(28, 3), Vector2(r.size.x - 28, r.size.y - 6))
	draw_rect(b, Color(0, 0, 0, 0.75))
	var c := col
	if low and fmod(Time.get_ticks_msec() * 0.004, 2.0) < 1.0: c = Color(1, 1, 1)
	draw_rect(Rect2(b.position + Vector2(2, 2), Vector2((b.size.x - 4) * clampf(frac, 0.0, 1.0), b.size.y - 4)), c)
	draw_rect(b, Color(1, 1, 1, 0.35), false, 1.0)

func _draw() -> void:
	if game == null or game.player == null or rects.is_empty(): return
	var p: Player = game.player
	if flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, screen), Color(0.8, 0.0, 0.0, 0.38 * flash))
	var rb: Rect2 = rects.bars
	draw_style_box(_panel, rb)
	var row := (rb.size.y - 12.0) / 4.0
	_bar(Rect2(rb.position + Vector2(8, 6), Vector2(rb.size.x - 16, row)), p.health / p.max_health, Color(0.9, 0.25, 0.22), "heart", p.health < p.max_health * 0.3)
	_bar(Rect2(rb.position + Vector2(8, 6 + row), Vector2(rb.size.x - 16, row)), p.stamina / p.max_stamina, Color(0.95, 0.8, 0.2), "bolt", p.exhausted)
	_bar(Rect2(rb.position + Vector2(8, 6 + row * 2), Vector2(rb.size.x - 16, row)), p.food / 100.0, Color(0.5, 0.8, 0.3), "leaf", p.food < 20.0)
	_bar(Rect2(rb.position + Vector2(8, 6 + row * 3), Vector2(rb.size.x - 16, row)), p.water / 100.0, Color(0.3, 0.62, 0.95), "drop", p.water < 20.0)
	# abilities owned
	var ra: Rect2 = rects.abilities
	var ax := ra.position.x + 15.0
	for key in D.ABILITY_ORDER:
		var n := Save.ability(key)
		if n <= 0: continue
		var c := Vector2(ax, ra.position.y + 15.0)
		draw_circle(c, 15.0, Color(0, 0, 0, 0.62))
		var col: Color = D.PLANTS[key].glow
		UI.draw_icon(self, ABILITY_ICON[key], c, 20.0, col.lightened(0.3))
		if key == "clover": _text(c + Vector2(-14, 30), "%d%%" % p.speed_percent(), 13, Color(0.7, 1.0, 0.75))
		elif n > 1: _text(c + Vector2(6, 16), "%d" % n, 12)
		ax += 31.0
	if p.poison > 0.0:
		UI.draw_icon(self, "skull", Vector2(ax, ra.position.y + 15.0), 24.0, Color(0.8, 0.4, 1.0))
	# clock, day, weather, threat, goals
	var rt: Rect2 = rects.top
	draw_style_box(_panel, rt)
	var sky: SkyRig = game.sky
	var night := sky.is_night
	UI.draw_icon(self, "moon" if night and sky.weather == 0 else WEATHER_ICON[sky.weather], rt.position + Vector2(20, 18), 22.0, Color(0.8, 0.85, 1.0) if night else Color(1.0, 0.9, 0.5))
	_text(rt.position + Vector2(38, 25), "Day %d   %s" % [sky.day, sky.clock_text()], 18)
	var th: int = game.fauna.threat_level
	var tc: Color = THREAT_COL[th]
	if th == 2 and fmod(Time.get_ticks_msec() * 0.003, 1.0) < 0.5: tc = Color(1, 0.75, 0.7)
	UI.draw_icon(self, "eye", Vector2(rt.end.x - 104, rt.position.y + 18), 20.0, tc)
	_text(Vector2(rt.end.x - 90, rt.position.y + 25), THREAT_TEXT[th], 17, tc)
	_text(rt.position + Vector2(10, 52), game.goal_text(), 15, Color(1.0, 0.93, 0.7), HORIZONTAL_ALIGNMENT_CENTER, rt.size.x - 20)
	# discoveries / wildlife
	var rc: Rect2 = rects.counts
	draw_style_box(_panel, rc)
	UI.draw_icon(self, "flag", rc.position + Vector2(14, 12), 16.0, UI.GOLD)
	_text(rc.position + Vector2(28, 17), "Discoveries %d / %d" % [game.discoveries(), D.DISCOVERY_TOTAL], 13)
	UI.draw_icon(self, "paw", rc.position + Vector2(14, 33), 16.0, Color(0.8, 0.9, 1.0))
	_text(rc.position + Vector2(28, 38), "Wildlife seen %d / %d" % [game.fauna.seen_count(), D.WILDLIFE_TOTAL], 13)
	# pop-up notes
	var rn: Rect2 = rects.notes
	var y := rn.position.y
	for n in notes:
		var a := clampf(minf(n.age * 5.0, (4.0 - n.age) * 2.0), 0.0, 1.0)
		var col2: Color = [Color(1, 1, 1), Color(1.0, 0.82, 0.3), Color(1.0, 0.4, 0.35), Color(0.55, 1.0, 0.6)][n.kind]
		var w := minf(_font.get_string_size(n.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x + 28.0, rn.size.x)
		var r := Rect2(Vector2(rn.position.x + (rn.size.x - w) * 0.5, y), Vector2(w, 32))
		draw_rect(r, Color(0.03, 0.05, 0.04, 0.7 * a))
		_text(Vector2(rn.position.x, y + 23), n.text, 18, Color(col2.r, col2.g, col2.b, a), HORIZONTAL_ALIGNMENT_CENTER, rn.size.x)
		y += 36.0
	# what the action button will do
	if hint != "" and game.controls.buttons.has("act"):
		var b: Dictionary = game.controls.buttons.act
		_text(Vector2(b.pos.x - 150, b.pos.y - b.r - 10), hint, 16, Color(1, 1, 0.85), HORIZONTAL_ALIGNMENT_CENTER, 300.0)

var _panel: StyleBoxFlat = UI.box(UI.PANEL, 10, 0)
