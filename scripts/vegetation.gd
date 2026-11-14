class_name Vegetation
extends Node3D
## All trees, bushes, ferns, rocks and lilies as MultiMeshes in 64 m chunks.
## Chunks are switched on/off by distance a few times per second; far trees use a
## much lighter mesh (lod1). Positions come from assets/world/veg.bin (fixed map).

const KIND_TREE := 0
const KIND_BUSH := 1
const KIND_SMALL := 2
# type name -> [kind, horizontal scale multiplier, trunk radius per unit scale (0 = no collision)]
const TYPES := {
	"tree_a": [0, 1.0, 0.075], "tree_b": [0, 1.0, 0.075], "tree_c": [0, 1.0, 0.085], "tree_d": [0, 1.0, 0.075], "tree_big": [0, 1.0, 0.1],
	"tree_giant": [0, 1.0, 0.11], "palm_a": [0, 1.0, 0.045], "palm_b": [0, 1.0, 0.045],
	"banana": [1, 1.0, 0.0], "bush_a": [1, 1.0, 0.0], "bush_b": [1, 1.0, 0.0], "bush_berry": [1, 1.0, 0.0],
	"rock_a": [1, 1.0, 0.45], "rock_b": [1, 1.0, 0.42], "rock_c": [1, 1.0, 0.2],
	"fern_a": [2, 1.0, 0.0], "fern_b": [2, 1.0, 0.0], "tall_grass": [2, 2.4, 0.0], "lily": [2, 1.0, 0.0],
}
var material: ShaderMaterial
var meshes := {}
var lod_meshes := {}
var _data := PackedByteArray()
var _count := 0
var _pos := 0
# parallel arrays, one entry per MultiMeshInstance
var _nodes: Array[MultiMeshInstance3D] = []
var _far_nodes: Array = []          # lod1 partner or null
var _cx := PackedFloat32Array()
var _cz := PackedFloat32Array()
var _kind := PackedByteArray()
var _cursor := 0
var instance_total := 0

static func mesh_from(path: String) -> Mesh:
	var scene: PackedScene = load(path)
	var inst := scene.instantiate()
	var found: Mesh = null
	for c in inst.find_children("*", "MeshInstance3D", true, false):
		found = (c as MeshInstance3D).mesh
		break
	inst.free()
	return found

func setup() -> void:
	material = ShaderMaterial.new()
	material.shader = load("res://shaders/veg.gdshader")
	material.set_shader_parameter("detail", load("res://assets/textures/veg_detail.png"))
	for t in TYPES:
		meshes[t] = mesh_from("res://assets/models/nature/%s.glb" % t)
		var lp := "res://assets/models/nature/%s_lod1.glb" % t
		if ResourceLoader.exists(lp): lod_meshes[t] = mesh_from(lp)
	_data = FileAccess.get_file_as_bytes("res://assets/world/veg.bin")
	_count = _data.decode_u32(0)
	_pos = 0
	apply_quality()

func apply_quality() -> void:
	if material: material.set_shader_parameter("wind", 1.0 if Cfg.v("wind") else 0.0)
	var sh := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if Cfg.v("shadows") else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for i in _nodes.size():
		if _kind[i] == KIND_TREE: _nodes[i].cast_shadow = sh

func progress() -> float:
	return float(_pos) / maxf(1.0, _count)

## builds chunk groups for about `budget_ms`; returns false when everything is built
func build_some(budget_ms: int) -> bool:
	var t0 := Time.get_ticks_msec()
	while _pos < _count:
		_build_group()
		if Time.get_ticks_msec() - t0 >= budget_ms: break
	if _pos >= _count:
		_data = PackedByteArray()
		return false
	return true

func _build_group() -> void:
	var o := 4 + _pos * 8
	var type := _data.decode_u8(o)
	var x0 := _data.decode_u16(o + 4) / 60.0
	var z0 := _data.decode_u16(o + 6) / 60.0
	var ck := int(z0 / 64.0) * 16 + int(x0 / 64.0)
	var xf: Array[Transform3D] = []
	var tname: String = World.veg_types[type]
	var cfg: Array = TYPES[tname]
	while _pos < _count:
		o = 4 + _pos * 8
		if _data.decode_u8(o) != type: break
		var x := _data.decode_u16(o + 4) / 60.0
		var z := _data.decode_u16(o + 6) / 60.0
		if int(z / 64.0) * 16 + int(x / 64.0) != ck: break
		var sc := _data.decode_u8(o + 1) / 16.0
		var rot := _data.decode_u8(o + 2) / 256.0 * TAU
		var y := 0.02 if tname == "lily" else World.height(x, z) - 0.05
		var b := Basis(Vector3.UP, rot).scaled(Vector3(sc * cfg[1], sc, sc * cfg[1]))
		xf.append(Transform3D(b, Vector3(x, y, z)))
		if cfg[2] > 0.0: World.add_tree(x, z, cfg[2] * sc)
		_pos += 1
	var cx := (ck % 16) * 64.0 + 32.0
	var cz := (ck / 16) * 64.0 + 32.0
	var near := _make(meshes[tname], xf)
	near.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if (cfg[0] == KIND_TREE and Cfg.v("shadows")) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var far = null
	if lod_meshes.has(tname):
		far = _make(lod_meshes[tname], xf)
		far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_nodes.append(near); _far_nodes.append(far); _cx.append(cx); _cz.append(cz); _kind.append(cfg[0])
	instance_total += xf.size()

func _make(mesh: Mesh, xf: Array[Transform3D]) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xf.size()
	for i in xf.size(): mm.set_instance_transform(i, xf[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = material
	mmi.visible = false
	add_child(mmi)
	return mmi

## distance culling + LOD switch. Processes a slice of the chunks per call.
func update_visibility(cam: Vector3, all := false) -> void:
	var n := _nodes.size()
	if n == 0: return
	var steps := n if all else mini(n, 260)
	var tree_near: float = Cfg.v("tree_near") + 40.0
	var tree_far: float = float(Cfg.v("view")) - 10.0
	var bush: float = Cfg.v("bush") + 30.0
	var small: float = Cfg.v("small") + 30.0
	for _s in steps:
		var i := _cursor
		_cursor = (_cursor + 1) % n
		var dx := _cx[i] - cam.x
		var dz := _cz[i] - cam.z
		var d2 := dx * dx + dz * dz
		var k := _kind[i]
		if k == KIND_TREE:
			var is_near := d2 < tree_near * tree_near
			_nodes[i].visible = is_near
			var f = _far_nodes[i]
			if f != null: f.visible = (not is_near) and d2 < tree_far * tree_far
		elif k == KIND_BUSH:
			_nodes[i].visible = d2 < bush * bush
		else:
			_nodes[i].visible = d2 < small * small
