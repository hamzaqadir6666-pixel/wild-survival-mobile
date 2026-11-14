extends Node
## Progress that survives between sessions: abilities, unlocked levels, records, guide.

const PATH := "user://save.json"
var d := {}

func _ready() -> void:
	reset()
	if not Cfg.test_mode and FileAccess.file_exists(PATH):
		var j = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if typeof(j) == TYPE_DICTIONARY: _merge(d, j)

func reset() -> void:
	d = {"unlocked": 1, "unlocked_pred": 1, "side": "prey", "char": {"prey": "deer", "pred": "lion"}, "best_endless_pred": 0.0, "best_endless": 0.0, "abilities": {}, "tutorial_done": false,
		"stats": {"best_time": 0.0, "escapes": 0, "plants": 0, "games": 0, "deaths": 0, "levels_done": 0, "nights": 0, "kills": 0},
		"seen": {}, "plants_found": {}, "landmarks": {}, "ach": {}}

func _merge(a: Dictionary, b: Dictionary) -> void:
	for k in b:
		if a.has(k) and typeof(a[k]) == TYPE_DICTIONARY and typeof(b[k]) == TYPE_DICTIONARY: _merge(a[k], b[k])
		else: a[k] = b[k]

func store() -> void:
	if Cfg.test_mode: return
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(d))

func ability(key: String) -> int:
	return int(d.abilities.get(key, 0))

func add_ability(key: String) -> void:
	d.abilities[key] = ability(key) + 1

## returns true the first time
func unlock(ach: String) -> bool:
	if d.ach.has(ach): return false
	d.ach[ach] = true
	return true

func side() -> String:
	return "pred" if str(d.side) == "pred" else "prey"

## the animal chosen for the current side
func character() -> String:
	var c := str(d.char.get(side(), ""))
	if not D.CHARACTERS.has(c) or D.CHARACTERS[c].side != side(): c = D.CHAR_ORDER[side()][0]
	return c
