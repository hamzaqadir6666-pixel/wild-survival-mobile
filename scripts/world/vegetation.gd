extends Node3D
## Scatters grass, trees, bushes, rocks and desert plants across the terrain
## using MultiMeshInstance3D for cheap instancing with distance fading.

@export var grass_instances := 26000
@export var tree_instances := 1100
@export var bush_instances := 1400
@export var rock_instances := 900
@export var cactus_instances := 200
@export var grass_radius := 58.0

var terrain: Node3D
var _grass_mm: MultiMeshInstance3D
var _tree_mms: Array[MultiMeshInstance3D] = []
var _rng := RandomNumberGenerator.new()


func setup(p_terrain: Node3D) -> void:
	terrain = p_terrain
	_rng.seed = 918273
	_build_grass()
	_build_trees()
	_build_bushes()
	_build_rocks()
	_build_cacti()


func _height(x: float, z: float) -> float:
	if terrain and terrain.has_method("height_at"):
		return terrain.height_at(x, z)
	return 0.0


func _biome(x: float, z: float) -> Dictionary:
	if terrain and terrain.has_method("biome_at"):
		return terrain.biome_at(x, z)
	return {"grass": 1.0, "forest": 0.0, "desert": 0.0, "rock": 0.0}


func _slope(x: float, z: float) -> float:
	var d := 1.5
	var hx := _height(x + d, z) - _height(x - d, z)
	var hz := _height(x, z + d) - _height(x, z - d)
	return clampf(Vector2(hx, hz).length() / (2.0 * d), 0.0, 1.0)


func _build_grass() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.85, 0.62)
	quad.center_offset = Vector3(0, 0.31, 0)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/grass_blades.gdshader")
	mat.set_shader_parameter("grass_tex", load("res://assets/textures/grass_card.png"))
	mat.set_shader_parameter("fade_start", 34.0)
	mat.set_shader_parameter("fade_end", 58.0)
	quad.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = quad
	var list: Array[Transform3D] = []
	var colors: Array[Color] = []
	var center := Vector2(-34, -14)
	var tries := 0
	while list.size() < grass_instances and tries < grass_instances * 6:
		tries += 1
		var x := _rng.randf_range(-280.0, 280.0)
		var z := _rng.randf_range(-280.0, 280.0)
		var b := _biome(x, z)
		var density: float = float(b["grass"]) * 0.95 + float(b["forest"]) * 0.55
		if _rng.randf() > density:
			continue
		if _slope(x, z) > 0.45:
			continue
		var y := _height(x, z)
		if y < 1.6:
			continue
		if terrain and terrain.has_method("river_distance") and terrain.river_distance(x, z) < 5.0:
			continue
		var s := _rng.randf_range(0.7, 1.5)
		var basis := Basis(Vector3.UP, _rng.randf_range(0.0, TAU)).scaled(Vector3(s, s * _rng.randf_range(0.8, 1.3), s))
		list.append(Transform3D(basis, Vector3(x, y - 0.05, z)))
		var tint := Color(1, 1, 1, 1).lerp(Color(1.15, 1.1, 0.85, 1), _rng.randf() * float(b["desert"]))
		colors.append(tint)
	mm.instance_count = list.size()
	for i in list.size():
		mm.set_instance_transform(i, list[i])
		mm.set_instance_color(i, colors[i])
	_grass_mm = MultiMeshInstance3D.new()
	_grass_mm.name = "GrassField"
	_grass_mm.multimesh = mm
	_grass_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_grass_mm.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_grass_mm.visibility_range_end = 62.0
	_grass_mm.visibility_range_end_margin = 8.0
	_grass_mm.extra_cull_margin = 4.0
	add_child(_grass_mm)


func _load_mesh(path: String) -> Mesh:
	var ps: PackedScene = load(path)
	if ps == null:
		return null
	var inst := ps.instantiate()
	var mi := _find_mesh_instance(inst)
	var mesh: Mesh = null
	if mi and mi.mesh:
		mesh = mi.mesh
	inst.free()
	return mesh


func _find_mesh_instance(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var r := _find_mesh_instance(c)
		if r:
			return r
	return null


func _make_tree_material(mesh: Mesh, tint: Color) -> void:
	# re-materialise Kenney's unlit vertex-coloured meshes into PBR materials
	for i in mesh.get_surface_count():
		var m := StandardMaterial3D.new()
		m.albedo_color = tint
		m.roughness = 0.88
		m.metallic = 0.0
		m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
		m.vertex_color_use_as_albedo = true
		m.cull_mode = BaseMaterial3D.CULL_BACK
		mesh.surface_set_material(i, m)


func _build_trees() -> void:
	var kinds := [
		{"path": "res://assets/props/kenney/nature/tree_pineTallA.glb", "w": 3.0, "scale": 6.5, "tint": Color(0.30, 0.42, 0.26)},
		{"path": "res://assets/props/kenney/nature/tree_pineTallB.glb", "w": 2.5, "scale": 6.0, "tint": Color(0.26, 0.38, 0.24)},
		{"path": "res://assets/props/kenney/nature/tree_pineRoundA.glb", "w": 2.0, "scale": 5.5, "tint": Color(0.33, 0.45, 0.25)},
		{"path": "res://assets/props/kenney/nature/tree_detailed.glb", "w": 3.0, "scale": 5.2, "tint": Color(0.35, 0.46, 0.22)},
		{"path": "res://assets/props/kenney/nature/tree_oak.glb", "w": 2.5, "scale": 5.0, "tint": Color(0.38, 0.44, 0.20)},
		{"path": "res://assets/props/kenney/nature/tree_tall.glb", "w": 2.0, "scale": 6.0, "tint": Color(0.30, 0.40, 0.24)},
		{"path": "res://assets/props/kenney/nature/tree_thin.glb", "w": 1.5, "scale": 5.6, "tint": Color(0.28, 0.36, 0.22)},
		{"path": "res://assets/props/kenney/nature/tree_plateau.glb", "w": 1.0, "scale": 5.0, "tint": Color(0.36, 0.40, 0.22)},
	]
	var total_w := 0.0
	for k in kinds:
		total_w += float(k["w"])
	for k in kinds:
		var mesh := _load_mesh(k["path"])
		if mesh == null:
			continue
		_make_tree_material(mesh, Color(1, 1, 1))
		var share := int(float(k["w"]) / total_w * tree_instances)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = mesh
		var list: Array[Transform3D] = []
		var cols: Array[Color] = []
		var tries := 0
		while list.size() < share and tries < share * 40:
			tries += 1
			var x := _rng.randf_range(-275.0, 275.0)
			var z := _rng.randf_range(-275.0, 275.0)
			var b := _biome(x, z)
			var density: float = float(b["forest"]) * 1.0 + float(b["grass"]) * 0.18
			if _rng.randf() > density * 0.85:
				continue
			if _slope(x, z) > 0.5:
				continue
			var y := _height(x, z)
			if y < 2.0 or y > 95.0:
				continue
			if terrain and terrain.has_method("river_distance") and terrain.river_distance(x, z) < 8.0:
				continue
			if _near_town(x, z):
				continue
			var s := float(k["scale"]) * _rng.randf_range(0.68, 1.25)
			var basis := Basis(Vector3.UP, _rng.randf_range(0.0, TAU)).scaled(Vector3(s, s * _rng.randf_range(0.9, 1.15), s))
			list.append(Transform3D(basis, Vector3(x, y - 0.3, z)))
			var tint: Color = k["tint"]
			tint = tint.lerp(Color(0.44, 0.42, 0.18), _rng.randf() * 0.35)
			cols.append(Color(tint.r * 1.15, tint.g * 1.1, tint.b * 1.1, 1.0))
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
			mm.set_instance_color(i, cols[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Trees_" + str(k["path"]).get_file().get_basename()
		mmi.multimesh = mm
		mmi.visibility_range_end = 330.0
		mmi.visibility_range_end_margin = 60.0
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mmi.extra_cull_margin = 6.0
		add_child(mmi)
		_tree_mms.append(mmi)


func _near_town(x: float, z: float) -> bool:
	var d := Vector2(x, z).distance_to(Vector2(-34, -14))
	return d < 60.0


func _build_bushes() -> void:
	var mesh := _load_mesh("res://assets/props/kenney/nature/plant_bushDetailed.glb")
	var bush2 := _load_mesh("res://assets/props/kenney/nature/plant_bushLarge.glb")
	var flat := _load_mesh("res://assets/props/kenney/nature/plant_flatTall.glb")
	var entries := []
	if mesh:
		entries.append({"mesh": mesh, "scale": 1.8, "end": 120.0, "tint": Color(0.34, 0.44, 0.24)})
	if bush2:
		entries.append({"mesh": bush2, "scale": 2.0, "end": 150.0, "tint": Color(0.32, 0.42, 0.22)})
	if flat:
		entries.append({"mesh": flat, "scale": 1.4, "end": 90.0, "tint": Color(0.40, 0.46, 0.24)})
	for e in entries:
		var m: Mesh = e["mesh"]
		_make_tree_material(m, Color(1, 1, 1))
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = m
		var per := int(float(bush_instances) / entries.size())
		var list: Array[Transform3D] = []
		var cols: Array[Color] = []
		var tries := 0
		while list.size() < per and tries < per * 30:
			tries += 1
			var x := _rng.randf_range(-270.0, 270.0)
			var z := _rng.randf_range(-270.0, 270.0)
			var b := _biome(x, z)
			var density: float = float(b["grass"]) * 0.6 + float(b["forest"]) * 0.9 + float(b["desert"]) * 0.35
			if _rng.randf() > density:
				continue
			var y := _height(x, z)
			if y < 1.7:
				continue
			var s := float(e["scale"]) * _rng.randf_range(0.6, 1.4)
			var basis := Basis(Vector3.UP, _rng.randf_range(0.0, TAU)).scaled(Vector3(s, s, s))
			list.append(Transform3D(basis, Vector3(x, y - 0.1, z)))
			var t: Color = e["tint"]
			cols.append(t.lerp(Color(0.46, 0.40, 0.20), _rng.randf() * 0.5))
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
			mm.set_instance_color(i, cols[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.visibility_range_end = float(e["end"])
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)


func _build_rocks() -> void:
	var rocks := ["rock_largeA", "rock_largeB", "rock_largeC", "rock_tallA", "rock_tallB", "stone_largeA", "stone_largeB", "rock_smallFlatA"]
	for name in rocks:
		var mesh := _load_mesh("res://assets/props/kenney/nature/%s.glb" % name)
		if mesh == null:
			continue
		_make_tree_material(mesh, Color(1, 1, 1))
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = mesh
		var per := int(float(rock_instances) / rocks.size())
		var list: Array[Transform3D] = []
		var cols: Array[Color] = []
		var tries := 0
		while list.size() < per and tries < per * 30:
			tries += 1
			var x := _rng.randf_range(-275.0, 275.0)
			var z := _rng.randf_range(-275.0, 275.0)
			var b := _biome(x, z)
			var slope := _slope(x, z)
			var density: float = 0.12 + float(b["rock"]) * 0.9 + slope * 1.4 + float(b["desert"]) * 0.25
			if _rng.randf() > density:
				continue
			var y := _height(x, z)
			var s := _rng.randf_range(0.8, 2.6)
			var basis := Basis(Vector3.UP, _rng.randf_range(0.0, TAU)).scaled(Vector3(s, s * _rng.randf_range(0.7, 1.1), s))
			list.append(Transform3D(basis, Vector3(x, y - s * 0.15, z)))
			var g := _rng.randf_range(0.55, 0.9)
			cols.append(Color(g * 1.02, g, g * 0.95))
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
			mm.set_instance_color(i, cols[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mmi.visibility_range_end = 260.0
		add_child(mmi)


func _build_cacti() -> void:
	var meshes := []
	for n in ["cactus_short", "cactus_tall"]:
		var m := _load_mesh("res://assets/props/kenney/nature/%s.glb" % n)
		if m:
			_make_tree_material(m, Color(1, 1, 1))
			meshes.append(m)
	for m in meshes:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = m
		var per := int(float(cactus_instances) / maxi(1, meshes.size()))
		var list: Array[Transform3D] = []
		var cols: Array[Color] = []
		var tries := 0
		while list.size() < per and tries < per * 40:
			tries += 1
			var x := _rng.randf_range(-100.0, 275.0)
			var z := _rng.randf_range(-80.0, 275.0)
			var b := _biome(x, z)
			if float(b["desert"]) < 0.35 or _rng.randf() > 0.6:
				continue
			var y := _height(x, z)
			var s := _rng.randf_range(1.0, 2.2)
			var basis := Basis(Vector3.UP, _rng.randf_range(0.0, TAU)).scaled(Vector3(s, s * _rng.randf_range(0.9, 1.4), s))
			list.append(Transform3D(basis, Vector3(x, y - 0.1, z)))
			cols.append(Color(0.42, 0.52, 0.30, 1))
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
			mm.set_instance_color(i, cols[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mmi.visibility_range_end = 220.0
		add_child(mmi)
