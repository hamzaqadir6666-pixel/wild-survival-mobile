class_name TouchControls
extends Control
## Touch controls: floating joystick on the left, camera drag on the right half,
## round buttons. Keyboard and mouse work too (desktop testing).

signal map_pressed
signal pause_pressed

var move := Vector2.ZERO           # x = right, y = forward
var look := Vector2.ZERO           # accumulated camera drag, consumed by the game
var sprint := false
var sneak := false
var jump := false                  # one-shot, consumed by the game
var act := false                   # one-shot
var action_icon := ""              # set by the game: leaf / drop / clover / ""
var enabled := true
var bot := false                   # test bots write the fields directly

var buttons := {}                  # id -> {pos, r, icon, touch}
var screen := Vector2(1280, 720)
var safe := Rect2(0, 0, 1280, 720)
var _stick_touch := -1
var _stick_origin := Vector2.ZERO
var _stick_pos := Vector2.ZERO
var _look_touch := -1
var _stick_r := 78.0
var _key_sprint := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

## places every button for a screen size (canvas units) and safe area
func layout(p_screen: Vector2, p_safe: Rect2, r0: float) -> void:
	screen = p_screen
	safe = p_safe
	var k := r0 / 48.0
	var br := safe.end
	buttons = {
		"act": {"pos": br + Vector2(-112, -112) * k, "r": 62.0 * k, "icon": "leaf", "touch": -1},
		"jump": {"pos": br + Vector2(-262, -84) * k, "r": 50.0 * k, "icon": "jump", "touch": -1},
		"sprint": {"pos": br + Vector2(-88, -262) * k, "r": 50.0 * k, "icon": "sprint", "touch": -1},
		"sneak": {"pos": br + Vector2(-232, -216) * k, "r": 48.0 * k, "icon": "sneak", "touch": -1},
		"map": {"pos": Vector2(br.x - 172.0 - r0 * 1.15, safe.position.y + 10.0 + r0), "r": r0, "icon": "map", "touch": -1},
		"pause": {"pos": Vector2(br.x - 172.0 - r0 * 3.4, safe.position.y + 10.0 + r0), "r": r0, "icon": "pause", "touch": -1},
	}
	_stick_r = 78.0 * k
	queue_redraw()

func reset() -> void:
	move = Vector2.ZERO; look = Vector2.ZERO; sprint = false; jump = false; act = false
	_stick_touch = -1; _look_touch = -1
	for id in buttons: buttons[id].touch = -1
	queue_redraw()

func _button_at(p: Vector2) -> String:
	for id in buttons:
		var b: Dictionary = buttons[id]
		if p.distance_to(b.pos) <= b.r * 1.12: return id
	return ""

func _input(e: InputEvent) -> void:
	if not enabled or not is_visible_in_tree(): return
	if e is InputEventScreenTouch:
		var p: Vector2 = get_global_transform().affine_inverse() * e.position
		if e.pressed:
			var id := _button_at(p)
			if id != "":
				buttons[id].touch = e.index
				_press(id)
			elif p.x < screen.x * 0.45 and _stick_touch == -1:
				_stick_touch = e.index
				_stick_origin = Vector2(clampf(p.x, safe.position.x + _stick_r + 8.0, screen.x * 0.45), clampf(p.y, _stick_r + 8.0, safe.end.y - _stick_r - 8.0))
				_stick_pos = p
				_stick_update()
			elif _look_touch == -1:
				_look_touch = e.index
		else:
			if e.index == _stick_touch:
				_stick_touch = -1
				move = Vector2.ZERO
			if e.index == _look_touch: _look_touch = -1
			for id in buttons:
				if buttons[id].touch == e.index:
					buttons[id].touch = -1
					if id == "sprint": sprint = false
		queue_redraw()
	elif e is InputEventScreenDrag:
		if e.index == _stick_touch:
			_stick_pos = get_global_transform().affine_inverse() * e.position
			_stick_update()
			queue_redraw()
		elif e.index == _look_touch:
			look += e.relative
	elif e is InputEventKey and not e.echo:
		match e.keycode:
			KEY_SPACE:
				if e.pressed: jump = true
			KEY_E:
				if e.pressed: act = true
			KEY_C, KEY_CTRL:
				if e.pressed: sneak = not sneak; queue_redraw()
			KEY_M, KEY_TAB:
				if e.pressed: map_pressed.emit()
			KEY_SHIFT: _key_sprint = e.pressed

func _press(id: String) -> void:
	match id:
		"act": act = true
		"jump": jump = true
		"sprint": sprint = true
		"sneak": sneak = not sneak
		"map": map_pressed.emit()
		"pause": pause_pressed.emit()
	if id != "sprint" and id != "act" and id != "jump": Sfx.click()

func _stick_update() -> void:
	var v := (_stick_pos - _stick_origin) / _stick_r
	if v.length() > 1.0: v = v.normalized()
	move = Vector2(v.x, -v.y)

func _process(_dt: float) -> void:
	if not enabled or bot: return
	if _stick_touch == -1:
		var k := Vector2(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
			float(Input.is_physical_key_pressed(KEY_W)) - float(Input.is_physical_key_pressed(KEY_S)))
		move = k.normalized() if k != Vector2.ZERO else Vector2.ZERO
	if buttons.has("sprint") and buttons.sprint.touch == -1: sprint = _key_sprint

func _draw() -> void:
	if buttons.is_empty(): return
	for id in buttons:
		var b: Dictionary = buttons[id]
		var on: bool = b.touch != -1 or (id == "sneak" and sneak) or (id == "sprint" and sprint)
		var ic: String = b.icon
		var dim := 1.0
		if id == "act":
			ic = action_icon if action_icon != "" else "leaf"
			if action_icon == "": dim = 0.35
		draw_circle(b.pos, b.r, Color(0.02, 0.05, 0.03, 0.42 * (0.6 + 0.4 * dim)))
		draw_arc(b.pos, b.r, 0.0, TAU, 40, Color(1, 1, 1, 0.9 if on else 0.5 * dim), 3.0 if on else 2.0, true)
		if on: draw_circle(b.pos, b.r - 3.0, Color(0.5, 0.9, 0.45, 0.35))
		UI.draw_icon(self, ic, b.pos, b.r * 1.05, Color(1, 1, 1, 0.95 * dim))
	# joystick: shown where the thumb is, or a hint ring when idle
	var o := _stick_origin if _stick_touch != -1 else Vector2(safe.position.x + 150.0 * _stick_r / 78.0, safe.end.y - 150.0 * _stick_r / 78.0)
	draw_circle(o, _stick_r, Color(0.02, 0.05, 0.03, 0.30))
	draw_arc(o, _stick_r, 0.0, TAU, 48, Color(1, 1, 1, 0.45), 2.0, true)
	var knob := o + Vector2(move.x, -move.y) * _stick_r
	draw_circle(knob, _stick_r * 0.42, Color(1, 1, 1, 0.55 if _stick_touch != -1 else 0.3))
	draw_arc(knob, _stick_r * 0.42, 0.0, TAU, 32, Color(0, 0, 0, 0.6), 2.0, true)
