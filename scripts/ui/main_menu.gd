extends Control
## Title screen: New Game / Continue / Settings / Controls / Quit, painted in
## an oil-on-canvas Western style with animated dust motes.

@onready var backdrop: ColorRect = $Backdrop
@onready var title_layer: Control = $TitleLayer
@onready var button_box: VBoxContainer = $TitleLayer/Buttons
@onready var status_label: Label = $TitleLayer/Status

var _time := 0.0
var _dust: Array[Dictionary] = []
var _settings_panel: Control


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	_build_dust()
	var cont := button_box.get_node_or_null("Continue")
	var has_save := SaveSystem.newest_slot() >= 0
	if cont:
		cont.disabled = not has_save
		cont.modulate.a = 1.0 if has_save else 0.45
	_background_music()
	status_label.text = "Press ENTER to ride" if has_save else "A frontier tale by Red Hollow Games"


func _background_music() -> void:
	AudioManager.play_music("explore", 3.0)
	AudioManager.set_ambience("wind", -18.0, 3.0)


func _build_dust() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in 140:
		_dust.append({
			"p": Vector2(rng.randf(), rng.randf()),
			"v": Vector2(rng.randf_range(-0.01, 0.02), rng.randf_range(-0.035, -0.006)),
			"s": rng.randf_range(0.6, 2.2),
			"a": rng.randf_range(0.12, 0.5),
		})
	backdrop.draw.connect(_draw_backdrop)


func _process(delta: float) -> void:
	_time += delta
	for d in _dust:
		d["p"] += d["v"] * delta
		if d["p"].y < -0.02:
			d["p"].y = 1.02
			d["p"].x = randf()
		if d["p"].x < -0.02:
			d["p"].x = 1.02
		elif d["p"].x > 1.02:
			d["p"].x = -0.02
	backdrop.queue_redraw()


func _draw_backdrop() -> void:
	var sz := backdrop.size
	var h := sz.y
	# layered sepia sky, sun glow and silhouetted mesas
	for i in 48:
		var t := float(i) / 47.0
		var c := Color(0.36, 0.2, 0.1).lerp(Color(0.98, 0.72, 0.36), pow(t, 1.5))
		backdrop.draw_rect(Rect2(0, h * t * 0.62, sz.x, h * 0.62 / 48.0 + 1), c)
	var sun_pos := Vector2(sz.x * 0.72, h * 0.44)
	for r in range(28, 0, -1):
		var rr := r * 12.0
		backdrop.draw_circle(sun_pos, rr, Color(1.0, 0.82, 0.5, 0.012 * r))
	backdrop.draw_circle(sun_pos, 58.0, Color(1.0, 0.93, 0.72, 0.95))
	# distant mesa silhouettes
	var layers := [
		{"y": 0.60, "col": Color(0.34, 0.2, 0.14, 0.85), "amp": 26.0, "freq": 0.0075, "off": 0.0},
		{"y": 0.70, "col": Color(0.24, 0.14, 0.1, 0.92), "amp": 40.0, "freq": 0.0055, "off": 2.1},
		{"y": 0.82, "col": Color(0.13, 0.08, 0.06, 0.98), "amp": 22.0, "freq": 0.011, "off": 4.3},
	]
	for l in layers:
		var pts := PackedVector2Array()
		pts.append(Vector2(0, sz.y))
		var step := 14.0
		var x := 0.0
		while x <= sz.x:
			var y := h * float(l["y"]) - absf(sin(x * float(l["freq"]) + float(l["off"]))) * float(l["amp"]) - sin(x * 0.0021) * 18.0
			pts.append(Vector2(x, y))
			x += step
		pts.append(Vector2(sz.x, sz.y))
		backdrop.draw_colored_polygon(pts, l["col"])
	# dust motes
	for d in _dust:
		var p: Vector2 = d["p"]
		var pos := Vector2(p.x * sz.x, p.y * h)
		backdrop.draw_circle(pos, float(d["s"]), Color(1.0, 0.92, 0.72, float(d["a"]) * 0.55))
	# vignette
	for i in 16:
		var t := float(i) / 15.0
		backdrop.draw_rect(Rect2(0, 0, sz.x, 6.0), Color(0, 0, 0, 0))
	var vign := Color(0.03, 0.02, 0.01, 0.55)
	backdrop.draw_rect(Rect2(0, 0, sz.x, 90), Color(vign.r, vign.g, vign.b, 0.35))
	backdrop.draw_rect(Rect2(0, h - 140, sz.x, 140), Color(vign.r, vign.g, vign.b, 0.55))


func _on_new_game() -> void:
	AudioManager.play_sfx("ui_click", 1.0, -4.0)
	GameState.reset_to_defaults()
	GameState.is_new_game = true
	get_tree().change_scene_to_file("res://scenes/world/main_world.tscn")


func _on_continue() -> void:
	AudioManager.play_sfx("ui_click", 1.0, -4.0)
	var slot := SaveSystem.newest_slot()
	if slot >= 0 and SaveSystem.load_game(slot):
		get_tree().change_scene_to_file("res://scenes/world/main_world.tscn")
	else:
		status_label.text = "No save found."


func _on_settings() -> void:
	AudioManager.play_sfx("ui_click", 1.0, -4.0)
	status_label.text = "Settings are available in-game from the pause menu."


func _on_controls() -> void:
	AudioManager.play_sfx("ui_click", 1.0, -4.0)
	status_label.text = "WASD move · SHIFT sprint · SPACE jump · RMB aim · LMB fire · E interact · C camera"


func _on_quit() -> void:
	get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			if SaveSystem.newest_slot() >= 0:
				_on_continue()
			else:
				_on_new_game()
		elif event.keycode == KEY_ESCAPE:
			_on_quit()
