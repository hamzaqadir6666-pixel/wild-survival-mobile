extends Node
## Settings. Only the preset NUMBER is saved; its values always come from PRESETS below,
## so changing a preset in a new build reaches players with old save files.
## Explicit user choices are kept in `over` and dropped when VERSION changes.

signal changed
const VERSION := 1
const PATH := "user://settings.json"
const PRESETS := [
	{"name": "Low", "shadows": false, "shadow_size": 0, "scale": 0.6, "grass": 0.25, "view": 170.0, "fps": 30, "wind": false, "rain": 110, "tree_near": 20.0, "tree_mid": 75.0, "bush": 50.0, "small": 30.0, "anim_near": 55.0},
	{"name": "Medium", "shadows": true, "shadow_size": 1024, "scale": 0.8, "grass": 0.6, "view": 230.0, "fps": 60, "wind": true, "rain": 220, "tree_near": 24.0, "tree_mid": 105.0, "bush": 70.0, "small": 42.0, "anim_near": 80.0},
	{"name": "High", "shadows": true, "shadow_size": 2048, "scale": 1.0, "grass": 1.0, "view": 270.0, "fps": 60, "wind": true, "rain": 340, "tree_near": 26.0, "tree_mid": 92.0, "bush": 70.0, "small": 42.0, "anim_near": 80.0},
]
const OVERRIDABLE := ["shadows", "scale", "grass", "view", "fps"]

var preset := 1
var auto_quality := true
var over := {}
var vol := {"master": 0.9, "music": 0.45, "sfx": 0.9, "ambience": 0.7}
var sensitivity := 1.0
var invert := false
var cam_dist := 6.5
var test_mode := false       # tests: never touch the settings file
var first_launch := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--test") or a.begins_with("--soak"): test_mode = true
	if test_mode:
		reset_for_tests()
	else:
		load_file()
	apply()

func reset_for_tests() -> void:
	preset = 0; auto_quality = false; over = {}; sensitivity = 1.0; invert = false; cam_dist = 6.5
	vol = {"master": 0.0, "music": 0.0, "sfx": 0.0, "ambience": 0.0}

func v(key: String):
	if over.has(key): return over[key]
	return PRESETS[preset][key]

func set_preset(p: int, keep_over := false) -> void:
	preset = clampi(p, 0, PRESETS.size() - 1)
	if not keep_over: over = {}
	save_file(); apply()

func set_over(key: String, value) -> void:
	if value == PRESETS[preset][key]: over.erase(key)
	else: over[key] = value
	save_file(); apply()

func detect_preset() -> int:
	var mem: int = int(OS.get_memory_info().get("physical", 0)) / (1024 * 1024)
	var cores := OS.get_processor_count()
	var gpu := RenderingServer.get_video_adapter_name().to_lower()
	var weak_gpu := false
	for k in ["mali-4", "mali-t", "mali-g31", "mali-g51", "mali-g52", "adreno (tm) 3", "adreno (tm) 4", "adreno (tm) 50", "adreno (tm) 51", "powervr", "llvmpipe", "swiftshader"]:
		if gpu.contains(k): weak_gpu = true
	if not (OS.has_feature("mobile")):
		return 2 if not weak_gpu else 1
	if weak_gpu or cores <= 4 or (mem > 0 and mem < 3600): return 0
	if cores >= 8 and mem >= 7000: return 2
	return 1

func load_file() -> void:
	if not FileAccess.file_exists(PATH):
		first_launch = true
		preset = detect_preset()
		save_file()
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(d) != TYPE_DICTIONARY:
		preset = detect_preset(); return
	preset = clampi(int(d.get("preset", 1)), 0, PRESETS.size() - 1)
	auto_quality = bool(d.get("auto", true))
	if int(d.get("version", 0)) == VERSION:
		var o = d.get("over", {})
		for k in OVERRIDABLE:
			if o.has(k): over[k] = o[k]
	var vv = d.get("vol", {})
	for k in vol.keys(): vol[k] = clampf(float(vv.get(k, vol[k])), 0.0, 1.0)
	sensitivity = clampf(float(d.get("sens", 1.0)), 0.3, 2.5)
	invert = bool(d.get("invert", false))
	cam_dist = clampf(float(d.get("cam", 6.5)), 4.0, 10.0)

func save_file() -> void:
	if test_mode: return
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"version": VERSION, "preset": preset, "auto": auto_quality, "over": over, "vol": vol, "sens": sensitivity, "invert": invert, "cam": cam_dist}))

func apply() -> void:
	Engine.max_fps = int(v("fps"))
	var vp := get_viewport()
	if vp:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = float(v("scale"))
		vp.msaa_3d = Viewport.MSAA_DISABLED
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		vp.use_taa = false
		vp.use_debanding = false
	changed.emit()

## Called by the game when the frame rate stayed under 25 fps for a while.
func lower_quality() -> bool:
	if not auto_quality: return false
	if over.size() > 0:
		over = {}; save_file(); apply(); return true
	if preset > 0:
		set_preset(preset - 1); return true
	return false
