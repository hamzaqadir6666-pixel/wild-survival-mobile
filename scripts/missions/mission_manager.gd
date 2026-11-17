extends Node
## Data-driven mission system: main story, side jobs and random encounters.
## Each mission is a list of objectives with progress checks evaluated in _process.

signal objective_updated(mission_id: String, index: int, text: String)
signal mission_finished(mission_id: String, title: String, reward: int)

const MISSIONS := {
	"m1_cattle": {
		"title": "The Missing Herd",
		"giver": "Rancher Holt",
		"desc": "Three head of cattle wandered off toward the eastern badlands. Bring them home.",
		"objectives": [
			{"type": "talk", "target": "Rancher Holt", "text": "Speak with Rancher Holt at Barrett Ranch"},
			{"type": "reach", "pos": Vector3(150, 0, -60), "radius": 26.0, "text": "Search the badlands for the strays"},
			{"type": "kill", "target": "Wolf", "count": 2, "text": "Drive off the wolves circling the herd"},
			{"type": "talk", "target": "Rancher Holt", "text": "Report back to Rancher Holt"},
		],
		"reward": 60,
		"flag": "ranch_helped",
	},
	"m2_bandits": {
		"title": "Rattler Gulch",
		"giver": "Sheriff Ambrose",
		"desc": "The Rattler gang has been robbing stagecoaches. Sheriff Ambrose wants them cleared out.",
		"objectives": [
			{"type": "talk", "target": "Sheriff Ambrose", "text": "Get the warrant from Sheriff Ambrose"},
			{"type": "kill", "target": "Bandit", "count": 4, "text": "Clear Rattler Gulch (0/4 bandits)"},
			{"type": "talk", "target": "Sheriff Ambrose", "text": "Return to town and claim the bounty"},
		],
		"reward": 150,
		"flag": "bandits_cleared",
	},
	"m3_supplies": {
		"title": "Medicine Run",
		"giver": "Doc Whitlow",
		"desc": "Doc Whitlow needs a crate of medicine from the abandoned mine's supply cache.",
		"objectives": [
			{"type": "talk", "target": "Doc Whitlow", "text": "Ask Doc Whitlow what he needs"},
			{"type": "reach", "pos": Vector3(210, 0, -60), "radius": 18.0, "text": "Ride to Dustwater Mine"},
			{"type": "talk", "target": "Doc Whitlow", "text": "Deliver the medicine to Doc Whitlow"},
		],
		"reward": 90,
		"flag": "doc_helped",
	},
	"side_hunt": {
		"title": "Pelts for the Trapper",
		"giver": "Trapper Hollis",
		"desc": "Bring down three deer for the camp trapper.",
		"objectives": [
			{"type": "kill", "target": "Deer", "count": 3, "text": "Hunt deer (0/3)"},
		],
		"reward": 45,
		"flag": "first_hunt",
	},
}

var active: Dictionary = {}
var _dialogue_cooldowns: Dictionary = {}
var hud_ref: Node


func _ready() -> void:
	add_to_group("mission_manager")
	GameState.mission_started.connect(_on_mission_started)


func _process(_delta: float) -> void:
	for id in active.keys():
		_check_objectives(id)


func start_mission(id: String) -> void:
	if not MISSIONS.has(id):
		return
	if GameState.completed_missions.has(id):
		return
	if active.has(id):
		return
	var m: Dictionary = MISSIONS[id].duplicate(true)
	m["progress"] = 0
	m["counters"] = {}
	m["started_at"] = Time.get_ticks_msec()
	active[id] = m
	GameState.active_missions[id] = {"title": m["title"], "progress": 0}
	GameState.emit_signal("mission_started", id, m["title"])
	GameState.notify("New task: %s" % m["title"], 4.0)
	AudioManager.play_sfx("ui_click", 1.0, -6.0)
	_publish_objective(id)


func _on_mission_started(id: String, _title: String) -> void:
	if not active.has(id) and MISSIONS.has(id):
		start_mission(id)
	if hud_ref == null:
		hud_ref = get_tree().get_first_node_in_group("hud")


func _publish_objective(id: String) -> void:
	var m: Dictionary = active.get(id, {})
	if m.is_empty():
		return
	var idx: int = m["progress"]
	var objs: Array = m["objectives"]
	if idx >= objs.size():
		return
	var text := str(objs[idx].get("text", ""))
	GameState.set_objective("%s — %s" % [m["title"], text])
	objective_updated.emit(id, idx, text)


func _check_objectives(id: String) -> void:
	var m: Dictionary = active[id]
	var idx: int = m["progress"]
	var objs: Array = m["objectives"]
	if idx >= objs.size():
		_finish(id)
		return
	var obj: Dictionary = objs[idx]
	var done := false
	match str(obj["type"]):
		"reach":
			var player := get_tree().get_first_node_in_group("player")
			if player:
				var p: Vector3 = obj["pos"]
				var d := Vector2(player.global_position.x - p.x, player.global_position.z - p.z).length()
				if d <= float(obj.get("radius", 20.0)):
					done = true
		"kill":
			var target := str(obj["target"])
			var need := int(obj.get("count", 1))
			var have := 0
			if target == "Bandit":
				have = int(GameState.mission_flags.get("bandits_killed", 0))
				if m["counters"].has("bandit_base"):
					have -= int(m["counters"]["bandit_base"])
				else:
					m["counters"]["bandit_base"] = int(GameState.mission_flags.get("bandits_killed", 0))
					have = 0
			else:
				have = int(GameState.hunting_scores.get(target, 0))
				if not m["counters"].has(target + "_base"):
					m["counters"][target + "_base"] = have
				have -= int(m["counters"].get(target + "_base", 0))
			if have >= need:
				done = true
		"talk":
			# satisfied by the NPC interaction callback below
			pass
	if done:
		_advance(id)


func notify_talk(npc_name: String) -> void:
	for id in active.keys():
		var m: Dictionary = active[id]
		var idx: int = m["progress"]
		var objs: Array = m["objectives"]
		if idx >= objs.size():
			continue
		var obj: Dictionary = objs[idx]
		if str(obj["type"]) == "talk" and str(obj.get("target", "")) == npc_name:
			_advance(id)


func _advance(id: String) -> void:
	if not active.has(id):
		return
	var m: Dictionary = active[id]
	m["progress"] = int(m["progress"]) + 1
	GameState.active_missions[id]["progress"] = m["progress"]
	GameState.mission_flags["last_objective_time"] = Time.get_ticks_msec()
	AudioManager.play_sfx("ui_click", 1.35, -8.0)
	if int(m["progress"]) >= (m["objectives"] as Array).size():
		_finish(id)
	else:
		GameState.notify("Objective complete.", 2.5)
		_publish_objective(id)


func _finish(id: String) -> void:
	if not active.has(id):
		return
	var m: Dictionary = active[id]
	# clear the HUD objective *before* the payout so the toast order reads right
	GameState.set_objective("")
	var reward := int(m.get("reward", 0))
	GameState.add_money(reward)
	active.erase(id)
	GameState.active_missions.erase(id)
	if not GameState.completed_missions.has(id):
		GameState.completed_missions.append(id)
	GameState.mission_flags[str(m.get("flag", id))] = true
	GameState.notify("Task complete: %s  (+$%d)" % [m["title"], reward], 5.0)
	mission_finished.emit(id, str(m["title"]), reward)
	# a short celebratory jingle-ish cue
	AudioManager.play_sfx("ui_click", 0.8, -4.0)
	GameState.emit_signal("mission_completed", id)


func mission_list() -> Array:
	var out := []
	for id in MISSIONS.keys():
		var m: Dictionary = MISSIONS[id]
		var status := "available"
		if GameState.completed_missions.has(id):
			status = "complete"
		elif active.has(id):
			status = "active"
		out.append({"id": id, "title": m["title"], "giver": m["giver"], "desc": m["desc"], "status": status})
	return out
