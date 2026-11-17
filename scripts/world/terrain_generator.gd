extends Node3D
## Procedural heightfield terrain with an authored layout:
## a mountain range to the north, forested hills west, desert east,
## a river carving through the valley and a lake in the south.

const CHUNK_SIZE := 96.0
const CHUNKS := 6             # 6x6 chunks => 576 x 576 m of playable land
const RES := 33               # verts per chunk edge (32 quads)
const HEIGHT_SCALE := 1.0

@export var seed_value: int = 20261117
@export var world_extent := 576.0
@export var water_level := 1.2
@export var generate_collision := true
@export var grass_amount := 16000
@export var tree_amount := 900

var heights: PackedFloat32Array = PackedFloat32Array()
var noise_hills: FastNoiseLite
var noise_detail: FastNoiseLite
var noise_ridge: FastNoiseLite
var noise_desert: FastNoiseLite
var noise_forest: FastNoiseLite
var _chunks: Array[Node3D] = []
var _spawn_points: Array[Dictionary] = []
var _roads: Array[PackedVector3Array] = []
var lake_center := Vector2(60, 150)
var river_points: PackedVector2Array = PackedVector2Array()


func _ready() -> void:
	randomize_seed(seed_value)
	_build_noise()
	_compute_river()
	generate()


func randomize_seed(s: int) -> void:
	seed_value = s


func _build_noise() -> void:
	noise_hills = FastNoiseLite.new()
	noise_hills.seed = seed_value
	noise_hills.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_hills.frequency = 0.0035
	noise_hills.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise_hills.fractal_octaves = 5
	noise_hills.fractal_gain = 0.5

	noise_detail = FastNoiseLite.new()
	noise_detail.seed = seed_value + 11
	noise_detail.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise_detail.frequency = 0.03
	noise_detail.fractal_octaves = 3

	noise_ridge = FastNoiseLite.new()
	noise_ridge.seed = seed_value + 27
	noise_ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise_ridge.frequency = 0.0055
	noise_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	noise_ridge.fractal_octaves = 4

	noise_desert = FastNoiseLite.new()
	noise_desert.seed = seed_value + 41
	noise_desert.frequency = 0.0022
	noise_desert.fractal_octaves = 2

	noise_forest = FastNoiseLite.new()
	noise_forest.seed = seed_value + 53
	noise_forest.frequency = 0.006
	noise_forest.fractal_octaves = 3


func _compute_river() -> void:
	# A gentle S-curve river running from the north-west mountains to the lake.
	river_points.clear()
	for i in 24:
		var t := float(i) / 23.0
		var z := -280.0 + t * 430.0
		var x := -120.0 + sin(t * 5.2) * 70.0 + t * 60.0
		river_points.append(Vector2(x, z))


func river_distance(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var best := 1e9
	for i in river_points.size() - 1:
		var a := river_points[i]
		var b := river_points[i + 1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var d := p.distance_to(a + ab * t)
		if d < best:
			best = d
	return best


## Biome weights used by vegetation + material blending.
func biome_at(x: float, z: float) -> Dictionary:
	var north := clampf((-z - 60.0) / 240.0, 0.0, 1.0)        # mountains
	var east := clampf((x - 60.0) / 220.0, 0.0, 1.0)           # desert
	var west := clampf((-x - 40.0) / 200.0, 0.0, 1.0)          # forest
	var forest_noise := noise_forest.get_noise_2d(x, z) * 0.5 + 0.5
	var grass := clampf(1.0 - north * 1.2 - east * 1.1, 0.0, 1.0)
	var forest := clampf(west * (0.5 + forest_noise * 0.9) - north * 0.4 + 0.15, 0.0, 1.0)
	return {
		"grass": grass,
		"forest": forest,
		"desert": east * (0.6 + 0.4 * clampf(noise_desert.get_noise_2d(x, z) + 0.5, 0.0, 1.0)),
		"rock": north,
	}


func height_at(x: float, z: float) -> float:
	var h := 0.0
	# rolling base hills
	h += noise_hills.get_noise_2d(x, z) * 14.0
	h += 6.0
	# mountain range to the north — ridged noise ramped up
	var north := clampf((-z - 40.0) / 260.0, 0.0, 1.0)
	var ridge := (noise_ridge.get_noise_2d(x, z) * 0.5 + 0.5)
	var mountain := pow(north, 1.6) * (ridge * 150.0 + 40.0)
	h += mountain
	# eastern mesas / badlands terraces
	var east := clampf((x - 40.0) / 240.0, 0.0, 1.0)
	var mesa := east * (noise_ridge.get_noise_2d(x + 400.0, z - 200.0) * 22.0)
	h += maxf(0.0, mesa)
	# fine detail
	h += noise_detail.get_noise_2d(x * 1.4, z * 1.4) * 1.6
	# west forested hills
	var west := clampf((-x - 20.0) / 220.0, 0.0, 1.0)
	h += west * (noise_hills.get_noise_2d(x * 2.1, z * 2.1) * 9.0 + 4.0)
	# river valley carving
	var rd := river_distance(x, z)
	var valley := 1.0 - smoothstep(6.0, 46.0, rd)
	h = lerp(h, h - 6.0, valley * 0.85)
	h -= (1.0 - smoothstep(0.0, 14.0, rd)) * 3.0
	# lake basin
	var dl := Vector2(x, z).distance_to(lake_center)
	h -= (1.0 - smoothstep(28.0, 82.0, dl)) * 5.5
	# flatten the town plateau
	var town := town_flatten(Vector2(x, z))
	h = lerp(h, 4.2, town)
	# keep the very edges from spiking (world border cliffs blend)
	var edge := maxf(absf(x), absf(z)) / (world_extent * 0.5)
	if edge > 0.86:
		h += (edge - 0.86) * 60.0
	return h


func town_flatten(p: Vector2) -> float:
	var c := Vector2(-34.0, -14.0)
	var d := p.distance_to(c)
	return 1.0 - smoothstep(48.0, 74.0, d)


func generate() -> void:
	_lake_shore()
	var total := CHUNKS * CHUNKS
	for cz in CHUNKS:
		for cx in CHUNKS:
			_create_chunk(cx, cz, (cz * CHUNKS + cx), total)


func _create_chunk(cx: int, cz: int, idx: int, total: int) -> void:
	var origin := Vector3((cx - CHUNKS * 0.5) * CHUNK_SIZE, 0.0, (cz - CHUNKS * 0.5) * CHUNK_SIZE)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var verts := []
	var normals := []
	var colors := []
	var uvs := []
	var step := CHUNK_SIZE / float(RES - 1)
	for z in RES:
		var row := []
		for x in RES:
			var wx := origin.x + x * step
			var wz := origin.z + z * step
			var h := height_at(wx, wz)
			row.append(Vector3(wx, h, wz))
		verts.append(row)
	# normals from the height field
	for z in RES:
		var nrow := []
		for x in RES:
			var hl := height_at(origin.x + (x - 1) * step, origin.z + z * step)
			var hr := height_at(origin.x + (x + 1) * step, origin.z + z * step)
			var hd := height_at(origin.x + x * step, origin.z + (z - 1) * step)
			var hu := height_at(origin.x + x * step, origin.z + (z + 1) * step)
			var n := Vector3(hl - hr, 2.0 * step, hd - hu).normalized()
			nrow.append(n)
		normals.append(nrow)
	for z in RES - 1:
		for x in RES - 1:
			var v00: Vector3 = verts[z][x]
			var v10: Vector3 = verts[z][x + 1]
			var v01: Vector3 = verts[z + 1][x]
			var v11: Vector3 = verts[z + 1][x + 1]
			var n00: Vector3 = normals[z][x]
			var n10: Vector3 = normals[z][x + 1]
			var n01: Vector3 = normals[z + 1][x]
			var n11: Vector3 = normals[z + 1][x + 1]
			var b00 := biome_at(v00.x, v00.z)
			var b10 := biome_at(v10.x, v10.z)
			var b01 := biome_at(v01.x, v01.z)
			var b11 := biome_at(v11.x, v11.z)
			var uv_scale := 0.06
			# triangle 1
			_emit(st, v00, n00, b00, uv_scale)
			_emit(st, v01, n01, b01, uv_scale)
			_emit(st, v10, n10, b10, uv_scale)
			# triangle 2
			_emit(st, v10, n10, b10, uv_scale)
			_emit(st, v01, n01, b01, uv_scale)
			_emit(st, v11, n11, b11, uv_scale)
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.name = "Ground_%d_%d" % [cx, cz]
	mi.mesh = mesh
	mi.material_override = _ground_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mi.visibility_range_end = 900.0
	mi.visibility_range_end_margin = 120.0
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(mi)
	_chunks.append(mi)
	if generate_collision:
		var body := StaticBody3D.new()
		body.name = "GroundBody_%d_%d" % [cx, cz]
		body.collision_layer = 1
		body.collision_mask = 0
		body.add_to_group("ground")
		var cs := CollisionShape3D.new()
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(mesh.get_faces())
		shape.backface_collision = true
		cs.shape = shape
		body.add_child(cs)
		add_child(body)


func _emit(st: SurfaceTool, v: Vector3, n: Vector3, b: Dictionary, uv_scale: float) -> void:
	st.set_normal(n)
	st.set_uv(Vector2(v.x, v.z) * uv_scale)
	# vertex colour encodes biome weights for the terrain shader:
	#   r = grass, g = forest floor, b = sand/desert, a = rock
	var grass: float = b["grass"]
	var forest: float = b["forest"]
	var desert: float = b["desert"]
	var rock: float = b["rock"]
	var slope := clampf((1.0 - n.y) * 3.4, 0.0, 1.0)
	rock = clampf(rock * 1.4 + slope, 0.0, 1.0)
	var c := Color(grass, forest, desert, rock)
	st.set_color(c)
	st.add_vertex(v)


var _ground_mat: ShaderMaterial

func _ground_material() -> ShaderMaterial:
	if _ground_mat:
		return _ground_mat
	var sh: Shader = load("res://shaders/ground.gdshader")
	_ground_mat = ShaderMaterial.new()
	_ground_mat.shader = sh
	_ground_mat.set_shader_parameter("tex_grass", load("res://assets/textures/terrain_grass.png"))
	_ground_mat.set_shader_parameter("tex_dirt", load("res://assets/textures/terrain_dirt.png"))
	_ground_mat.set_shader_parameter("tex_sand", load("res://assets/textures/terrain_sand.png"))
	_ground_mat.set_shader_parameter("tex_rock", load("res://assets/textures/terrain_rock.png"))
	_ground_mat.set_shader_parameter("tex_snow", load("res://assets/textures/terrain_snow.png"))
	_ground_mat.set_shader_parameter("nrm_grass", load("res://assets/textures/terrain_grass_n.png"))
	_ground_mat.set_shader_parameter("nrm_dirt", load("res://assets/textures/terrain_dirt_n.png"))
	_ground_mat.set_shader_parameter("nrm_sand", load("res://assets/textures/terrain_sand_n.png"))
	_ground_mat.set_shader_parameter("nrm_rock", load("res://assets/textures/terrain_rock_n.png"))
	_ground_mat.set_shader_parameter("uv_scale", 0.22)
	_ground_mat.set_shader_parameter("macro_scale", 0.004)
	return _ground_mat


func _lake_shore() -> void:
	# flatten around the lake centre so the water plane reads cleanly
	for c in _chunks:
		c.queue_free()
	_chunks.clear()


func get_heights_around(pos: Vector3, radius: float) -> float:
	return height_at(pos.x, pos.z)


func spawn_position() -> Vector3:
	var x := -34.0
	var z := -14.0
	return Vector3(x, height_at(x, z) + 0.2, z)


func road_path() -> PackedVector3Array:
	var pts := PackedVector3Array()
	for p in river_points:
		pts.append(Vector3(p.x + 34.0, 0.0, p.y))
	return pts
