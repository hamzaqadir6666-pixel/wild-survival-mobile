class_name UI
extends RefCounted
## Small helpers so every piece of text and every button looks the same.
## All HUD text gets a dark outline so it stays readable on bright ground.

const GREEN := Color(0.45, 0.85, 0.4)
const GOLD := Color(1.0, 0.82, 0.35)
const RED := Color(0.95, 0.3, 0.25)
const PANEL := Color(0.05, 0.08, 0.06, 0.72)
static var _icons := {}

static func icon(name: String) -> Texture2D:
	if not _icons.has(name): _icons[name] = load("res://assets/ui/%s.png" % name)
	return _icons[name]

static func label(text: String, size := 18, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	l.add_theme_constant_override("outline_size", maxi(4, size / 4))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

static func box(color := PANEL, radius := 10, margin := 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	return s

static func panel(color := PANEL, radius := 12, margin := 10) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(color, radius, margin))
	return p

static func button(text: String, cb: Callable, size := 22, min_size := Vector2(230, 64), icon_name := "") -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	b.add_theme_constant_override("outline_size", 4)
	b.add_theme_stylebox_override("normal", box(Color(0.16, 0.30, 0.17, 0.95), 12, 10))
	b.add_theme_stylebox_override("hover", box(Color(0.20, 0.38, 0.21, 0.95), 12, 10))
	b.add_theme_stylebox_override("pressed", box(Color(0.30, 0.52, 0.28, 1.0), 12, 10))
	b.add_theme_stylebox_override("disabled", box(Color(0.14, 0.15, 0.14, 0.9), 12, 10))
	if icon_name != "":
		b.icon = icon(icon_name)
		b.expand_icon = true
		b.add_theme_constant_override("icon_max_width", int(min_size.y * 0.55))
	b.pressed.connect(func():
		Sfx.click()
		cb.call())
	return b

static func icon_rect(name: String, size := 24.0, color := Color.WHITE) -> TextureRect:
	var t := TextureRect.new()
	t.texture = icon(name)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = Vector2(size, size)
	t.modulate = color
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t

## icon with a dark copy underneath, for drawing directly on the 3D view
static func draw_icon(ci: CanvasItem, name: String, center: Vector2, size: float, color := Color.WHITE) -> void:
	var tex := icon(name)
	var r := Rect2(center - Vector2(size, size) * 0.5, Vector2(size, size))
	for o in [Vector2(-2, 0), Vector2(2, 0), Vector2(0, -2), Vector2(0, 2)]:
		ci.draw_texture_rect(tex, Rect2(r.position + o, r.size), false, Color(0, 0, 0, 0.8 * color.a))
	ci.draw_texture_rect(tex, r, false, color)

## 9 mm in canvas units for the current screen (buttons must not be smaller)
static func mm(n: float, win: Window) -> float:
	var dpi := float(DisplayServer.screen_get_dpi())
	if dpi <= 0.0: dpi = 160.0
	var sc := minf(win.size.x / 1280.0, win.size.y / 720.0)
	if sc <= 0.0: sc = 1.0
	return n * dpi / 25.4 / sc
