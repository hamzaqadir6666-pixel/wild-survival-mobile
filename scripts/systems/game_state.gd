extends Node
## Global player + world state. Persisted by SaveSystem.

signal money_changed(value: int)
signal health_changed(current: float, max_value: float)
signal stamina_changed(current: float, max_value: float)
signal horse_stamina_changed(current: float, max_value: float)
signal ammo_changed(weapon_id: String, clip: int, reserve: int)
signal weapon_changed(weapon_id: String)
signal inventory_changed()
signal objective_changed(text: String)
signal notification(text: String, seconds: float)
signal mission_started(mission_id: String, title: String)
signal mission_completed(mission_id: String)
signal wanted_level_changed(level: int)
signal player_died()
signal game_loaded()

const SAVE_VERSION := 3
const HEAT_DECAY_SECONDS := 25.0
const HORSE_NAME := "Juniper"
const PLAYER_NAME := "Silas Creed"

var max_health := 100.0
var health := 100.0
var max_stamina := 100.0
var stamina := 100.0
var max_horse_stamina := 100.0
var horse_stamina := 100.0
var money := 42

## weapon_id -> {clip, reserve, capacity, damage, spread, rate, auto, range, pellets}
var weapons := {}
var weapon_order: Array[String] = []
var current_weapon := ""
var equipped_weapons: Dictionary = {}

## mission state
var active_missions: Dictionary = {}
var completed_missions: Array[String] = []
var mission_flags: Dictionary = {}
var visited_locations: Array[String] = []
var collectibles: Array[String] = []
var wanted_level := 0
var hunting_scores: Dictionary = {}

## world clock (seconds since midnight) shared by the time system
var world_time := 8.5 * 3600.0
var day := 1
var weather_state := "clear"

var player_position := Vector3.ZERO
var player_rotation := 0.0
var horse_position := Vector3.ZERO
var horse_rot := 0.0
var horse_summoned := false
var camera_mode := 0
var difficulty := 1
var mouse_sensitivity := 1.0
var _heat_timer := 0.0
var is_new_game := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	reset_to_defaults()
	# phones should not burn battery at 120 fps, and the touch stick assumes this
	if OS.has_feature("mobile"):
		Engine.max_fps = 60
		DisplayServer.screen_set_keep_on(true)


func reset_to_defaults() -> void:
	health = max_health
	stamina = max_stamina
	horse_stamina = max_horse_stamina
	money = 42
	wanted_level = 0
	active_missions.clear()
	completed_missions.clear()
	mission_flags.clear()
	visited_locations.clear()
	collectibles.clear()
	hunting_scores.clear()
	world_time = 8.0 * 3600.0
	day = 1
	weather_state = "clear"
	player_position = Vector3.ZERO
	player_rotation = 0.0
	horse_position = Vector3.ZERO
	horse_rot = 0.0
	horse_summoned = false
	camera_mode = 0
	setup_weapons()
	is_new_game = true


func setup_weapons() -> void:
	weapons = {
		"revolver": {
			"name": "Cattleman Revolver",
			"clip": 6, "reserve": 48, "capacity": 6,
			"damage": 34.0, "spread": 0.012, "rate": 0.30, "auto": false,
			"range": 140.0, "pellets": 1, "recoil": 1.6, "reload": 0.75,
			"sound": "shot_revolver", "model": "revolver",
		},
		"rifle": {
			"name": "Rolling Block Rifle",
			"clip": 5, "reserve": 30, "capacity": 5,
			"damage": 78.0, "spread": 0.003, "rate": 0.85, "auto": false,
			"range": 320.0, "pellets": 1, "recoil": 4.2, "reload": 1.1,
			"sound": "shot_rifle", "model": "rifle",
		},
		"shotgun": {
			"name": "Double-Barrel Shotgun",
			"clip": 2, "reserve": 24, "capacity": 2,
			"damage": 26.0, "spread": 0.075, "rate": 0.65, "auto": false,
			"range": 55.0, "pellets": 9, "recoil": 6.0, "reload": 1.0,
			"sound": "shot_shotgun", "model": "shotgun",
		},
	}
	weapon_order = ["revolver", "rifle", "shotgun"]
	current_weapon = "revolver"
	emit_signal("weapon_changed", current_weapon)
	emit_signal("inventory_changed")


func has_weapon(id: String) -> bool:
	return weapons.has(id)


func select_weapon(id: String) -> void:
	if not weapons.has(id) or id == current_weapon:
		return
	current_weapon = id
	emit_signal("weapon_changed", id)
	var w: Dictionary = weapons[id]
	emit_signal("ammo_changed", id, w["clip"], w["reserve"])


func cycle_weapon(step: int = 1) -> void:
	if weapon_order.is_empty():
		return
	var idx := weapon_order.find(current_weapon)
	idx = (idx + step + weapon_order.size()) % weapon_order.size()
	select_weapon(weapon_order[idx])


func weapon_data() -> Dictionary:
	return weapons.get(current_weapon, {})


func consume_ammo() -> bool:
	var w: Dictionary = weapons.get(current_weapon, {})
	if w.is_empty():
		return false
	if int(w["clip"]) <= 0:
		return false
	w["clip"] = int(w["clip"]) - 1
	weapons[current_weapon] = w
	emit_signal("ammo_changed", current_weapon, w["clip"], w["reserve"])
	return true


func start_reload() -> bool:
	var w: Dictionary = weapons.get(current_weapon, {})
	if w.is_empty():
		return false
	var cap := int(w["capacity"])
	var clip := int(w["clip"])
	var reserve := int(w["reserve"])
	if clip >= cap or reserve <= 0:
		return false
	var need: int = cap - clip
	var take: int = mini(need, reserve)
	w["clip"] = clip + take
	w["reserve"] = reserve - take
	weapons[current_weapon] = w
	emit_signal("ammo_changed", current_weapon, int(w["clip"]), int(w["reserve"]))
	return true


func add_ammo(id: String, amount: int) -> void:
	if not weapons.has(id):
		return
	var w: Dictionary = weapons[id]
	w["reserve"] = int(w["reserve"]) + amount
	weapons[id] = w
	emit_signal("ammo_changed", id, int(w["clip"]), int(w["reserve"]))


func add_money(amount: int) -> void:
	money = max(0, money + amount)
	emit_signal("money_changed", money)


func spend_money(amount: int) -> bool:
	if money < amount:
		notify("Not enough money.")
		return false
	money -= amount
	emit_signal("money_changed", money)
	return true


func damage_player(amount: float) -> void:
	if health <= 0.0:
		return
	health = clampf(health - amount, 0.0, max_health)
	emit_signal("health_changed", health, max_health)
	if health <= 0.0:
		emit_signal("player_died")


func heal_player(amount: float) -> void:
	health = clampf(health + amount, 0.0, max_health)
	emit_signal("health_changed", health, max_health)


func use_stamina(amount: float) -> bool:
	if stamina <= 0.5:
		return false
	stamina = clampf(stamina - amount, 0.0, max_stamina)
	emit_signal("stamina_changed", stamina, max_stamina)
	return true


func recover_stamina(amount: float) -> void:
	stamina = clampf(stamina + amount, 0.0, max_stamina)
	emit_signal("stamina_changed", stamina, max_stamina)


func drain_horse_stamina(amount: float) -> void:
	horse_stamina = clampf(horse_stamina - amount, 0.0, max_horse_stamina)
	emit_signal("horse_stamina_changed", horse_stamina, max_horse_stamina)


func recover_horse_stamina(amount: float) -> void:
	horse_stamina = clampf(horse_stamina + amount, 0.0, max_horse_stamina)
	emit_signal("horse_stamina_changed", horse_stamina, max_horse_stamina)


func notify(text: String, seconds: float = 3.0) -> void:
	emit_signal("notification", text, seconds)
	print("[notice] ", text)


func set_objective(text: String) -> void:
	emit_signal("objective_changed", text)


func set_wanted(level: int) -> void:
	level = clampi(level, 0, 5)
	_heat_timer = 0.0
	if level != wanted_level:
		wanted_level = level
		emit_signal("wanted_level_changed", level)


## The law cools off if you keep your nose clean: one star every 25 s of quiet.
func _process(delta: float) -> void:
	if wanted_level <= 0:
		return
	_heat_timer += delta
	if _heat_timer >= HEAT_DECAY_SECONDS:
		_heat_timer = 0.0
		set_wanted(wanted_level - 1)


func add_wanted(amount: int) -> void:
	if amount <= 0:
		return
	set_wanted(wanted_level + amount)


func register_visit(id: String, label: String) -> void:
	if visited_locations.has(id):
		return
	visited_locations.append(id)
	notify("Discovered: %s" % label, 3.5)
	add_money(15)
	emit_signal("inventory_changed")


func add_collectible(id: String, label: String) -> void:
	if collectibles.has(id):
		return
	collectibles.append(id)
	notify("Found %s  (%d/%d)" % [label, collectibles.size(), 12], 3.0)
	emit_signal("inventory_changed")


func add_hunting_score(animal: String, value: int) -> void:
	hunting_scores[animal] = int(hunting_scores.get(animal, 0)) + value
	add_money(value)
	emit_signal("inventory_changed")


func serialize() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"health": health, "max_health": max_health,
		"stamina": stamina, "max_stamina": max_stamina,
		"horse_stamina": horse_stamina,
		"money": money,
		"weapons": weapons,
		"current_weapon": current_weapon,
		"active_missions": active_missions,
		"completed_missions": completed_missions,
		"mission_flags": mission_flags,
		"visited_locations": visited_locations,
		"collectibles": collectibles,
		"hunting_scores": hunting_scores,
		"wanted_level": wanted_level,
		"world_time": world_time,
		"day": day,
		"weather_state": weather_state,
		"player_position": var_to_str(player_position),
		"player_rotation": player_rotation,
		"horse_position": var_to_str(horse_position),
		"horse_rot": horse_rot,
		"horse_summoned": horse_summoned,
		"camera_mode": camera_mode,
		"difficulty": difficulty,
	}


func deserialize(d: Dictionary) -> void:
	health = float(d.get("health", max_health))
	max_health = float(d.get("max_health", 100.0))
	stamina = float(d.get("stamina", max_stamina))
	horse_stamina = float(d.get("horse_stamina", max_horse_stamina))
	money = int(d.get("money", 42))
	weapons = d.get("weapons", {})
	if weapons.is_empty():
		setup_weapons()
	current_weapon = str(d.get("current_weapon", "revolver"))
	active_missions = d.get("active_missions", {})
	completed_missions = []
	for m in d.get("completed_missions", []):
		completed_missions.append(str(m))
	mission_flags = d.get("mission_flags", {})
	visited_locations = []
	for v in d.get("visited_locations", []):
		visited_locations.append(str(v))
	collectibles = []
	for c in d.get("collectibles", []):
		collectibles.append(str(c))
	hunting_scores = d.get("hunting_scores", {})
	wanted_level = int(d.get("wanted_level", 0))
	world_time = float(d.get("world_time", 28800.0))
	day = int(d.get("day", 1))
	weather_state = str(d.get("weather_state", "clear"))
	player_position = str_to_var(str(d.get("player_position", "(0, 0, 0)")))
	if typeof(player_position) != TYPE_VECTOR3:
		player_position = Vector3.ZERO
	player_rotation = float(d.get("player_rotation", 0.0))
	horse_position = str_to_var(str(d.get("horse_position", "(0, 0, 0)")))
	if typeof(horse_position) != TYPE_VECTOR3:
		horse_position = Vector3.ZERO
	horse_rot = float(d.get("horse_rot", 0.0))
	horse_summoned = bool(d.get("horse_summoned", false))
	camera_mode = int(d.get("camera_mode", 0))
	difficulty = int(d.get("difficulty", 1))
	is_new_game = false
	emit_signal("health_changed", health, max_health)
	emit_signal("stamina_changed", stamina, max_stamina)
	emit_signal("horse_stamina_changed", horse_stamina, max_horse_stamina)
	emit_signal("money_changed", money)
	emit_signal("weapon_changed", current_weapon)
	emit_signal("inventory_changed")
	emit_signal("game_loaded")
