extends Node
## Pooled particle / decal effects: bullet impacts, dust, blood, muzzle flashes.

const MAX_IMPACTS := 40

var _impact_pool: Array[Node3D] = []
var _impact_index := 0
var _decal_scene: PackedScene


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func spawn_impact(pos: Vector3, normal: Vector3, kind: String = "dirt") -> void:
	var root := get_tree().current_scene
	if root == null:
		return
	var p := GPUParticles3D.new()
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3.UP
	mat.spread = 55.0
	mat.initial_velocity_min = 2.0
	mat.initial_velocity_max = 7.0
	mat.gravity = Vector3(0, -12.0, 0)
	mat.scale_min = 0.35
	mat.scale_max = 1.2
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.05
	mat.color = _impact_color(kind)
	p.process_material = mat
	var qm := QuadMesh.new()
	qm.size = Vector2(0.09, 0.09)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _soft_dot_texture()
	qm.material = m
	p.draw_pass_1 = qm
	p.amount = 18
	p.lifetime = 0.9
	p.one_shot = true
	p.explosiveness = 0.95
	root.add_child(p)
	p.global_position = pos + normal * 0.05
	if normal.length() > 0.01:
		# never pass an "up" that is parallel to the look direction
		var up := Vector3.UP if absf(normal.normalized().y) < 0.95 else Vector3.FORWARD
		p.look_at(p.global_position + normal, up)
	p.emitting = true
	var t := get_tree().create_timer(1.6)
	t.timeout.connect(p.queue_free)
	if kind == "wood" or kind == "stone":
		_spawn_decal(pos, normal, kind)


func _impact_color(kind: String) -> Color:
	match kind:
		"blood":
			return Color(0.45, 0.05, 0.04)
		"wood":
			return Color(0.42, 0.3, 0.18)
		"stone":
			return Color(0.55, 0.53, 0.5)
		"water":
			return Color(0.8, 0.88, 0.95)
		"metal":
			return Color(0.75, 0.72, 0.6)
		_:
			return Color(0.38, 0.29, 0.19)


func _spawn_decal(pos: Vector3, normal: Vector3, kind: String) -> void:
	var root := get_tree().current_scene
	if root == null:
		return
	var d := Decal.new()
	d.size = Vector3(0.34, 0.34, 0.35)
	d.albedo_mix = 0.9
	d.modulate = Color(0.1, 0.09, 0.08, 1.0) if kind != "stone" else Color(0.3, 0.29, 0.27, 1.0)
	d.texture_albedo = _hole_texture()
	d.normal_fade = 0.4
	root.add_child(d)
	d.global_position = pos
	var up := Vector3.UP if abs(normal.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
	d.look_at(pos - normal, up)
	_impact_pool.append(d)
	if _impact_pool.size() > MAX_IMPACTS:
		var old: Node3D = _impact_pool.pop_front()
		if is_instance_valid(old):
			old.queue_free()


func spawn_muzzle_flash(pos: Vector3, dir: Vector3) -> void:
	var root := get_tree().current_scene
	if root == null:
		return
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.78, 0.45)
	light.light_energy = 6.0
	light.omni_range = 9.0
	light.shadow_enabled = false
	root.add_child(light)
	light.global_position = pos + dir * 0.1
	var tw := create_tween()
	tw.tween_property(light, "light_energy", 0.0, 0.09)
	tw.tween_callback(light.queue_free)


func spawn_tracer(from: Vector3, to: Vector3, color: Color = Color(1.0, 0.85, 0.55)) -> void:
	var root := get_tree().current_scene
	if root == null:
		return
	var im := ImmediateMesh.new()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = false
	m.vertex_color_use_as_albedo = true
	im.surface_begin(Mesh.PRIMITIVE_LINES, m)
	im.surface_set_color(color)
	im.surface_add_vertex(from)
	im.surface_set_color(Color(color.r, color.g, color.b, 0.0))
	im.surface_add_vertex(to)
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	root.add_child(mi)
	var tw := create_tween()
	tw.tween_interval(0.045)
	tw.tween_callback(mi.queue_free)


func spawn_dust(pos: Vector3, radius: float = 0.4, amount: int = 8) -> void:
	var root := get_tree().current_scene
	if root == null:
		return
	var p := GPUParticles3D.new()
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3.UP
	mat.spread = 80.0
	mat.initial_velocity_min = 0.4
	mat.initial_velocity_max = 1.6
	mat.gravity = Vector3(0, 0.35, 0)
	mat.scale_min = 0.6
	mat.scale_max = 1.8
	mat.color = Color(0.55, 0.48, 0.38, 0.45)
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = radius
	p.process_material = mat
	var qm := QuadMesh.new()
	qm.size = Vector2(0.5, 0.5)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _soft_dot_texture()
	qm.material = m
	p.draw_pass_1 = qm
	p.amount = amount
	p.lifetime = 1.4
	p.one_shot = true
	p.explosiveness = 0.7
	root.add_child(p)
	p.global_position = pos
	p.emitting = true
	var t := get_tree().create_timer(2.2)
	t.timeout.connect(p.queue_free)


func spawn_blood(pos: Vector3, dir: Vector3) -> void:
	var root := get_tree().current_scene
	if root == null:
		return
	var p := GPUParticles3D.new()
	var mat := ParticleProcessMaterial.new()
	mat.direction = -dir
	mat.spread = 35.0
	mat.initial_velocity_min = 1.5
	mat.initial_velocity_max = 4.5
	mat.gravity = Vector3(0, -14, 0)
	mat.scale_min = 0.4
	mat.scale_max = 1.0
	mat.color = Color(0.5, 0.06, 0.05, 0.9)
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.1
	p.process_material = mat
	var qm := QuadMesh.new()
	qm.size = Vector2(0.05, 0.05)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	qm.material = m
	p.draw_pass_1 = qm
	p.amount = 12
	p.lifetime = 0.7
	p.one_shot = true
	p.explosiveness = 1.0
	root.add_child(p)
	p.global_position = pos
	p.emitting = true
	var t := get_tree().create_timer(1.4)
	t.timeout.connect(p.queue_free)


var _dot_tex: Texture2D
var _hole_tex: Texture2D

func _soft_dot_texture() -> Texture2D:
	if _dot_tex:
		return _dot_tex
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	_dot_tex = t
	return _dot_tex


func _hole_texture() -> Texture2D:
	if _hole_tex:
		return _hole_tex
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.35, Color(1, 1, 1, 1))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	_hole_tex = t
	return _hole_tex
