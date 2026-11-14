class_name Water
extends Node3D
## Water surfaces ONLY where there is water: grid cells over the river and the lakes.

var material: ShaderMaterial
var triangles := 0

func build() -> void:
	material = ShaderMaterial.new()
	material.shader = load("res://shaders/water.gdshader")
	material.set_shader_parameter("ripple", load("res://assets/textures/water_ripple.png"))
	var NN := World.N
	var H := World.heights
	for cz in 4:
		for cx in 4:
			var verts := PackedVector3Array(); var cols := PackedColorArray(); var uvs := PackedVector2Array(); var nrm := PackedVector3Array()
			for j in range(cz * 64, cz * 64 + 64):
				for i in range(cx * 64, cx * 64 + 64):
					var k := j * NN + i
					var h00 := H[k]; var h10 := H[k + 1]; var h01 := H[k + NN]; var h11 := H[k + NN + 1]
					if minf(minf(h00, h10), minf(h01, h11)) > 0.05: continue
					var x := i * 4.0; var z := j * 4.0
					var p := [Vector3(x, 0, z), Vector3(x + 4, 0, z), Vector3(x, 0, z + 4), Vector3(x + 4, 0, z + 4)]
					var d := [h00, h10, h01, h11]
					for q in [0, 1, 2, 1, 3, 2]:
						verts.append(p[q]); nrm.append(Vector3.UP)
						cols.append(Color(1, 1, 1, clampf(-d[q] * 1.1, 0.0, 1.0)))
						uvs.append(Vector2(p[q].x, p[q].z) / 9.0)
			if verts.is_empty(): continue
			var arr := []; arr.resize(Mesh.ARRAY_MAX)
			arr[Mesh.ARRAY_VERTEX] = verts; arr[Mesh.ARRAY_NORMAL] = nrm; arr[Mesh.ARRAY_COLOR] = cols; arr[Mesh.ARRAY_TEX_UV] = uvs
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			var mi := MeshInstance3D.new()
			mi.mesh = mesh; mi.material_override = material
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			triangles += verts.size() / 3
