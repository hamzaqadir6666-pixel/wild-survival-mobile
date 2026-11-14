class_name Animal
extends Node3D
## Base for every ground animal: model, animation matched to movement speed, cheap
## ground following (height lookup, no physics) and level-of-detail tiers.

const TIER_NEAR := 0     # animated, updated every frame
const TIER_MID := 1      # visible, animation frozen, updated a few times per second
const TIER_FAR := 2      # hidden, position updated about once per second

static var _info := {}
static var _mats := {}
static var _looped := {}
static var _bird_lib: AnimationLibrary
static var _bird_mats := {}
static var _blob_mesh: QuadMesh
static var _blob_mat: StandardMaterial3D

var species := ""
var cfg := {}
var fauna: Node = null
var model: Node3D
var anim: AnimationPlayer
var mesh_inst: MeshInstance3D
var blob: MeshInstance3D
var yaw := 0.0
var speed := 0.0
var cur_anim := ""
var walk_nat := 1.0
var run_nat := 4.0
var body := 0.5
var tier := TIER_NEAR
var alive := true
var acc_dt := 0.0
var swim_depth := 0.6
var in_water := false
var home := Vector2.ZERO
var is_bird := false
var hidden := false      # inside a safe thicket (deer only)
var sneaking := false
var noise := 0.0         # how far the animal can be heard, metres

static func info() -> Dictionary:
	if _info.is_empty():
		_info = JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/animals/animals.json"))
	return _info

func setup(sp: String) -> void:
	species = sp
	cfg = D.SPECIES[sp]
	is_bird = cfg.get("bird", false)
	if is_bird:
		_setup_bird()
	else:
		var scene: PackedScene = load("res://assets/models/animals/%s.glb" % cfg.model)
		model = scene.instantiate()
		var sc: float = cfg.scale
		var shape: Vector3 = cfg.get("shape", Vector3(cfg.get("wide", 1.0), 1.0, 1.0))
		model.scale = Vector3(sc, sc, sc) * shape
		add_child(model)
		anim = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		var mis := model.find_children("*", "MeshInstance3D", true, false)
		if mis.size() > 0:
			mesh_inst = mis[0]
			mesh_inst.material_override = _material(sp)
			mesh_inst.extra_cull_margin = 1.0
		var inf: Dictionary = info()[cfg.model]
		walk_nat = float(inf.walk_ref) * sc
		run_nat = float(inf.run_ref) * sc
		body = float(inf.length) * sc * 0.28
		swim_depth = float(inf.height) * sc * shape.y * 0.55
		if anim and not _looped.has(cfg.model):
			_looped[cfg.model] = true
			for a in ["idle", "idle2", "walk", "run", "eat"]:
				if anim.has_animation(a): anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
		if anim: anim.playback_default_blend_time = 0.18
	apply_quality()
	play("idle")

func _material(sp: String) -> ShaderMaterial:
	if _mats.has(sp): return _mats[sp]
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/fur.gdshader")
	m.set_shader_parameter("fur", load("res://assets/textures/fur_%s.png" % cfg.fur))
	m.set_shader_parameter("pattern_color", cfg.pat)
	m.set_shader_parameter("pattern", cfg.pat_k)
	m.set_shader_parameter("uv_scale", cfg.uv)
	_mats[sp] = m
	return m

func _setup_bird() -> void:
	model = Animal.make_bird(species)
	add_child(model)
	anim = model.get_node("Anim") as AnimationPlayer
	for c in model.find_children("*", "MeshInstance3D", true, false):
		mesh_inst = c
	walk_nat = 0.35; run_nat = 4.5; body = 0.2; swim_depth = 0.1

const BIRD_LOOK := {
	"junglefowl": ["bird_01", 1.25, Color(1.0, 0.62, 0.42)],
	"crow": ["bird_02", 1.1, Color(0.10, 0.10, 0.12)],
	"hawk": ["bird_03", 2.1, Color(0.62, 0.45, 0.32)],
}

## Rigged bird (Blender Studio DOGWALK, CC-BY 4.0) with clips idle, walk, eat, fly.
static func make_bird(kind: String) -> Node3D:
	var look: Array = BIRD_LOOK[kind]
	var scene: PackedScene = load("res://assets/models/birds/%s.gltf" % look[0])
	var n: Node3D = scene.instantiate()
	n.scale = Vector3.ONE * float(look[1])
	if not _bird_mats.has(kind):
		var first: MeshInstance3D = n.find_children("*", "MeshInstance3D", true, false)[0]
		var src := first.mesh.surface_get_material(0) as BaseMaterial3D
		var m := StandardMaterial3D.new()
		m.albedo_texture = src.albedo_texture if src else null
		m.albedo_color = look[2]
		m.vertex_color_use_as_albedo = false
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.roughness = 1.0
		m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		if src and src.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			m.alpha_scissor_threshold = 0.5
		_bird_mats[kind] = m
	for c in n.find_children("*", "MeshInstance3D", true, false):
		(c as MeshInstance3D).material_override = _bird_mats[kind]
		(c as MeshInstance3D).extra_cull_margin = 1.0
	if _bird_lib == null:
		_bird_lib = AnimationLibrary.new()
		for a in ["idle", "walk", "eat"]:
			var an: Animation = load("res://assets/models/birds/anim_%s.tres" % a)
			an.loop_mode = Animation.LOOP_LINEAR
			_bird_lib.add_animation(a, an)
		# flight clip: drop the take-off root motion (the game moves the bird) and keep the steady flapping part
		var fly: Animation = (load("res://assets/models/birds/anim_fly.tres") as Animation).duplicate()
		for t in range(fly.get_track_count() - 1, -1, -1):
			var path := String(fly.track_get_path(t))
			if path.ends_with(":subroot") or path.ends_with(":root") or not path.contains("Skeleton3D:"): fly.remove_track(t)
		fly.loop_mode = Animation.LOOP_NONE
		_bird_lib.add_animation("run", fly)
	var ap := AnimationPlayer.new()
	ap.name = "Anim"
	n.add_child(ap)
	ap.root_node = NodePath("..")
	ap.add_animation_library("", _bird_lib)
	ap.playback_default_blend_time = 0.15
	return n

## keeps a bird in the steady part of its flight clip
static func bird_fly(ap: AnimationPlayer, rate := 1.0) -> void:
	if ap.current_animation != "run":
		ap.play("run")
		ap.seek(1.3, true)
	elif ap.current_animation_position > 2.6 or not ap.is_playing():
		ap.play("run")
		ap.seek(1.3, true)
	ap.speed_scale = rate

func apply_quality() -> void:
	var want_blob := not bool(Cfg.v("shadows"))
	if mesh_inst:
		mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if want_blob else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if want_blob and blob == null:
		if _blob_mesh == null:
			_blob_mesh = QuadMesh.new(); _blob_mesh.size = Vector2(1, 1); _blob_mesh.orientation = PlaneMesh.FACE_Y
			_blob_mat = StandardMaterial3D.new()
			_blob_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			_blob_mat.albedo_texture = load("res://assets/textures/blob.png")
			_blob_mat.albedo_color = Color(0, 0, 0, 0.5)
			_blob_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		blob = MeshInstance3D.new()
		blob.mesh = _blob_mesh; blob.material_override = _blob_mat
		blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		blob.scale = Vector3(body * 3.2, 1, body * 4.6)
		blob.position.y = 0.06
		add_child(blob)
	elif not want_blob and blob != null:
		blob.queue_free(); blob = null

func play(a: String, rate := 1.0) -> void:
	if anim == null: return
	if cur_anim != a:
		if not anim.has_animation(a):
			if a == "death": anim.pause()
			return
		cur_anim = a
		anim.play(a)
	anim.speed_scale = rate

## picks idle / walk / run and plays it at the rate that matches the ground speed
func locomotion(spd: float) -> void:
	if anim == null: return
	if spd < 0.15: play("idle")
	elif is_bird and spd >= run_nat * 0.55:
		cur_anim = "run"
		Animal.bird_fly(anim)
	elif spd < run_nat * 0.55: play("walk", clampf(spd / walk_nat, 0.5, 3.0))
	else: play("run", clampf(spd / run_nat, 0.5, 3.0))

func set_tier(t: int) -> void:
	if t == tier: return
	tier = t
	if model: model.visible = t != TIER_FAR
	if blob: blob.visible = t == TIER_NEAR
	if anim: anim.active = t == TIER_NEAR

func pos2() -> Vector2:
	return Vector2(position.x, position.z)

func dist_to(p: Vector3) -> float:
	var dx := p.x - position.x
	var dz := p.z - position.z
	return sqrt(dx * dx + dz * dz)

func face(dir: Vector2, delta: float, rate := 8.0) -> void:
	if dir.length_squared() < 0.0001: return
	yaw = lerp_angle(yaw, atan2(dir.x, dir.y), minf(1.0, rate * delta))
	rotation.y = yaw

func forward() -> Vector2:
	return Vector2(sin(yaw), cos(yaw))

func place(x: float, z: float) -> void:
	var h := World.height(x, z)
	in_water = h < -swim_depth
	position = Vector3(x, -swim_depth if in_water else h, z)
	if blob: blob.visible = tier == TIER_NEAR and not in_water

## straight-line step toward a point; returns remaining distance
func step_to(target: Vector2, spd: float, delta: float, turn := 7.0) -> float:
	var to := target - pos2()
	var d := to.length()
	if d < 0.05:
		speed = 0.0
		return d
	var dir := to / d
	var stepd := minf(d, spd * delta)
	face(dir, delta, turn)
	var nx := position.x + dir.x * stepd
	var nz := position.z + dir.y * stepd
	if can_enter(nx, nz):
		place(nx, nz)
		speed = spd
	else:
		speed = 0.0
	return d - stepd

func can_enter(x: float, z: float) -> bool:
	return World.playable(x, z)
