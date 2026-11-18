extends Node3D

var world: VoxelWorld
var player: Explorer
var hud: Variant
var sun: DirectionalLight3D
var environment: Environment

func _ready() -> void:
 _setup_environment()
 player = Explorer.new()
 player.name = "Explorer"
 add_child(player)
 world = VoxelWorld.new()
 world.name = "World"
 player.world = world
 world.generation_finished.connect(_on_world_ready)
 hud = preload("res://scripts/hud.gd").new()
 hud.game = self
 hud.player = player
 hud.world = world
 add_child(hud)
 world.generation_progress.connect(hud.update_loading)
 add_child(world)

func _setup_environment() -> void:
 environment = Environment.new()
 var sky := Sky.new()
 var sky_material := ProceduralSkyMaterial.new()
 sky_material.sky_top_color = Color("4176a5")
 sky_material.sky_horizon_color = Color("b9dce4")
 sky_material.ground_bottom_color = Color("506c5b")
 sky_material.ground_horizon_color = Color("b9dce4")
 sky_material.sun_angle_max = 18.0
 sky.sky_material = sky_material
 environment.background_mode = Environment.BG_SKY
 environment.sky = sky
 environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
 environment.ambient_light_color = Color("c4d9e3")
 environment.ambient_light_energy = 0.7
 environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
 environment.fog_enabled = true
 environment.fog_light_color = Color("b2d1db")
 environment.fog_density = 0.008
 var env_node := WorldEnvironment.new()
 env_node.environment = environment
 add_child(env_node)
 sun = DirectionalLight3D.new()
 sun.rotation_degrees = Vector3(-55,-35,0)
 sun.light_color = Color("fff1d1")
 sun.light_energy = 1.0
 sun.shadow_enabled = true
 add_child(sun)
 # A low translucent water surface gives the valleys a calm shoreline.
 var water := MeshInstance3D.new()
 var plane := PlaneMesh.new()
 plane.size = Vector2(96,96)
 water.mesh = plane
 water.position.y = 9.15
 var water_mat := StandardMaterial3D.new()
 water_mat.albedo_color = Color(0.23,0.57,0.67,0.68)
 water_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
 water_mat.roughness = 0.25
 water_mat.metallic = 0.05
 water_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
 water.material_override = water_mat
 add_child(water)

func _on_world_ready() -> void:
 player.respawn()
 player.can_move = true
 hud.finish_loading()
 if not player.touch_enabled:
  Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
