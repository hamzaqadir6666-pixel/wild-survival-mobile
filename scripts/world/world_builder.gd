extends Node3D
## Assembles the whole open world at runtime: terrain, sky, water, vegetation,
## the town, ranches, camps, bandit hideouts plus wildlife and weather.

const CHARACTER_PATHS := {
	"player": "res://assets/characters/rigged/player_cowboy.glb",
	"resident_m": "res://assets/characters/rigged/npc_peasant_male.glb",
	"resident_f": "res://assets/characters/rigged/npc_peasant_female.glb",
	"ranger_f": "res://assets/characters/rigged/npc_ranger_female.glb",
	"bandit": "res://assets/characters/rigged/npc_bandit.glb",
	"animal_horse": "res://assets/animals/Horse.gltf",
	"animal_deer": "res://assets/animals/Deer.gltf",
	"animal_stag": "res://assets/animals/Stag.gltf",
	"animal_wolf": "res://assets/animals/Wolf.gltf",
	"animal_fox": "res://assets/animals/Fox.gltf",
	"animal_cow": "res://assets/animals/Cow.gltf",
	"animal_bull": "res://assets/animals/Bull.gltf",
}

## Authoritative actor scenes (collision shapes + groups + camera rig live there).
const ACTOR_SCENES := {
	"player": "res://scenes/player/player.tscn",
	"horse": "res://scenes/animals/horse.tscn",
	"animal": "res://scenes/animals/animal.tscn",
	"npc": "res://scenes/npcs/npc.tscn",
}

@onready var terrain_holder: Node3D = $Terrain
@onready var vegetation_holder: Node3D = $Vegetation
@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var sun: DirectionalLight3D = $Sun
@onready var moon: DirectionalLight3D = $Moon
@onready var water: MeshInstance3D = $Water
@onready var props_root: Node3D = $Props
@onready var npc_root: Node3D = $NPCs
@onready var animal_root: Node3D = $Animals
@onready var poi_root: Node3D = $PointsOfInterest

var terrain: Node3D
var vegetation: Node3D
var day_night: Node
var weather: Node
var clock: Node
var town: Node3D
var horse: Node3D
var player: Node3D
var sky_material: ShaderMaterial

var _loaded_models: Dictionary = {}
var _pois: Array = []
## Omni lights are the most expensive thing we add per lamp; cap them and only
## switch them on at night.
const MAX_LAMP_LIGHTS := 6
var _lamp_lights: Array[OmniLight3D] = []
var _lamps_on := false


func _ready() -> void:
	add_to_group("world")
	_setup_environment()
	_build_terrain()
	_build_water()
	_build_vegetation()
	_build_clock_and_weather()
	_build_town()
	_build_farm()
	_build_camps()
	_build_bandit_camp()
	_build_landmarks()
	_spawn_player()
	_spawn_horse()
	_spawn_npcs()
	_spawn_wildlife()
	GameState.notify("Welcome to Red Hollow Territory, %s." % GameState.PLAYER_NAME, 4.0)


func _setup_environment() -> void:
	var sky := Sky.new()
	sky_material = ShaderMaterial.new()
	sky_material.shader = load("res://shaders/sky.gdshader")
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	var env: Environment = world_env.environment
	if env == null:
		env = load("res://resources/default_environment.tres")
		world_env.environment = env
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	sky_material.set_shader_parameter("cloud_coverage", 0.3)


func _build_terrain() -> void:
	terrain = Node3D.new()
	terrain.name = "Heightfield"
	terrain.set_script(load("res://scripts/world/terrain_generator.gd"))
	terrain_holder.add_child(terrain)
	if terrain.has_method("generate"):
		pass  # terrain builds itself in _ready()


func _build_water() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(620, 620)
	plane.subdivide_width = 96
	plane.subdivide_depth = 96
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/water.gdshader")
	mat.set_shader_parameter("normal_map_a", load("res://assets/textures/water_normal.png"))
	mat.set_shader_parameter("normal_map_b", load("res://assets/textures/water_normal.png"))
	water.mesh = plane
	water.material_override = mat
	water.position = Vector3(0, 1.2, 0)
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	# place the lake in the southern basin
	water.position.y = 1.0


func _build_vegetation() -> void:
	vegetation = Node3D.new()
	vegetation.name = "Scatter"
	vegetation.set_script(load("res://scripts/world/vegetation.gd"))
	vegetation_holder.add_child(vegetation)
	if vegetation.has_method("setup"):
		vegetation.setup(terrain)


func _build_clock_and_weather() -> void:
	day_night = Node.new()
	day_night.name = "DayNightCycle"
	day_night.set_script(load("res://scripts/world/day_night_cycle.gd"))
	add_child(day_night)
	day_night.setup(sun, moon, world_env)
	clock = day_night
	weather = Node.new()
	weather.name = "WeatherSystem"
	weather.set_script(load("res://scripts/world/weather_system.gd"))
	add_child(weather)
	weather.setup(day_night, world_env, sky_material)
	weather.set_weather(GameState.weather_state, true)


func _process(_delta: float) -> void:
	if _lamp_lights.is_empty() or day_night == null:
		return
	var night := false
	if day_night.has_method("is_night"):
		night = bool(day_night.is_night())
	if night == _lamps_on:
		return
	_lamps_on = night
	for l in _lamp_lights:
		if is_instance_valid(l):
			l.visible = night


func get_clock() -> Node:
	return clock


func terrain_height(x: float, z: float) -> float:
	if terrain and terrain.has_method("height_at"):
		return terrain.height_at(x, z)
	return 0.0


func spawn_position() -> Vector3:
	var p := Vector3(-40, 0, 6)
	p.y = terrain_height(p.x, p.z) + 0.15
	return p


func _place_prop(path: String, pos: Vector3, rot_y: float = 0.0, scale: float = 1.0, group: String = "props", shadow: bool = true) -> Node3D:
	var ps: PackedScene = _loaded_models.get(path)
	if ps == null:
		if not ResourceLoader.exists(path):
			return null
		ps = load(path)
		_loaded_models[path] = ps
	var inst: Node3D = ps.instantiate()
	inst.rotation.y = rot_y
	var holder = props_root
	if group == "a":
		holder = props_root
	holder.add_child(inst)
	inst.global_position = pos
	inst.scale = Vector3.ONE * scale
	if not shadow:
		for c in inst.find_children("*", "MeshInstance3D", true, false):
			(c as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return inst


func _load_model(path: String) -> Node3D:
	if not ResourceLoader.exists(path):
		push_warning("Missing model: " + path)
		return null
	var ps: PackedScene = load(path)
	if ps == null:
		return null
	var inst = ps.instantiate()
	return inst as Node3D


## ---------------------------------------------------------------------------
## Town: saloon, general store, sheriff's office, stable, houses, boardwalk.
## ---------------------------------------------------------------------------
func _build_town() -> void:
	town = Node3D.new()
	town.name = "Dustwater"
	town.add_to_group("town")
	add_child(town)
	var base := Vector3(-34, 0, -14)
	base.y = terrain_height(base.x, base.z)
	town.global_position = base

	var house := "res://assets/props/kenney/hexagon/building-house.glb"
	var cabin := "res://assets/props/kenney/hexagon/building-cabin.glb"
	var mill := "res://assets/props/kenney/hexagon/building-mill.glb"
	var market := "res://assets/props/kenney/hexagon/building-market.glb"
	var tower := "res://assets/props/kenney/hexagon/building-tower.glb"

	# main street runs east-west
	var road := "res://assets/props/kenney/hexagon/dirt.glb"
	for i in 9:
		var x := -26.0 + i * 6.5
		_place_prop(road, Vector3(x, terrain_height(x, -14) + 0.02, -14), 0.0, 1.0, "a", false)
		_place_prop(road, Vector3(x, terrain_height(x, -20) + 0.02, -20), 0.0, 1.0, "a", false)

	# buildings on both sides of main street
	_place_prop(house, Vector3(-44, terrain_height(-44, -6) + 0.2, -6), PI, 3.4)
	_place_prop(market, Vector3(-30, terrain_height(-30, -5) + 0.2, -5), PI, 3.6)
	_place_prop(tower, Vector3(-16, terrain_height(-16, -6) + 0.2, -6), PI, 3.2)
	_place_prop(mill, Vector3(0, terrain_height(0, -7) + 0.2, -7), PI, 3.4)
	_place_prop(house, Vector3(14, terrain_height(14, -5) + 0.2, -5), PI, 3.2)

	_place_prop(cabin, Vector3(-40, terrain_height(-40, -24) + 0.2, -24), 0.0, 3.0)
	_place_prop(house, Vector3(-24, terrain_height(-24, -25) + 0.2, -25), 0.0, 3.2)
	_place_prop(house, Vector3(-8, terrain_height(-8, -25) + 0.2, -25), 0.0, 3.4)
	_place_prop(cabin, Vector3(8, terrain_height(8, -24) + 0.2, -24), 0.0, 3.0)
	_place_prop(house, Vector3(22, terrain_height(22, -25) + 0.2, -25), 0.0, 3.2)

	# boardwalk-style detailing: barrels, crates, benches, lamps, signs
	var barrels := "res://assets/props/kenney/survival/barrel.glb"
	var crates := "res://assets/props/kenney/survival/box.glb"
	var bench := "res://assets/props/kenney/furniture/bench.glb"
	var sign := "res://assets/props/kenney/nature/sign.glb"
	var fence := "res://assets/props/kenney/nature/fence_simple.glb"
	for i in 12:
		var x := -40.0 + i * 5.0
		var z := -18.5 if i % 2 == 0 else -10.5
		var y := terrain_height(x, z)
		if i % 3 == 0:
			_place_prop(barrels, Vector3(x + 1.2, y + 0.1, z), randf() * TAU, 2.0)
		elif i % 3 == 1:
			_place_prop(crates, Vector3(x + 1.2, y + 0.1, z), randf() * TAU, 2.0)
		if i % 4 == 0:
			_place_prop(bench, Vector3(x, y + 0.05, z + 1.0), PI * (0.5 if z < -14 else -0.5), 2.0)
	_place_prop(sign, Vector3(-30, terrain_height(-30, -17) + 0.1, -17), 0.0, 3.6)

	# hitching posts + street lamps (lights added below)
	for i in 6:
		var x := -38.0 + i * 10.0
		var y := terrain_height(x, -17.5)
		_place_prop(fence, Vector3(x, y + 0.05, -17.5), 0.0, 2.2, "props", false)
		_add_street_lamp(Vector3(x, y + 0.1, -11.0))

	# stable & corral fence line
	var stable := "res://assets/props/kenney/hexagon/building-farm.glb"
	_place_prop(stable, Vector3(30, terrain_height(30, -18) + 0.2, -18), -PI * 0.5, 3.0)
	for i in 8:
		var x := 36.0 + (i % 4) * 3.2
		var z := -8.0 + int(i / 4) * 8.0
		_place_prop(fence, Vector3(x, terrain_height(x, z) + 0.05, z), PI * 0.5, 2.0, "props", false)

	_build_mission_markers()


func _add_street_lamp(pos: Vector3) -> void:
	var pole := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.06
	pm.bottom_radius = 0.09
	pm.height = 3.4
	pole.mesh = pm
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.18, 0.13, 0.09)
	wood.roughness = 0.8
	pole.material_override = wood
	add_child(pole)
	pole.global_position = pos + Vector3(0, 1.7, 0)
	var head := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.34, 0.4, 0.34)
	head.mesh = bm
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(1.0, 0.82, 0.5)
	glass.emission_enabled = true
	glass.emission = Color(1.0, 0.75, 0.42)
	glass.emission_energy_multiplier = 2.4
	head.material_override = glass
	add_child(head)
	head.global_position = pos + Vector3(0, 3.5, 0)
	# Lamps burn brightest after dark; the day/night cycle toggles this flag.
	if _lamp_lights.size() >= MAX_LAMP_LIGHTS:
		return
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.76, 0.45)
	light.light_energy = 2.4
	light.omni_range = 11.0
	light.omni_attenuation = 1.4
	light.shadow_enabled = false
	add_child(light)
	light.global_position = pos + Vector3(0, 3.3, 0)
	_lamp_lights.append(light)


func _build_farm() -> void:
	var farm := Node3D.new()
	farm.name = "BarrettRanch"
	add_child(farm)
	var farm_pos := Vector3(96, 0, 34)
	farm_pos.y = terrain_height(farm_pos.x, farm_pos.z)
	farm.global_position = farm_pos
	var barn := "res://assets/props/kenney/hexagon/building-farm.glb"
	var house := "res://assets/props/kenney/hexagon/building-cabin.glb"
	_place_prop(barn, farm_pos + Vector3(0, 0.2, 0), 0.4, 4.0)
	_place_prop(house, farm_pos + Vector3(16, 0.2, 12), -0.6, 3.0)
	# crop rows + fence
	var crops := "res://assets/props/kenney/nature/crops_cornStageD.glb"
	var fence := "res://assets/props/kenney/nature/fence_planks.glb"
	for i in 5:
		for j in 3:
			var p := farm_pos + Vector3(-12 + i * 3.0, 0.05, 10 + j * 4.0)
			p.y = terrain_height(p.x, p.z)
			_place_prop(crops, p, 0.0, 2.2, "props", false)
	for i in 10:
		var ang := TAU * i / 10.0
		var p := farm_pos + Vector3(cos(ang) * 24.0, 0, sin(ang) * 24.0)
		p.y = terrain_height(p.x, p.z) + 0.05
		_place_prop(fence, p, ang + PI * 0.5, 2.0, "props", false)
	for i in 4:
		var p := farm_pos + Vector3(randf_range(-8, 8), 0, randf_range(-8, 8))
		p.y = terrain_height(p.x, p.z)
		_spawn_animal("animal_cow", p, false, "Cow")


func _build_camps() -> void:
	var camp_positions := [
		Vector3(-110, 0, 60), Vector3(120, 0, -150), Vector3(-190, 0, -60), Vector3(60, 0, 150)
	]
	var names := ["Hunter's Rest", "Dry Gulch Camp", "Pine Hollow Camp", "Coyote Springs"]
	for i in camp_positions.size():
		var p: Vector3 = camp_positions[i]
		p.y = terrain_height(p.x, p.z)
		var camp := Node3D.new()
		camp.name = "Camp_%d" % i
		add_child(camp)
		camp.global_position = p
		_place_prop("res://assets/props/kenney/nature/tent_detailedOpen.glb", p + Vector3(0, 0.05, 0), 0.3, 3.6)
		_place_prop("res://assets/props/kenney/nature/campfire_logs.glb", p + Vector3(3.4, 0.05, 1.2), 0.0, 2.4)
		_place_prop("res://assets/props/kenney/nature/log.glb", p + Vector3(4.6, 0.2, 3.0), 0.4, 2.0)
		_place_prop("res://assets/props/kenney/survival/bedroll.glb", p + Vector3(-1.4, 0.1, 1.8), 1.2, 2.0)
		var fire_light := OmniLight3D.new()
		fire_light.light_color = Color(1.0, 0.6, 0.25)
		fire_light.light_energy = 2.2
		fire_light.omni_range = 9.0
		fire_light.shadow_enabled = false
		add_child(fire_light)
		fire_light.global_position = p + Vector3(3.4, 0.6, 1.2)
		# a hunter NPC at the camp
		var npc := _spawn_npc("resident_m", p + Vector3(2.0, 0.2, -3.0), "Trapper %s" % ["Hollis", "Mabe", "Dunn", "Cato"][i], 4)
		if npc and npc.has_method("set_schedule"):
			var pts: Array[Vector3] = []
			for k in 3:
				var a := TAU * k / 3.0
				pts.append(p + Vector3(cos(a) * 6.0, 0, sin(a) * 6.0))
			npc.set_schedule(pts)
		_pois.append({"name": names[i], "pos": p, "kind": "camp"})


func _build_bandit_camp() -> void:
	var pos := Vector3(170, 0, -190)
	pos.y = terrain_height(pos.x, pos.z)
	var camp := Node3D.new()
	camp.name = "RattlerGulch"
	camp.add_to_group("bandit_camp")
	add_child(camp)
	camp.global_position = pos
	_place_prop("res://assets/props/kenney/nature/tent_smallClosed.glb", pos + Vector3(-4, 0.05, 0), 0.2, 3.2)
	_place_prop("res://assets/props/kenney/nature/tent_smallClosed.glb", pos + Vector3(5, 0.05, 1.5), -0.6, 3.2)
	_place_prop("res://assets/props/kenney/nature/campfire_stones.glb", pos + Vector3(0, 0.05, -2), 0.0, 2.2)
	_place_prop("res://assets/props/kenney/survival/barrel.glb", pos + Vector3(7.5, 0.1, -3), 0.0, 2.0)
	_place_prop("res://assets/props/kenney/survival/box-large.glb", pos + Vector3(-6.5, 0.1, 3.5), 0.4, 2.0)
	_place_prop("res://assets/props/kenney/nature/fence_simpleHigh.glb", pos + Vector3(-9, 0.05, -6), 0.0, 2.4, "props", false)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.62, 0.28)
	light.light_energy = 1.8
	light.omni_range = 10.0
	add_child(light)
	light.global_position = pos + Vector3(0, 0.8, -2)
	var names := ["Rattler Jack", "Mule Ferris", "Sally Two-Guns", "Dusty Crane", "Hob Kettle"]
	for i in 5:
		var off := Vector3(cos(TAU * i / 5.0) * 6.0, 0.2, sin(TAU * i / 5.0) * 6.0)
		_spawn_npc("bandit", pos + off, names[i], 2)
	_pois.append({"name": "Rattler Gulch (Bandit Camp)", "pos": pos, "kind": "bandit"})


func _build_landmarks() -> void:
	# abandoned mine entrance, wooden bridge, church ruins, waterfall overlook
	var mine := Vector3(210, 0, -60)
	mine.y = terrain_height(mine.x, mine.z)
	_place_prop("res://assets/props/kenney/survival/structure-metal-doorway.glb", mine + Vector3(0, 0.2, 0), 0.2, 3.0)
	_place_prop("res://assets/props/kenney/survival/resource-planks.glb", mine + Vector3(3, 0.2, 2), 0.5, 2.4)
	_place_prop("res://assets/props/kenney/survival/chest.glb", mine + Vector3(-1.5, 0.3, 1.2), 0.4, 1.6)
	_pois.append({"name": "Dustwater Mine (abandoned)", "pos": mine, "kind": "mine"})

	var bridge_pos := Vector3(-120, 0, 40)
	bridge_pos.y = terrain_height(bridge_pos.x, bridge_pos.z)
	for i in 4:
		_place_prop("res://assets/props/kenney/nature/bridge_wood.glb", bridge_pos + Vector3(0, 0.1, i * 4.0 - 6.0), PI * 0.5, 2.6)
	_pois.append({"name": "Old Timer's Bridge", "pos": bridge_pos, "kind": "bridge"})

	var ruin := Vector3(-200, 0, -160)
	ruin.y = terrain_height(ruin.x, ruin.z)
	for i in 6:
		_place_prop("res://assets/props/kenney/building/wall.glb", ruin + Vector3(i * 4.0 - 10.0, 0.1, 0), 0.0, 3.0)
	_place_prop("res://assets/props/kenney/building/wall-doorway-square.glb", ruin + Vector3(2, 0.1, 0), 0.0, 3.0)
	_pois.append({"name": "Hollow Chapel Ruins", "pos": ruin, "kind": "ruin"})

	var fall := Vector3(-60, 0, -230)
	fall.y = terrain_height(fall.x, fall.z)
	_place_prop("res://assets/props/kenney/nature/cliff_waterfall_stone.glb", fall, 0.0, 4.0)
	_pois.append({"name": "Silverthread Falls", "pos": fall, "kind": "waterfall"})

	# hidden collectibles scattered around
	var collectibles := [
		Vector3(-150, 0, 100), Vector3(80, 0, -120), Vector3(-240, 0, 20),
		Vector3(140, 0, 120), Vector3(-20, 0, -200), Vector3(220, 0, 60),
	]
	for i in collectibles.size():
		var p: Vector3 = collectibles[i]
		p.y = terrain_height(p.x, p.z) + 0.4
		var c := Node3D.new()
		c.set_script(load("res://scripts/world/collectible.gd"))
		c.set("item_id", "relic_%d" % i)
		c.set("label", ["Silver Spur", "Bowie Knife", "Gold Watch", "Canteen", "Arrowhead", "Wanted Poster"][i])
		add_child(c)
		c.global_position = p


func _build_mission_markers() -> void:
	var marker_scene := load("res://scripts/world/mission_marker.gd")
	var defs := [
		{"id": "m1_cattle", "title": "The Missing Herd", "pos": Vector3(96, 0, 34), "giver": "Rancher Holt"},
		{"id": "m2_bandits", "title": "Rattler Gulch", "pos": Vector3(170, 0, -190), "giver": "Sheriff Ambrose"},
		{"id": "m3_supplies", "title": "Medicine Run", "pos": Vector3(-30, 0, -5), "giver": "Doc Whitlow"},
	]
	for d in defs:
		var p: Vector3 = d["pos"]
		p.y = terrain_height(p.x, p.z) + 1.2
		var m := Node3D.new()
		m.set_script(marker_scene)
		m.set("mission_id", d["id"])
		m.set("title", d["title"])
		m.set("giver", d["giver"])
		add_child(m)
		m.global_position = p
		_pois.append({"name": d["title"], "pos": p, "kind": "mission"})


## ---------------------------------------------------------------------------
## Characters
## ---------------------------------------------------------------------------
func _spawn_player() -> void:
	# read the saved position before _ready() runs on the new node
	var saved := GameState.player_position
	var has_saved := not GameState.is_new_game and saved != Vector3.ZERO
	var holder: Node3D = load(ACTOR_SCENES["player"]).instantiate()
	holder.name = "Player"
	add_child(holder)
	holder.global_position = spawn_position()
	var model := _load_model(CHARACTER_PATHS["player"])
	if model == null:
		model = _load_model(CHARACTER_PATHS["resident_m"])
	if model:
		holder.setup(model)
	player = holder
	if has_saved:
		holder.global_position = saved + Vector3(0, 0.25, 0)
		holder.set("yaw", GameState.player_rotation)
		var mr := holder.get_node_or_null("ModelRoot")
		if mr:
			(mr as Node3D).rotation.y = GameState.player_rotation


func _spawn_horse() -> void:
	var holder: Node3D = load(ACTOR_SCENES["horse"]).instantiate()
	holder.name = "Juniper"
	add_child(holder)
	var spawn := spawn_position() + Vector3(6.0, 0.5, 4.0)
	spawn.y = terrain_height(spawn.x, spawn.z) + 0.6
	holder.global_position = spawn
	var model := _load_model(CHARACTER_PATHS["animal_horse"])
	if model:
		holder.setup(model)
	horse = holder
	if not GameState.is_new_game and GameState.horse_position != Vector3.ZERO:
		holder.global_position = GameState.horse_position + Vector3(0, 0.3, 0)
		holder.rotation.y = GameState.horse_rot
		var hr := holder.get_node_or_null("ModelRoot")
		if hr:
			(hr as Node3D).rotation.y = GameState.horse_rot


func _spawn_npc(key: String, pos: Vector3, display_name: String, role: int) -> Node3D:
	var holder: Node3D = load(ACTOR_SCENES["npc"]).instantiate()
	holder.name = display_name.replace(" ", "")
	npc_root.add_child(holder)
	holder.global_position = pos
	var model := _load_model(CHARACTER_PATHS.get(key, CHARACTER_PATHS["resident_m"]))
	if model:
		holder.setup(model, display_name, role)
	else:
		holder.set("display_name", display_name)
		holder.set("role", role)
	return holder


func _spawn_npcs() -> void:
	var town_center := Vector3(-34, 0, -14)
	var residents := [
		["resident_m", "Elias Boone", 0],
		["resident_f", "Martha Boone", 0],
		["resident_m", "Gus the Barber", 0],
		["ranger_f", "Lily Vance", 1],
		["resident_m", "Sheriff Ambrose", 3],
		["resident_m", "Doc Whitlow", 1],
		["resident_f", "Widow Ashby", 0],
		["resident_m", "Walt the Clerk", 1],
		["resident_m", "Cobb the Stablehand", 0],
		["ranger_f", "Miss Delphine", 1],
	]
	for i in residents.size():
		var d: Array = residents[i]
		var ang := TAU * i / residents.size()
		var p := town_center + Vector3(cos(ang) * 12.0, 0, sin(ang) * 6.0)
		p.y = terrain_height(p.x, p.z) + 0.1
		var npc := _spawn_npc(str(d[0]), p, str(d[1]), int(d[2]))
		if npc and npc.has_method("set_schedule"):
			var pts: Array[Vector3] = []
			for k in 4:
				var a2 := TAU * (k * 3 + i) / 8.0
				var q := town_center + Vector3(cos(a2) * randf_range(8.0, 22.0), 0, sin(a2) * randf_range(4.0, 9.0))
				q.y = terrain_height(q.x, q.z) + 0.1
				pts.append(q)
			npc.set_schedule(pts)


func _spawn_wildlife() -> void:
	var groups := [
		{"key": "animal_deer", "name": "Deer", "count": 14, "predator": false, "speed": 9.5},
		{"key": "animal_stag", "name": "Stag", "count": 6, "predator": false, "speed": 9.0},
		{"key": "animal_wolf", "name": "Wolf", "count": 7, "predator": true, "speed": 10.5},
		{"key": "animal_fox", "name": "Fox", "count": 8, "predator": false, "speed": 8.0},
		{"key": "animal_bull", "name": "Bull", "count": 3, "predator": true, "speed": 6.0},
	]
	for g in groups:
		for i in int(g["count"]):
			var p := _random_wild_point()
			_spawn_animal(str(g["key"]), p, bool(g["predator"]), str(g["name"]), float(g["speed"]))


func _random_wild_point() -> Vector3:
	for attempt in 30:
		var x := randf_range(-250.0, 250.0)
		var z := randf_range(-250.0, 250.0)
		if Vector2(x, z).distance_to(Vector2(-34, -14)) < 60.0:
			continue
		var y := terrain_height(x, z)
		if y < 2.0 or y > 80.0:
			continue
		return Vector3(x, y + 0.4, z)
	return Vector3(60, terrain_height(60, 60) + 0.4, 60)


func _spawn_animal(key: String, pos: Vector3, predator: bool, animal_name: String, speed: float = 9.0) -> Node3D:
	var holder: Node3D = load(ACTOR_SCENES["animal"]).instantiate()
	holder.name = animal_name + str(randi() % 999)
	holder.set("run_speed", speed)
	holder.set("max_health", 120.0 if animal_name == "Bull" else 60.0)
	animal_root.add_child(holder)
	holder.global_position = pos
	var model := _load_model(CHARACTER_PATHS.get(key, ""))
	if model:
		holder.setup(model, animal_name, predator)
	return holder


func points_of_interest() -> Array:
	return _pois
