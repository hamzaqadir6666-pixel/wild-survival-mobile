extends Node
## Sound: music, layered ambience loops and a small pool of one-shot players.
## No 3D audio nodes are used; distance volume is computed by hand (cheap on phones).

const ONE_SHOTS := ["growl", "roar", "snarl", "howl", "laugh", "hiss", "grunt", "bleat", "moo", "rooster", "crow", "eat", "drink", "click", "thud",
	"thunder1", "thunder2", "step1", "step2", "step3", "step4", "splash1", "splash2", "splash3"]
const LOOPS := ["amb_day", "amb_night", "amb_water", "amb_rain", "amb_wind", "chase", "heartbeat"]
const LOOP_BUS := {"chase": "Music", "heartbeat": "SFX"}      # everything else: Ambience
var music_duck := 0.0      # 0..1, the calm music makes room for the chase music
var streams := {}
var pool: Array[AudioStreamPlayer] = []
var loops := {}
var loop_target := {}
const MUSIC := ["music1", "music2"]      # Enchanted Valley, Ascending the Vale (Kevin MacLeod)
var tracks: Array = []
var track := 0
var music: AudioStreamPlayer
var _next := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for b in ["Music", "SFX", "Ambience"]:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, b)
		AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	for n in ONE_SHOTS: streams[n] = load("res://assets/audio/%s.wav" % n)
	for i in 10:
		var p := AudioStreamPlayer.new(); p.bus = "SFX"; add_child(p); pool.append(p)
	for n in LOOPS:
		var s: AudioStreamWAV = load("res://assets/audio/%s.wav" % n)
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = int(s.get_length() * s.mix_rate)
		var p := AudioStreamPlayer.new(); p.stream = s; p.bus = LOOP_BUS.get(n, "Ambience"); p.volume_db = -60.0; add_child(p)
		loops[n] = p; loop_target[n] = 0.0
	music = AudioStreamPlayer.new(); music.bus = "Music"
	# two recorded pieces played one after the other, for ever
	for f in MUSIC: tracks.append(load("res://assets/audio/%s.mp3" % f))
	music.stream = tracks[0]; music.volume_db = -8.0
	music.finished.connect(_next_track)
	add_child(music)
	Cfg.changed.connect(apply_volumes)
	apply_volumes()

func apply_volumes() -> void:
	_bus("Master", Cfg.vol.master); _bus("Music", Cfg.vol.music); _bus("SFX", Cfg.vol.sfx); _bus("Ambience", Cfg.vol.ambience)

func _bus(bus: String, lin: float) -> void:
	var i := AudioServer.get_bus_index(bus)
	AudioServer.set_bus_mute(i, lin <= 0.001)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(lin, 0.001)))

func _next_track() -> void:
	track = (track + 1) % tracks.size()
	music.stream = tracks[track]
	music.play()

func start_music() -> void:
	if not music.playing: music.play()

## plays a one-shot. `dist` in metres from the listener (0 = full volume)
func play(sound: String, vol := 1.0, pitch := 1.0, dist := 0.0, max_dist := 70.0) -> void:
	if dist > max_dist or not streams.has(sound): return
	var k := vol * (1.0 - dist / max_dist)
	if k <= 0.02: return
	var p := pool[_next]; _next = (_next + 1) % pool.size()
	p.stream = streams[sound]; p.pitch_scale = pitch; p.volume_db = linear_to_db(clampf(k, 0.02, 1.5)); p.play()

func click() -> void:
	play("click", 0.8, 1.0)

func set_loop(n: String, level: float) -> void:
	loop_target[n] = clampf(level, 0.0, 1.0)

func silence_loops() -> void:
	for n in LOOPS: loop_target[n] = 0.0

## heart rate follows the danger: 1.0 = calm 75 bpm
func set_heart_rate(k: float) -> void:
	loops["heartbeat"].pitch_scale = clampf(k, 0.8, 2.2)

func _process(delta: float) -> void:
	music_duck = move_toward(music_duck, 1.0 if float(loop_target["chase"]) > 0.0 else 0.0, delta * 1.2)
	music.volume_db = lerpf(-8.0, -40.0, music_duck)
	for n in LOOPS:
		var p: AudioStreamPlayer = loops[n]
		var cur := db_to_linear(p.volume_db)
		var t: float = loop_target[n]
		cur = move_toward(cur, t, delta * (1.6 if LOOP_BUS.has(n) else 0.6))
		if cur <= 0.003:
			if p.playing: p.stop()
			p.volume_db = -60.0
		else:
			p.volume_db = linear_to_db(cur)
			if not p.playing: p.play()
