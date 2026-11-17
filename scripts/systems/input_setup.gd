extends Node
## Registers all input actions at runtime so the project works without
## hand-editing the InputMap (and stays remappable in the settings menu).

const ACTIONS := {
	"move_forward": [KEY_W],
	"move_back": [KEY_S],
	"move_left": [KEY_A],
	"move_right": [KEY_D],
	"sprint": [KEY_SHIFT],
	"jump": [KEY_SPACE],
	"crouch": [KEY_CTRL],
	"interact": [KEY_E],
	"reload": [KEY_R],
	"camera_toggle": [KEY_C],
	"aim": [KEY_Q],
	"inventory": [KEY_I],
	"map": [KEY_M],
	"journal": [KEY_I],
	"holster": [KEY_H],
	"pause": [KEY_ESCAPE],
	"quick_save": [KEY_F5],
	"quick_load": [KEY_F9],
	"weapon_1": [KEY_1],
	"weapon_2": [KEY_2],
	"weapon_3": [KEY_3],
	"weapon_next": [KEY_X],
	"whistle_horse": [KEY_F],
	"call_horse": [KEY_V],
	"crouch_toggle": [KEY_CTRL],
	"toggle_hud": [KEY_F1],
	"toggle_help": [KEY_F2],
	"skip_time": [KEY_T],
	"debug_toggle": [KEY_F3],
}

const MOUSE_ACTIONS := {
	"fire": MOUSE_BUTTON_LEFT,
	"aim_hold": MOUSE_BUTTON_RIGHT,
}


func _ready() -> void:
	register_actions()
	# Default dead zones / device bindings.
	for action in ACTIONS:
		if InputMap.has_action(action):
			InputMap.action_set_deadzone(action, 0.2)


func register_actions() -> void:
	for action in ACTIONS.keys():
		_ensure_action(action)
		for key in ACTIONS[action]:
			_add_key(action, key)
	for action in MOUSE_ACTIONS.keys():
		_ensure_action(action)
		_add_mouse(action, MOUSE_ACTIONS[action])
	# Analogue sticks for gamepad users.
	_ensure_action("move_forward")
	_add_joy_axis("move_forward", JOY_AXIS_LEFT_Y, -1.0)
	_add_joy_axis("move_back", JOY_AXIS_LEFT_Y, 1.0)
	_add_joy_axis("move_left", JOY_AXIS_LEFT_X, -1.0)
	_add_joy_axis("move_right", JOY_AXIS_LEFT_X, 1.0)
	_ensure_action("camera_look_left")
	_ensure_action("camera_look_right")
	_ensure_action("camera_look_up")
	_ensure_action("camera_look_down")
	_add_joy_axis("camera_look_left", JOY_AXIS_RIGHT_X, -1.0)
	_add_joy_axis("camera_look_right", JOY_AXIS_RIGHT_X, 1.0)
	_add_joy_axis("camera_look_up", JOY_AXIS_RIGHT_Y, -1.0)
	_add_joy_axis("camera_look_down", JOY_AXIS_RIGHT_Y, 1.0)
	_add_joy_button("fire", JOY_BUTTON_RIGHT_SHOULDER)
	_add_joy_button("jump", JOY_BUTTON_A)
	_add_joy_button("interact", JOY_BUTTON_X)
	_add_joy_button("sprint", JOY_BUTTON_LEFT_STICK)


func _ensure_action(action: StringName) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)


func _add_key(action: StringName, keycode: Key) -> void:
	_ensure_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	if InputMap.action_has_event(action, ev):
		return
	InputMap.action_add_event(action, ev)


func _add_mouse(action: StringName, button: MouseButton) -> void:
	_ensure_action(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	if InputMap.action_has_event(action, ev):
		return
	InputMap.action_add_event(action, ev)


func _add_joy_axis(action: StringName, axis: JoyAxis, value: float) -> void:
	_ensure_action(action)
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = value
	InputMap.action_add_event(action, ev)


func _add_joy_button(action: StringName, button: JoyButton) -> void:
	_ensure_action(action)
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)
