extends Node
## Central audio: pooled one-shots, ambience cross-fades, music with ducking.

const POOL_SIZE := 24
const SFX := {
	"shot_revolver": "res://assets/audio/sfx/shot_revolver.wav",
	"shot_rifle": "res://assets/audio/sfx/shot_rifle.wav",
	"shot_shotgun": "res://assets/audio/sfx/shot_shotgun.wav",
	"dry_fire": "res://assets/audio/sfx/dry_fire.wav",
	"reload_revolver": "res://assets/audio/sfx/reload_revolver.wav",
	"reload_rifle": "res://assets/audio/sfx/reload_rifle.wav",
	"reload_shotgun": "res://assets/audio/sfx/reload_shotgun.wav",
	"thunder_far": "res://assets/audio/sfx/thunder_far.wav",
	"thunder_close": "res://assets/audio/sfx/thunder_close.wav",
	"horse_whinny": "res://assets/audio/sfx/horse_whinny.wav",
	"horse_snort": "res://assets/audio/sfx/horse_snort.wav",
	"horse_gallop": "res://assets/audio/sfx/horse_gallop.wav",
	"horse_hoof": "res://assets/audio/sfx/horse_hoof.wav",
	"step_grass": "res://assets/audio/sfx/step_grass.wav",
	"step_dirt": "res://assets/audio/sfx/step_dirt.wav",
	"step_wood": "res://assets/audio/sfx/step_wood.wav",
	"impact_bullet": "res://assets/audio/sfx/impact_bullet.wav",
	"ui_click": "res://assets/audio/sfx/ui_click.wav",
	"heartbeat": "res://assets/audio/sfx/heartbeat.wav",
	"wolf_howl": "res://assets/audio/sfx/wolf_howl.wav",
	"deer_call": "res://assets/audio/sfx/deer_call.wav",
	"whistle": "res://assets/audio/sfx/whistle.wav",
	"cloth": "res://assets/audio/ui/cloth_1.ogg",
	"door_open": "res://assets/audio/ui/door_open_1.ogg",
	"metal_click": "res://assets/audio/ui/metal_click.ogg",
	"impact_wood": "res://assets/audio/sfx/impact_wood_medium_000.ogg",
}
const AMBIENCE := {
	"wind": "res://assets/audio/sfx/amb_wind.wav",
	"rain": "res://assets/audio/sfx/amb_rain.wav",
	"birds": "res://assets/audio/sfx/amb_birds.wav",
	"river": "res://assets/audio/sfx/amb_river.wav",
	"forest": "res://assets/audio/sfx/amb_forest.wav",
	"saloon": "res://assets/audio/sfx/amb_saloon.wav",
	"campfire": "res://assets/audio/sfx/amb_campfire.wav",
}
const MUSIC := {
	"explore": "res://assets/audio/music/music_explore.wav",
	"town": "res://assets/audio/music/music_town.wav",
	"combat": "res://assets/audio/music/music_combat.wav",
	"night": "res://assets/audio/music/music_night.wav",
}

var _streams: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _pool_index := 0
var _amb: Dictionary = {}
var _music: AudioStreamPlayer
var _music_bus_name := "Music"
var _current_music := ""
var _pending_music := ""
var _music_fade := 0.0
var master_volume := 0.9
var music_volume := 0.55
var sfx_volume := 0.85
var ambience_volume := 0.6


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_buses()
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		p.max_polyphony = 4
		add_child(p)
		_pool.append(p)
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	_music.volume_db = -6.0
	add_child(_music)
	for key in AMBIENCE.keys():
		var a := AudioStreamPlayer.new()
		a.bus = "Ambience"
		a.stream = load(AMBIENCE[key])
		a.volume_db = -60.0
		add_child(a)
		_amb[key] = a
	_preload_streams()


func _ensure_buses() -> void:
	var layout_path := "res://resources/default_bus_layout.tres"
	if FileAccess.file_exists(layout_path):
		var layout: AudioBusLayout = load(layout_path)
		if layout:
			AudioServer.set_bus_layout(layout)
	for bus_name in ["Music", "SFX", "Ambience", "UI"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")
	apply_volumes()


func _preload_streams() -> void:
	for key in SFX.keys():
		var path: String = SFX[key]
		if ResourceLoader.exists(path):
			_streams[key] = load(path)
	for key in MUSIC.keys():
		var path: String = MUSIC[key]
		if ResourceLoader.exists(path):
			_streams["music_" + key] = load(path)


func apply_volumes() -> void:
	var mi := AudioServer.get_bus_index("Master")
	if mi >= 0:
		AudioServer.set_bus_volume_db(mi, linear_to_db(clampf(master_volume, 0.0001, 1.0)))
	var mu := AudioServer.get_bus_index("Music")
	if mu >= 0:
		AudioServer.set_bus_volume_db(mu, linear_to_db(clampf(music_volume, 0.0001, 1.0)))
	var sf := AudioServer.get_bus_index("SFX")
	if sf >= 0:
		AudioServer.set_bus_volume_db(sf, linear_to_db(clampf(sfx_volume, 0.0001, 1.0)))
	var am := AudioServer.get_bus_index("Ambience")
	if am >= 0:
		AudioServer.set_bus_volume_db(am, linear_to_db(clampf(ambience_volume, 0.0001, 1.0)))


func play_sfx(id: String, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	if not _streams.has(id):
		if not SFX.has(id):
			return
		var p: String = str(SFX[id])
		if not ResourceLoader.exists(p):
			return
		_streams[id] = load(p)
	var player := _pool[_pool_index]
	_pool_index = (_pool_index + 1) % _pool.size()
	player.stream = _streams[id]
	player.pitch_scale = clampf(pitch, 0.2, 4.0)
	player.volume_db = volume_db
	player.play()


func play_sfx_3d(id: String, pos: Vector3, parent: Node = null, volume_db: float = 0.0, pitch: float = 1.0, max_dist: float = 90.0) -> void:
	if not _streams.has(id):
		if not SFX.has(id):
			return
		var p: String = str(SFX[id])
		if not ResourceLoader.exists(p):
			return
		_streams[id] = load(p)
	var target_parent: Node = parent
	if target_parent == null:
		target_parent = get_tree().current_scene
	if target_parent == null:
		return
	var p3 := AudioStreamPlayer3D.new()
	p3.stream = _streams[id]
	p3.bus = "SFX"
	p3.max_distance = max_dist
	p3.unit_size = 8.0
	p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p3.pitch_scale = clampf(pitch, 0.2, 4.0)
	p3.volume_db = volume_db
	target_parent.add_child(p3)
	p3.global_position = pos
	p3.play()
	var t := get_tree().create_timer(maxf(0.5, _streams[id].get_length() / maxf(0.25, p3.pitch_scale) + 0.2))
	t.timeout.connect(p3.queue_free)


func set_ambience(id: String, target_db: float, fade: float = 2.0) -> void:
	for key in _amb.keys():
		var a: AudioStreamPlayer = _amb[key]
		var db := target_db if key == id else -60.0
		if db > -59.0 and not a.playing:
			a.play()
		var tw := create_tween()
		tw.tween_property(a, "volume_db", db, fade)
		if db <= -59.0:
			tw.tween_callback(a.stop)


func play_music(id: String, fade: float = 2.0) -> void:
	if id == _current_music:
		if not _music.playing:
			_music.play()
		return
	var key := "music_" + id
	if not _streams.has(key):
		return
	_current_music = id
	var tw := create_tween()
	tw.tween_property(_music, "volume_db", -40.0, fade * 0.5)
	tw.tween_callback(func() -> void:
		_music.stream = _streams[key]
		_music.play())
	tw.tween_property(_music, "volume_db", -6.0, fade * 0.5)


func stop_music(fade: float = 1.5) -> void:
	_current_music = ""
	var tw := create_tween()
	tw.tween_property(_music, "volume_db", -40.0, fade)
	tw.tween_callback(_music.stop)
