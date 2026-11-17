extends Node3D
## A glowing marker that starts a mission when the player walks into it.

@export var mission_id := "m1_cattle"
@export var title := "The Missing Herd"
@export var giver := "Rancher Holt"

var _t := 0.0
var _beam: MeshInstance3D
var _label: Label3D
var _started := false


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("mission_markers")
	_beam = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.55
	cm.bottom_radius = 0.55
	cm.height = 7.0
	cm.radial_segments = 16
	cm.cap_top = false
	cm.cap_bottom = false
	_beam.mesh = cm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.82, 0.35, 0.28)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_beam.material_override = m
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.position.y = 3.5
	add_child(_beam)
	_label = Label3D.new()
	_label.text = title
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 56
	_label.modulate = Color(1.0, 0.9, 0.62)
	_label.outline_modulate = Color(0.1, 0.07, 0.04)
	_label.outline_size = 10
	_label.position.y = 7.4
	_label.no_depth_test = false
	add_child(_label)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.8, 0.4)
	light.light_energy = 1.6
	light.omni_range = 6.0
	add_child(light)
	if GameState.completed_missions.has(mission_id):
		queue_free()


func _process(delta: float) -> void:
	_t += delta
	if GameState.completed_missions.has(mission_id):
		# that job is done: stop advertising it
		visible = false
		set_process(false)
		remove_from_group("interactable")
		return
	if _beam:
		_beam.rotation.y += delta * 0.4
	if _label:
		_label.position.y = 7.4 + sin(_t * 1.6) * 0.12


func interact_prompt() -> String:
	if _started:
		return ""
	if GameState.completed_missions.has(mission_id):
		return ""
	return "Start mission: %s  [E]" % title


func interact(_player: Node) -> void:
	if _started:
		return
	if GameState.completed_missions.has(mission_id):
		return
	_started = true
	var mm := get_tree().get_first_node_in_group("mission_manager")
	if mm and mm.has_method("start_mission"):
		mm.start_mission(mission_id)
	else:
		GameState.mission_started.emit(mission_id, title)
	queue_free()
