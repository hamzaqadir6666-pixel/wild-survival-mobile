class_name Grass
extends MultiMeshInstance3D
## Short grass tufts only around the camera. One MultiMesh, re-laid when the camera
## has moved a few metres. Chunky low tufts in the ground's own green (no thin blades).

const STEP := 1.0
var _last := Vector3(1e9, 0, 1e9)
var _radius := 14.0

func setup(material: ShaderMaterial) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _tuft()
	mm.instance_count = 2600
	mm.visible_instance_count = 0
	multimesh = mm
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	custom_aabb = AABB(Vector3(-40, -10, -40), Vector3(80, 30, 80))
	apply_quality()

## A clump of nine broad blades, one triangle each: light enough to cover the ground thickly.
## Vertex colour = grass green (darker at the root), alpha 1 at the tip so only the tips sway.
func _tuft() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var P := PackedVector3Array(); var N := PackedVector3Array(); var C := PackedColorArray(); var UV := PackedVector2Array()
	for i in 9:
		var ang := i * TAU / 9.0 + rng.randf_range(-0.25, 0.25)
		var out := Vector3(cos(ang), 0, sin(ang))
		var side := Vector3(-out.z, 0, out.x)
		var root := out * rng.randf_range(0.02, 0.15)
		var h := rng.randf_range(0.26, 0.44)
		var tip := root + out * rng.randf_range(0.08, 0.2) + Vector3(0, h, 0)
		var g := rng.randf_range(0.85, 1.15)
		var col := Color(0.056 * g, 0.156 * g, 0.020 * g)
		var n := (Vector3.UP + out * 0.35).normalized()
		for v in [root - side * 0.05, root + side * 0.05, tip]:
			P.append(v); N.append(n); UV.append(Vector2(v.x + v.z, v.y) * 2.0)
		C.append(Color(col.r * 0.7, col.g * 0.7, col.b * 0.7, 0.0)); C.append(Color(col.r * 0.7, col.g * 0.7, col.b * 0.7, 0.0)); C.append(Color(col.r * 1.25, col.g * 1.25, col.b * 1.1, 1.0))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = P; arr[Mesh.ARRAY_NORMAL] = N; arr[Mesh.ARRAY_COLOR] = C; arr[Mesh.ARRAY_TEX_UV] = UV
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m

func apply_quality() -> void:
	_radius = lerpf(11.0, 29.0, clampf(float(Cfg.v("grass")), 0.0, 1.0))
	_last = Vector3(1e9, 0, 1e9)

func update(cam: Vector3) -> void:
	if absf(cam.x - _last.x) + absf(cam.z - _last.z) < 3.5: return
	_last = cam
	global_position = Vector3(cam.x, 0, cam.z)
	var amount := float(Cfg.v("grass"))
	var mm := multimesh
	var n := 0
	var maxn := mm.instance_count
	if amount > 0.01:
		var i0 := int((cam.x - _radius) / STEP)
		var i1 := int((cam.x + _radius) / STEP)
		var j0 := int((cam.z - _radius) / STEP)
		var j1 := int((cam.z + _radius) / STEP)
		var r2 := _radius * _radius
		for j in range(j0, j1 + 1):
			for i in range(i0, i1 + 1):
				var hsh := (i * 73856093) ^ (j * 19349663)
				var u := float(hsh & 1023) / 1023.0
				var v := float((hsh >> 10) & 1023) / 1023.0
				var x := (i + u) * STEP
				var z := (j + v) * STEP
				var dx := x - cam.x
				var dz := z - cam.z
				if dx * dx + dz * dz > r2: continue
				var b := World.biome(x, z)
				var keep := 0.97 if b == World.GRASS else (0.6 if b == World.FOREST else 0.0)
				var w := float((hsh >> 20) & 255) / 255.0
				if w > keep * (0.5 + 0.5 * amount): continue
				var sc := 0.8 + u * 0.8
				var basis := Basis(Vector3.UP, v * TAU).scaled(Vector3(sc * 2.0, sc * (0.8 + w * 0.7), sc * 2.0))
				mm.set_instance_transform(n, Transform3D(basis, Vector3(dx, World.height(x, z) - 0.03, dz)))
				n += 1
				if n >= maxn: break
			if n >= maxn: break
	mm.visible_instance_count = n
