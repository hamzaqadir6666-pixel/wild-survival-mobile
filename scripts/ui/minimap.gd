class_name Minimap
extends Control
## Small north-up map (top right) and the full-screen map. Both draw the same data.

var game: Node
var full := false
var radius := 105.0             # metres shown from the centre in the small map
var map_tex: Texture2D
var _t := 0.0

func _ready() -> void:
	map_tex = load("res://assets/world/map.png")
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(dt: float) -> void:
	_t += dt
	if is_visible_in_tree() and (full or Engine.get_process_frames() % 3 == 0): queue_redraw()

func _draw() -> void:
	if game == null or game.player == null: return
	var deer: Vector3 = game.player.position
	var sz := size
	var centre := Vector2(deer.x, deer.z)
	var span := radius * 2.0
	if full:
		centre = Vector2(512, 512)
		span = 1024.0
	var scale_px := sz.x / span        # canvas units per metre
	var origin := centre - Vector2(span, span * sz.y / sz.x) * 0.5
	var src := Rect2(origin / 1024.0 * map_tex.get_width(), Vector2(span, span * sz.y / sz.x) / 1024.0 * map_tex.get_width())
	draw_rect(Rect2(Vector2.ZERO, sz), Color(0.12, 0.16, 0.13, 0.95))
	draw_texture_rect_region(map_tex, Rect2(Vector2.ZERO, sz), src)
	var font := get_theme_default_font()
	# safe thickets and landmarks, once discovered
	for i in World.thickets.size():
		if game.found_thickets.has(i):
			var t: Dictionary = World.thickets[i]
			var p := (Vector2(t.x, t.z) - origin) * scale_px
			draw_arc(p, 6.0 if not full else 9.0, 0, TAU, 16, Color(0, 0, 0, 0.9), 5.0, true)
			draw_arc(p, 6.0 if not full else 9.0, 0, TAU, 16, Color(0.4, 1.0, 0.45), 2.5, true)
			if full: _text(font, p + Vector2(12, 5), "Safe thicket", 13, Color(0.6, 1.0, 0.6))
	for i in World.landmarks.size():
		if game.found_landmarks.has(i):
			var l: Dictionary = World.landmarks[i]
			var p2 := (Vector2(l.x, l.z) - origin) * scale_px
			UI.draw_icon(self, "star", p2, 16.0 if not full else 22.0, UI.GOLD)
			if full: _text(font, p2 + Vector2(13, 5), l.name, 13, UI.GOLD)
	if full:
		for i in World.lakes.size():
			if game.found_lakes.has(i):
				var k: Dictionary = World.lakes[i]
				_text(font, (Vector2(k.x, k.z) - origin) * scale_px + Vector2(-34, 4), k.name, 14, Color(0.8, 0.95, 1.0))
	# rare plants that came within about 22 m, until eaten
	for it in game.plants.items:
		if it.shown and not it.eaten:
			var p3 := (Vector2(it.x, it.z) - origin) * scale_px
			if p3.x < -4 or p3.y < -4 or p3.x > sz.x + 4 or p3.y > sz.y + 4: continue
			var col: Color = D.PLANTS[it.t].glow
			draw_circle(p3, 5.0, Color(0, 0, 0, 0.9))
			draw_circle(p3, 3.6, col)
	# Owl-eye Mushroom: nearest hunter within 90 m
	if game.player.has("owleye") and game.fauna.nearest_hunter != null and game.fauna.nearest_hunter_dist < 90.0:
		var hp: Vector3 = game.fauna.nearest_hunter.position
		var p4 := (Vector2(hp.x, hp.z) - origin) * scale_px
		p4 = p4.clamp(Vector2(6, 6), sz - Vector2(6, 6))
		var pulse := 5.0 + sin(_t * 6.0) * 1.5
		draw_circle(p4, pulse + 2.0, Color(0, 0, 0, 0.9))
		draw_circle(p4, pulse, UI.RED)
	# the deer
	var dp := (Vector2(deer.x, deer.z) - origin) * scale_px
	var yaw: float = game.player.yaw
	var f := Vector2(sin(yaw), cos(yaw))
	var r := f.orthogonal()
	var s := 9.0 if not full else 11.0
	var tri := PackedVector2Array([dp + f * s, dp - f * s * 0.7 + r * s * 0.65, dp - f * s * 0.3, dp - f * s * 0.7 - r * s * 0.65])
	var dark := PackedVector2Array()
	for v in tri: dark.append(dp + (v - dp) * 1.45)
	draw_colored_polygon(dark, Color(0, 0, 0, 0.9))
	draw_colored_polygon(tri, Color(1, 1, 1))
	draw_rect(Rect2(Vector2.ZERO, sz), Color(0, 0, 0, 0.9), false, 4.0)
	draw_rect(Rect2(Vector2(2, 2), sz - Vector2(4, 4)), Color(0.85, 0.8, 0.6, 0.9), false, 1.5)
	if not full: _text(font, Vector2(sz.x * 0.5 - 5, 16), "N", 13, Color.WHITE)

func _text(font: Font, at: Vector2, text: String, fs: int, col: Color) -> void:
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0, 0, 0, 0.95))
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
