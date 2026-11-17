extends CanvasLayer
## On-screen touch controls (left thumb stick, look pad, fire / jump / sprint /
## interact / reload buttons). Only built when the platform actually has a
## touchscreen, so desktop players keep a clean screen.

signal touch_look(relative: Vector2)

const STICK_RADIUS := 92.0
const LOOK_SENS := 0.32

var enabled := false
var _root: Control
var _stick_base: Control
var _stick_knob: Control
var _stick_touch := -1
var _stick_origin := Vector2.ZERO
var _look_touch := -1
var _look_last := Vector2.ZERO
var _held: Dictionary = {}


func _ready() -> void:
	layer = 12
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("touch_controls")
	enabled = _has_touchscreen()
	visible = enabled
	if enabled:
		_build()


func _has_touchscreen() -> bool:
	var forced := OS.get_environment("DUST_TOUCH_UI")
	if forced == "1":
		return true
	if forced == "0":
		return false
	if DisplayServer.is_touchscreen_available():
		return true
	return OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")


func _build() -> void:
	_root = Control.new()
	_root.name = "TouchRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# ---- movement stick (lower left) ----
	_stick_base = Control.new()
	_stick_base.name = "StickBase"
	_stick_base.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_stick_base.position = Vector2(150, -170)
	_stick_base.custom_minimum_size = Vector2(STICK_RADIUS * 2, STICK_RADIUS * 2)
	_stick_base.size = Vector2(STICK_RADIUS * 2, STICK_RADIUS * 2)
	_stick_base.pivot_offset = Vector2(STICK_RADIUS, STICK_RADIUS)
	_stick_base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stick_base.draw.connect(_draw_stick_base)
	_root.add_child(_stick_base)

	_stick_knob = Control.new()
	_stick_knob.name = "StickKnob"
	_stick_knob.size = Vector2(64, 64)
	_stick_knob.position = Vector2(STICK_RADIUS - 32, STICK_RADIUS - 32)
	_stick_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stick_knob.draw.connect(_draw_stick_knob)
	_stick_base.add_child(_stick_knob)

	# ---- buttons (lower right) ----
	_button("Fire", Vector2(-140, -170), 62.0, Color(0.72, 0.2, 0.16, 0.55), "fire")
	_button("Aim", Vector2(-250, -250), 46.0, Color(0.3, 0.35, 0.45, 0.5), "aim_hold")
	_button("Jump", Vector2(-60, -300), 50.0, Color(0.3, 0.4, 0.3, 0.5), "jump")
	_button("Sprint", Vector2(-250, -120), 46.0, Color(0.35, 0.35, 0.28, 0.5), "sprint")
	_button("E", Vector2(-160, -320), 46.0, Color(0.5, 0.42, 0.22, 0.55), "interact")
	_button("R", Vector2(-330, -190), 42.0, Color(0.35, 0.3, 0.28, 0.5), "reload")
	_button("Horse", Vector2(-330, -290), 42.0, Color(0.4, 0.32, 0.2, 0.5), "whistle_horse")
	_button("Menu", Vector2(-70, -60), 40.0, Color(0.25, 0.22, 0.2, 0.55), "pause")
	_button("Map", Vector2(-160, -60), 40.0, Color(0.25, 0.22, 0.2, 0.55), "map")


func _button(label: String, offset: Vector2, radius: float, tint: Color, action: String) -> void:
	var b := Control.new()
	b.name = "Btn_" + action
	b.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	b.position = offset - Vector2(radius, radius)
	b.size = Vector2(radius * 2, radius * 2)
	b.pivot_offset = Vector2(radius, radius)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.set_meta("label", label)
	b.set_meta("radius", radius)
	b.set_meta("tint", tint)
	b.set_meta("action", action)
	b.set_meta("down", false)
	b.draw.connect(func() -> void: _draw_button(b))
	_root.add_child(b)


func _draw_button(b: Control) -> void:
	var r: float = b.get_meta("radius")
	var tint: Color = b.get_meta("tint")
	var down: bool = b.get_meta("down")
	var c := Vector2(r, r)
	b.draw_circle(c, r, Color(tint.r, tint.g, tint.b, tint.a * (1.45 if down else 1.0)))
	b.draw_arc(c, r, 0.0, TAU, 40, Color(0.95, 0.87, 0.68, 0.75), 2.0, true)
	var font := ThemeDB.fallback_font
	var text: String = b.get_meta("label")
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, 18).x
	b.draw_string(font, c + Vector2(-w * 0.5, 6.0), text, HORIZONTAL_ALIGNMENT_CENTER, -1, 18,
		Color(1.0, 0.96, 0.86, 0.95))


func _draw_stick_base() -> void:
	var c := Vector2(STICK_RADIUS, STICK_RADIUS)
	_stick_base.draw_circle(c, STICK_RADIUS, Color(0.08, 0.07, 0.06, 0.3))
	_stick_base.draw_arc(c, STICK_RADIUS - 2.0, 0.0, TAU, 48, Color(0.9, 0.82, 0.64, 0.55), 2.5, true)
	_stick_base.draw_arc(c, STICK_RADIUS * 0.45, 0.0, TAU, 32, Color(0.9, 0.82, 0.64, 0.22), 1.5, true)


func _draw_stick_knob() -> void:
	_stick_knob.draw_circle(Vector2(32, 32), 30.0, Color(0.92, 0.86, 0.7, 0.55))
	_stick_knob.draw_arc(Vector2(32, 32), 29.0, 0.0, TAU, 32, Color(1, 0.96, 0.86, 0.8), 2.0, true)


## ---- input ----
func _input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag:
		_handle_drag(event)


func _handle_touch(e: InputEventScreenTouch) -> void:
	var p := e.position
	if e.pressed:
		if _in_button(p) != "":
			_press_button(_in_button(p), true)
			get_viewport().set_input_as_handled()
			return
		if _stick_touch == -1 and p.x < get_viewport().get_visible_rect().size.x * 0.42 and p.y > get_viewport().get_visible_rect().size.y * 0.45:
			_stick_touch = e.index
			_stick_origin = p
			_move_stick(Vector2.ZERO)
			get_viewport().set_input_as_handled()
			return
		if _look_touch == -1:
			_look_touch = e.index
			_look_last = p
	else:
		if _stick_touch == e.index:
			_stick_touch = -1
			_move_stick(Vector2.ZERO)
		elif _look_touch == e.index:
			_look_touch = -1
		var a := _in_button(p)
		if a != "":
			_press_button(a, false)


func _handle_drag(e: InputEventScreenDrag) -> void:
	if e.index == _stick_touch:
		var off := (e.position - _stick_origin) / STICK_RADIUS
		if off.length() > 1.0:
			off = off.normalized()
		_move_stick(off)
	elif e.index == _look_touch:
		var rel := e.position - _look_last
		_look_last = e.position
		touch_look.emit(rel * LOOK_SENS)


func _move_stick(v: Vector2) -> void:
	_stick_knob.position = Vector2(STICK_RADIUS - 32, STICK_RADIUS - 32) + v * (STICK_RADIUS - 34.0)
	_stick_knob.queue_redraw()
	var dead := 0.16
	_set_action("move_forward", -v.y > dead, absf(v.y))
	_set_action("move_back", v.y > dead, v.y)
	_set_action("move_left", -v.x > dead, -v.x)
	_set_action("move_right", v.x > dead, v.x)


func _set_action(action: String, on: bool, strength: float = 1.0) -> void:
	if on:
		if not _held.has(action):
			Input.action_press(action, clampf(strength, 0.0, 1.0))
			_held[action] = true
	elif _held.has(action):
		Input.action_release(action)
		_held.erase(action)


func _release_all() -> void:
	for a in _held.keys():
		Input.action_release(a)
	_held.clear()


func _in_button(p: Vector2) -> String:
	if _root == null:
		return ""
	for c in _root.get_children():
		if not c.has_meta("action"):
			continue
		var rect := Rect2(c.global_position - Vector2(10, 10), c.size + Vector2(20, 20))
		if rect.has_point(p):
			return str(c.get_meta("action"))
	return ""


func _press_button(action: String, down: bool) -> void:
	for c in _root.get_children():
		if c.has_meta("action") and str(c.get_meta("action")) == action:
			c.set_meta("down", down)
			c.queue_redraw()
	if down:
		if not _held.has(action):
			Input.action_press(action)
			_held[action] = true
	elif _held.has(action):
		Input.action_release(action)
		_held.erase(action)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_release_all()
