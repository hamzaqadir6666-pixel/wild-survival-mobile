class_name Grass
extends MultiMeshInstance3D
## Short grass tufts only around the camera. One MultiMesh, re-laid when the camera
## has moved a few metres. Chunky low tufts in the ground's own green (no thin blades).

const STEP := 2.3
var _last := Vector3(1e9, 0, 1e9)
var _radius := 14.0

func setup(material: ShaderMaterial) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = Vegetation.mesh_from("res://assets/models/nature/grass_tuft.glb")
	mm.instance_count = 620
	mm.visible_instance_count = 0
	multimesh = mm
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	custom_aabb = AABB(Vector3(-40, -10, -40), Vector3(80, 30, 80))
	apply_quality()

func apply_quality() -> void:
	_radius = lerpf(10.0, 26.0, clampf(float(Cfg.v("grass")), 0.0, 1.0))
	_last = Vector3(1e9, 0, 1e9)

func update(cam: Vector3) -> void:
	if absf(cam.x - _last.x) + absf(cam.z - _last.z) < 3.0: return
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
				var keep := 0.9 if b == World.GRASS else (0.22 if b == World.FOREST else 0.0)
				var w := float((hsh >> 20) & 255) / 255.0
				if w > keep * (0.45 + 0.55 * amount): continue
				var sc := 1.1 + u * 0.9
				var basis := Basis(Vector3.UP, v * TAU).scaled(Vector3(sc * 2.2, sc * 0.9, sc * 2.2))
				mm.set_instance_transform(n, Transform3D(basis, Vector3(dx, World.height(x, z) - 0.03, dz)))
				n += 1
				if n >= maxn: break
			if n >= maxn: break
	mm.visible_instance_count = n
