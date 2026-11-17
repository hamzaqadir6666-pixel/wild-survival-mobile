extends Node
## Save / load game slots as JSON, with a small screenshot-free header.

const SAVE_DIR := "user://saves"
const SLOT_FORMAT := "dust_and_iron_save"

signal saved(slot: int)
signal loaded(slot: int)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_DIR))


func slot_path(slot: int) -> String:
	return "%s/slot_%d.json" % [SAVE_DIR, slot]


func has_save(slot: int) -> bool:
	return FileAccess.file_exists(slot_path(slot))


func save_game(slot: int = 0) -> bool:
	var player := get_tree().get_first_node_in_group("player")
	if player:
		GameState.player_position = player.global_position
		GameState.player_rotation = player.get("yaw")
		if player.get("mounted"):
			var h = player.get("horse")
			if h and is_instance_valid(h):
				GameState.horse_position = h.global_position
				GameState.horse_rot = h.rotation.y
	# Juniper roams free most of the time: persist wherever she actually is so a
	# reload puts her back on the same patch of prairie.
	var horse_node := get_tree().get_first_node_in_group("horse")
	if horse_node and is_instance_valid(horse_node) and not (player != null and player.get("mounted")):
		GameState.horse_position = horse_node.global_position
		GameState.horse_rot = horse_node.rotation.y
	var world := get_tree().get_first_node_in_group("world")
	if world and world.has_method("get_clock"):
		GameState.world_time = world.get_clock().time_of_day
		GameState.day = world.get_clock().day
	var payload := {
		"format": SLOT_FORMAT,
		"timestamp": Time.get_unix_time_from_system(),
		"date_string": Time.get_datetime_string_from_system(),
		"player_name": GameState.PLAYER_NAME,
		"money": GameState.money,
		"state": GameState.serialize(),
	}
	var f := FileAccess.open(slot_path(slot), FileAccess.WRITE)
	if f == null:
		push_error("Cannot write save: %s" % slot_path(slot))
		return false
	f.store_string(JSON.stringify(payload, "\t"))
	f.close()
	GameState.is_new_game = false
	emit_signal("saved", slot)
	GameState.notify("Game saved.", 2.0)
	return true


func load_game(slot: int = 0) -> bool:
	if not has_save(slot):
		return false
	var f := FileAccess.open(slot_path(slot), FileAccess.READ)
	if f == null:
		return false
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Corrupt save file: %s" % slot_path(slot))
		return false
	if str(parsed.get("format", "")) != SLOT_FORMAT:
		push_error("Unknown save format")
		return false
	GameState.deserialize(parsed.get("state", {}))
	emit_signal("loaded", slot)
	return true


func delete_save(slot: int) -> void:
	if has_save(slot):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(slot_path(slot)))


func list_saves() -> Array:
	var out := []
	for i in range(6):
		if has_save(i):
			var f := FileAccess.open(slot_path(i), FileAccess.READ)
			var info := {"slot": i, "date": "", "money": 0, "player": GameState.PLAYER_NAME}
			if f:
				var parsed = JSON.parse_string(f.get_as_text())
				f.close()
				if typeof(parsed) == TYPE_DICTIONARY:
					info["date"] = str(parsed.get("date_string", ""))
					info["money"] = int(parsed.get("money", 0))
			out.append(info)
	return out


func newest_slot() -> int:
	var best := -1
	var best_time := -1.0
	for i in range(6):
		if not has_save(i):
			continue
		var f := FileAccess.open(slot_path(i), FileAccess.READ)
		if f == null:
			continue
		var parsed = JSON.parse_string(f.get_as_text())
		f.close()
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		var t := float(parsed.get("timestamp", 0.0))
		if t > best_time:
			best_time = t
			best = i
	return best
