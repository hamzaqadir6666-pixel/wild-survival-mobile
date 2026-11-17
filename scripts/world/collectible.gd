extends Node3D
## A findable relic glinting in the world. Walk close and press E to collect.

@export var item_id := "relic_0"
@export var label := "Silver Spur"

var _t := 0.0
var _taken := false
var _mesh: MeshInstance3D


func _ready() -> void:
	add_to_group("interactable")
	_mesh = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.3, 0.16, 0.16)
	_mesh.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.95, 0.78, 0.32)
	m.metallic = 0.9
	m.roughness = 0.18
	m.emission_enabled = true
	m.emission = Color(1.0, 0.8, 0.35)
	m.emission_energy_multiplier = 0.6
	_mesh.material_override = m
	add_child(_mesh)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.85, 0.5)
	light.light_energy = 1.2
	light.omni_range = 3.2
	add_child(light)
	if GameState.collectibles.has(item_id):
		queue_free()


func _process(delta: float) -> void:
	_t += delta
	_mesh.rotation.y += delta * 1.2
	_mesh.position.y = sin(_t * 2.0) * 0.08


func interact_prompt() -> String:
	return "Pick up %s  [E]" % label


func interact(_player: Node) -> void:
	if _taken:
		return
	_taken = true
	GameState.add_collectible(item_id, label)
	AudioManager.play_sfx("metal_click", 1.2, -4.0)
	queue_free()
