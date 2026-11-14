class_name Terrain
extends Node3D
## Ground mesh in 8 x 8 chunks of 128 m. Heights and blend weights live in the vertices.

const CHUNK := 32          # cells per chunk side (32 * 4 m = 128 m)
var material: ShaderMaterial
var built := 0

func setup() -> void:
	material = ShaderMaterial.new()
	material.shader = load("res://shaders/terrain.gdshader")
	for t in ["grass", "forest", "dirt", "sand", "rock", "mud"]:
		material.set_shader_parameter("t_" + t, load("res://assets/textures/t_%s.png" % t))

func total() -> int:
	return 64

## builds one chunk; call until it returns false (spread over frames by the loader)
func build_next() -> bool:
	if built >= 64: return false
	_build(built % 8, built / 8)
	built += 1
	return built < 64

func _build(cx: int, cz: int) -> void:
	var n := CHUNK + 1
	var verts := PackedVector3Array(); verts.resize(n * n)
	var normals := PackedVector3Array(); normals.resize(n * n)
	var colors := PackedColorArray(); colors.resize(n * n)
	var uvs := PackedVector2Array(); uvs.resize(n * n)
	var uv2 := PackedVector2Array(); uv2.resize(n * n)
	var H := World.heights
	var S := World.splat
	var NN := World.N
	var k := 0
	for j in n:
		var gj := cz * CHUNK + j
		for i in n:
			var gi := cx * CHUNK + i
			var idx := gj * NN + gi
			var h := H[idx]
			verts[k] = Vector3(gi * 4.0, h, gj * 4.0)
			var hl := H[idx - 1] if gi > 0 else h
			var hr := H[idx + 1] if gi < NN - 1 else h
			var hu := H[idx - NN] if gj > 0 else h
			var hd := H[idx + NN] if gj < NN - 1 else h
			normals[k] = Vector3(hl - hr, 8.0, hu - hd).normalized()
			var s := idx * 5
			colors[k] = Color(S[s] / 255.0, S[s + 1] / 255.0, S[s + 2] / 255.0, S[s + 3] / 255.0)
			uv2[k] = Vector2(S[s + 4] / 255.0, 0.0)
			uvs[k] = Vector2(gi * 4.0, gj * 4.0) / 7.0
			k += 1
	var ind := PackedInt32Array(); ind.resize(CHUNK * CHUNK * 6)
	k = 0
	for j in CHUNK:
		for i in CHUNK:
			var a := j * n + i
			ind[k] = a; ind[k + 1] = a + 1; ind[k + 2] = a + n
			ind[k + 3] = a + 1; ind[k + 4] = a + n + 1; ind[k + 5] = a + n
			k += 6
	var arr := []; arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts; arr[Mesh.ARRAY_NORMAL] = normals; arr[Mesh.ARRAY_COLOR] = colors
	arr[Mesh.ARRAY_TEX_UV] = uvs; arr[Mesh.ARRAY_TEX_UV2] = uv2; arr[Mesh.ARRAY_INDEX] = ind
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh; mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
