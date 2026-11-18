extends CanvasLayer

var game: Node3D
var player: Explorer
var world: VoxelWorld
var root: Control
var loading: Control
var loading_label: Label
var progress: ProgressBar
var settings: Control
var touch_controls: Control
var hotbar: HBoxContainer
var slots: Array[Button] = []
var selected_label: Label
var hint: Label
var config := ConfigFile.new()

const INK := Color("ecf3e8")
const MUTED := Color("a8bdb2")
const GREEN := Color("b4e48c")

func _ready() -> void:
 config.load("user://settings.cfg")
 player.touch_enabled = config.get_value("controls", "touch", OS.has_feature("mobile"))
 player.sensitivity = config.get_value("controls", "sensitivity", 0.0025)
 player.camera.fov = config.get_value("graphics", "fov", 75.0)
 player.camera.far = config.get_value("graphics", "distance", 120.0)
 game.sun.shadow_enabled = config.get_value("graphics", "shadows", true)
 game.environment.fog_enabled = config.get_value("graphics", "fog", true)
 root = Control.new()
 root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 root.mouse_filter = Control.MOUSE_FILTER_IGNORE
 add_child(root)
 _build_hud()
 _build_settings()
 _build_loading()
 player.selection_changed.connect(_update_selection)
 _update_selection(1)

func _panel(color: Color, border: Color = Color("53665d"), radius: int = 8) -> StyleBoxFlat:
 var style := StyleBoxFlat.new()
 style.bg_color = color
 style.border_color = border
 style.set_border_width_all(1)
 style.set_corner_radius_all(radius)
 style.content_margin_left = 12
 style.content_margin_right = 12
 style.content_margin_top = 8
 style.content_margin_bottom = 8
 return style

func _label(text: String, size: int, color: Color = INK) -> Label:
 var label := Label.new()
 label.text = text
 label.add_theme_font_size_override("font_size", size)
 label.add_theme_color_override("font_color", color)
 label.mouse_filter = Control.MOUSE_FILTER_IGNORE
 return label

func _button(text: String) -> Button:
 var button := Button.new()
 button.text = text
 button.focus_mode = Control.FOCUS_NONE
 button.add_theme_font_size_override("font_size", 15)
 button.add_theme_color_override("font_color", INK)
 button.add_theme_stylebox_override("normal", _panel(Color("263a32")))
 button.add_theme_stylebox_override("hover", _panel(Color("3a5843"), GREEN))
 button.add_theme_stylebox_override("pressed", _panel(Color("4e6f4b"), GREEN))
 return button

func _build_hud() -> void:
 var brand := PanelContainer.new()
 brand.position = Vector2(24,22)
 brand.add_theme_stylebox_override("panel", _panel(Color(0.08,0.14,0.12,0.82)))
 root.add_child(brand)
 var brand_box := VBoxContainer.new()
 brand_box.add_theme_constant_override("separation", 0)
 brand.add_child(brand_box)
 brand_box.add_child(_label("W I L D L A N D S", 19, GREEN))
 brand_box.add_child(_label("A VOXEL SANDBOX", 10, MUTED))
 var settings_button := _button("⚙  SETTINGS")
 settings_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
 settings_button.offset_left = -158
 settings_button.offset_top = 24
 settings_button.offset_right = -24
 settings_button.offset_bottom = 65
 settings_button.pressed.connect(func(): _toggle_settings(true))
 root.add_child(settings_button)
 var cross := _label("+", 30, Color(1,1,1,0.9))
 cross.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 cross.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
 cross.set_anchors_preset(Control.PRESET_CENTER)
 cross.offset_left = -20
 cross.offset_right = 20
 cross.offset_top = -22
 cross.offset_bottom = 18
 root.add_child(cross)
 var bottom := VBoxContainer.new()
 bottom.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
 bottom.offset_left = -280
 bottom.offset_right = 280
 bottom.offset_top = -124
 bottom.offset_bottom = -18
 bottom.add_theme_constant_override("separation", 6)
 root.add_child(bottom)
 selected_label = _label("", 12, GREEN)
 selected_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 bottom.add_child(selected_label)
 hotbar = HBoxContainer.new()
 hotbar.alignment = BoxContainer.ALIGNMENT_CENTER
 hotbar.add_theme_constant_override("separation", 5)
 bottom.add_child(hotbar)
 for id in range(1,8):
  var slot := _button("%d\n%s" % [id, VoxelWorld.NAMES[id].left(3)])
  slot.custom_minimum_size = Vector2(65,54)
  slot.add_theme_font_size_override("font_size", 12)
  slot.pressed.connect(player.select_block.bind(id))
  hotbar.add_child(slot)
  slots.append(slot)
 hint = _label("WASD MOVE   ·   SPACE JUMP   ·   LEFT MINE   ·   RIGHT PLACE   ·   1–7 SELECT", 11, Color(1,1,1,0.85))
 hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 bottom.add_child(hint)
 _build_touch_controls()

func _build_touch_controls() -> void:
 touch_controls = Control.new()
 touch_controls.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 touch_controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
 root.add_child(touch_controls)
 var move_hint := _label("◉\nMOVE", 20, Color(1,1,1,0.7))
 move_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 move_hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
 move_hint.offset_left = 35
 move_hint.offset_top = -150
 move_hint.offset_right = 115
 move_hint.offset_bottom = -90
 touch_controls.add_child(move_hint)
 var actions := HBoxContainer.new()
 actions.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
 actions.offset_left = -255
 actions.offset_right = -20
 actions.offset_top = -120
 actions.offset_bottom = -60
 actions.add_theme_constant_override("separation", 6)
 touch_controls.add_child(actions)
 for action in ["MINE", "PLACE", "JUMP"]:
  var button := _button(action)
  button.custom_minimum_size = Vector2(74,50)
  button.add_theme_font_size_override("font_size", 12)
  if action == "MINE":
   button.pressed.connect(player.interact.bind(false))
  elif action == "PLACE":
   button.pressed.connect(player.interact.bind(true))
  else:
   button.pressed.connect(func(): player.jump_queued = true)
  actions.add_child(button)
 touch_controls.visible = player.touch_enabled
 hint.visible = not player.touch_enabled

func _update_selection(id: int) -> void:
 selected_label.text = "%s  /  INFINITE BLOCKS" % VoxelWorld.NAMES[id]
 for i in range(slots.size()):
  var color: Color = VoxelWorld.COLORS[i+1]
  var selected := i == id - 1
  slots[i].add_theme_stylebox_override("normal", _panel(color.darkened(0.55), GREEN if selected else Color("718276"), 5))
  slots[i].add_theme_stylebox_override("hover", _panel(color.darkened(0.35), GREEN, 5))

func _build_settings() -> void:
 settings = Control.new()
 settings.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 settings.mouse_filter = Control.MOUSE_FILTER_STOP
 settings.visible = false
 root.add_child(settings)
 var shade := ColorRect.new()
 shade.color = Color(0.02,0.05,0.04,0.75)
 shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
 settings.add_child(shade)
 var panel := PanelContainer.new()
 panel.set_anchors_preset(Control.PRESET_CENTER)
 panel.offset_left = -225
 panel.offset_right = 225
 panel.offset_top = -290
 panel.offset_bottom = 290
 panel.add_theme_stylebox_override("panel", _panel(Color("192b24"), Color("66816d"), 12))
 settings.add_child(panel)
 var margin := MarginContainer.new()
 margin.add_theme_constant_override("margin_left", 20)
 margin.add_theme_constant_override("margin_right", 20)
 margin.add_theme_constant_override("margin_top", 12)
 margin.add_theme_constant_override("margin_bottom", 12)
 panel.add_child(margin)
 var box := VBoxContainer.new()
 box.add_theme_constant_override("separation", 8)
 margin.add_child(box)
 box.add_child(_label("MAKE IT YOURS", 12, GREEN))
 box.add_child(_label("Settings", 30))
 box.add_child(_label("Tune your view and performance.", 14, MUTED))
 _slider(box, "FIELD OF VIEW", 55, 100, player.camera.fov, func(v): player.camera.fov = v; _save("graphics", "fov", v))
 _slider(box, "VIEW DISTANCE", 45, 160, player.camera.far, func(v): player.camera.far = v; _save("graphics", "distance", v))
 _slider(box, "LOOK SENSITIVITY", 1, 6, player.sensitivity * 1000, func(v): player.sensitivity = v / 1000.0; _save("controls", "sensitivity", player.sensitivity))
 _check(box, "Sun shadows", game.sun.shadow_enabled, func(v): game.sun.shadow_enabled = v; _save("graphics", "shadows", v))
 _check(box, "Atmospheric fog", game.environment.fog_enabled, func(v): game.environment.fog_enabled = v; _save("graphics", "fog", v))
 _check(box, "Touch controls", player.touch_enabled, func(v):
  player.touch_enabled = v
  touch_controls.visible = v
  hint.visible = not v
  _save("controls", "touch", v)
 )
 box.add_child(_label("ESC to pause  ·  Your block edits save automatically", 12, MUTED))
 var resume := _button("BACK TO THE WORLD  →")
 resume.custom_minimum_size.y = 42
 resume.pressed.connect(func(): _toggle_settings(false))
 box.add_child(resume)

func _slider(box: VBoxContainer, title: String, minimum: float, maximum: float, value: float, callback: Callable) -> void:
 var heading := _label(title, 11, GREEN)
 box.add_child(heading)
 var row := HBoxContainer.new()
 box.add_child(row)
 var slider := HSlider.new()
 slider.min_value = minimum
 slider.max_value = maximum
 slider.step = 0.1 if title == "LOOK SENSITIVITY" else 1.0
 slider.value = value
 slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 row.add_child(slider)
 var number := _label(str(snappedf(value, 0.1)), 13, MUTED)
 number.custom_minimum_size.x = 42
 number.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
 row.add_child(number)
 slider.value_changed.connect(func(v): number.text = str(snappedf(v, 0.1)); callback.call(v))

func _check(box: VBoxContainer, title: String, value: bool, callback: Callable) -> void:
 var check := CheckButton.new()
 check.text = title
 check.button_pressed = value
 check.add_theme_font_size_override("font_size", 14)
 box.add_child(check)
 check.toggled.connect(callback)

func _save(section: String, key: String, value: Variant) -> void:
 config.set_value(section,key,value)
 config.save("user://settings.cfg")

func _build_loading() -> void:
 loading = Control.new()
 loading.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 root.add_child(loading)
 var bg := ColorRect.new()
 bg.color = Color("14251f")
 bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 loading.add_child(bg)
 var box := VBoxContainer.new()
 box.set_anchors_preset(Control.PRESET_CENTER)
 box.offset_left = -190
 box.offset_right = 190
 box.offset_top = -80
 box.offset_bottom = 80
 box.add_theme_constant_override("separation", 14)
 loading.add_child(box)
 var eyebrow := _label("A LITTLE WORLD OF YOUR OWN", 12, GREEN)
 eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 box.add_child(eyebrow)
 var title := _label("W I L D L A N D S", 34)
 title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 box.add_child(title)
 loading_label = _label("Growing your world...", 14, MUTED)
 loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 box.add_child(loading_label)
 progress = ProgressBar.new()
 progress.custom_minimum_size.y = 8
 progress.show_percentage = false
 box.add_child(progress)

func update_loading(done: int, total: int) -> void:
 progress.value = 100.0 * done / total
 loading_label.text = "Growing your world... %d%%" % int(progress.value)

func finish_loading() -> void:
 loading.queue_free()

func _toggle_settings(open: bool) -> void:
 if not player.can_move:
  return
 settings.visible = open
 player.menu_open = open
 player.touch_move = Vector2.ZERO
 player.move_touch = -1
 player.look_touch = -1
 Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open or player.touch_enabled else Input.MOUSE_MODE_CAPTURED

func _input(event: InputEvent) -> void:
 if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
  _toggle_settings(not settings.visible)
  get_viewport().set_input_as_handled()
