extends SceneTree
func _init():
	var s: PackedScene = load("res://assets/models/birds/bird_01.gltf")
	var n := s.instantiate()
	_dump(n, 0)
	var sk: Skeleton3D = n.find_child("Skeleton3D", true, false)
	print("bones ", sk.get_bone_count())
	for a in ["fly", "fly2", "eat", "idle", "walk"]:
		var an: Animation = load("res://assets/models/birds/anim_%s.tres" % a)
		print(a, " len ", an.length, " tracks ", an.get_track_count())
		for t in an.get_track_count():
			if an.track_get_type(t) == Animation.TYPE_POSITION_3D and an.track_get_key_count(t) > 1:
				var mn := Vector3(1e9, 1e9, 1e9); var mx := -mn
				for k in an.track_get_key_count(t):
					var p: Vector3 = an.track_get_key_value(t, k)
					mn = mn.min(p); mx = mx.max(p)
				print("   ", an.track_get_path(t), " keys ", an.track_get_key_count(t), " ", mn, " ", mx)
	quit()
func _dump(n: Node, d: int):
	print("  ".repeat(d), n.name, " : ", n.get_class(), " ", (n as Node3D).transform.origin if n is Node3D else "")
	if d < 2:
		for c in n.get_children(): _dump(c, d + 1)
