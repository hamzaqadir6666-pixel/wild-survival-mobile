class_name Plants
extends Node3D
## The rare glowing plants: about 70 fixed places plus 5 close to the start point.

var items: Array = []          # {t, x, z, node, eaten, shown, extra}
var _mats := {}
var _glow_mats := {}
var _meshes := {}
var _quad: QuadMesh
var _cursor := 0
var rng := RandomNumberGenerator.new()

func setup() -> void:
	rng.randomize()
	_quad = QuadMesh.new(); _quad.size = Vector2(1.5, 1.5)
	for p in World.plants: _add(p.t, p.x, p.z, false)

func _mat(t: String) -> ShaderMaterial:
	if not _mats.has(t):
		var pd: Dictionary = D.PLANTS[t]
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/veg.gdshader")
		m.set_shader_parameter("detail", load("res://assets/textures/veg_detail.png"))
		m.set_shader_parameter("tint", Vector3(pd.tint.r, pd.tint.g, pd.tint.b))
		m.set_shader_parameter("glow", Vector3(pd.glow.r, pd.glow.g, pd.glow.b) * 0.5)
		_mats[t] = m
		var g := StandardMaterial3D.new()
		g.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		g.albedo_texture = load("res://assets/textures/glow.png")
		g.albedo_color = Color(pd.glow.r, pd.glow.g, pd.glow.b, 0.5)
		g.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		g.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		g.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		g.disable_fog = true
		_glow_mats[t] = g
		_meshes[t] = Vegetation.mesh_from("res://assets/models/nature/%s.glb" % pd.mesh)
	return _mats[t]

func _add(t: String, x: float, z: float, extra: bool) -> void:
	var pd: Dictionary = D.PLANTS[t]
	var mat := _mat(t)
	var n := MeshInstance3D.new()
	n.mesh = _meshes[t]
	n.material_override = mat
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sc: float = pd.scale
	n.scale = Vector3(sc, sc, sc)
	n.position = Vector3(x, maxf(World.height(x, z), 0.02), z)
	n.rotation.y = fposmod(x * 1.7 + z * 0.9, TAU)
	n.visible = false
	var g := MeshInstance3D.new()
	g.mesh = _quad
	g.material_override = _glow_mats[t]
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.position.y = 0.45 / sc
	g.scale = Vector3.ONE / sc
	n.add_child(g)
	add_child(n)
	items.append({"t": t, "x": x, "z": z, "node": n, "eaten": false, "shown": false, "extra": extra})

## new run: every plant grows back, 5 fresh ones appear around the start
func reset(start: Vector2) -> void:
	for i in range(items.size() - 1, -1, -1):
		var it: Dictionary = items[i]
		if it.extra:
			it.node.queue_free()
			items.remove_at(i)
		else:
			it.eaten = false; it.shown = false; it.node.visible = false
	var kinds := ["clover", "herb", "sunberry", "honey", "ironbark"]
	for k in 5:
		var p := World.dry_near(rng, start, 14.0, 42.0)
		_add(kinds[k], p.x, p.y, true)
	_cursor = 0

## shows plants near the camera and reveals them on the map; a slice per frame
func update(deer: Vector3) -> void:
	var n := items.size()
	for k in 16:
		_cursor = (_cursor + 1) % n
		var it: Dictionary = items[_cursor]
		if it.eaten: continue
		var dx: float = it.x - deer.x
		var dz: float = it.z - deer.z
		var d2 := dx * dx + dz * dz
		it.node.visible = d2 < 75.0 * 75.0
		if d2 < 22.0 * 22.0: it.shown = true

func nearest(deer: Vector3, reach: float) -> int:
	var best := -1
	var bd := reach * reach
	for i in items.size():
		var it: Dictionary = items[i]
		if it.eaten: continue
		var dx: float = it.x - deer.x
		var dz: float = it.z - deer.z
		var d2 := dx * dx + dz * dz
		if d2 < bd:
			bd = d2; best = i
	return best

func eat(i: int) -> String:
	var it: Dictionary = items[i]
	it.eaten = true
	it.node.visible = false
	return it.t
