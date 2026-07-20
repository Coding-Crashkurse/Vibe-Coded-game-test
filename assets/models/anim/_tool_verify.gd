extends SceneTree
## THROWAWAY experiment tool (retarget spike): reports bone names, rest pose and
## clip inventory of the retargeted scenes so the rest-pose match can be judged
## numerically before anything visual is built.

func _skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var s := _skel(c)
		if s != null:
			return s
	return null


func _anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var a := _anim(c)
		if a != null:
			return a
	return null


func _dump(path: String, label: String) -> void:
	print("\n===== %s (%s)" % [label, path])
	var ps: PackedScene = load(path)
	if ps == null:
		print("  LOAD FAILED")
		return
	var root := ps.instantiate()
	var sk := _skel(root)
	if sk == null:
		print("  NO SKELETON")
		return
	print("  bones=%d" % sk.get_bone_count())
	var names := []
	for i in sk.get_bone_count():
		names.append(sk.get_bone_name(i))
	print("  names: %s" % ", ".join(names))
	print("  has RightHand=%s  has Wrist.R=%s" % [sk.find_bone("RightHand"), sk.find_bone("Wrist.R")])
	# rest pose: global direction shoulder->elbow->hand, tells T-pose vs arms-down
	for chain in [["RightUpperArm", "RightLowerArm"], ["RightLowerArm", "RightHand"],
			["LeftUpperArm", "LeftLowerArm"], ["LeftUpperLeg", "LeftLowerLeg"]]:
		var a := sk.find_bone(chain[0])
		var b := sk.find_bone(chain[1])
		if a < 0 or b < 0:
			print("  chain %s: MISSING" % str(chain))
			continue
		var ga := sk.get_bone_global_rest(a).origin
		var gb := sk.get_bone_global_rest(b).origin
		var d := (gb - ga).normalized()
		print("  rest dir %-28s = (%.3f, %.3f, %.3f)   len=%.3f"
			% [chain[0] + "->" + chain[1], d.x, d.y, d.z, (gb - ga).length()])
	var ap := _anim(root)
	if ap != null:
		var lst := ap.get_animation_list()
		print("  clips=%d" % lst.size())
		var want := ["Crouch_Idle_Loop", "Pistol_Reload", "Crouch_Fwd_Loop"]
		for w in want:
			for c in lst:
				if String(c).contains(w):
					print("    FOUND %s" % c)
	root.free()


func _init() -> void:
	_dump("res://assets/models/anim/rt_swat.glb", "rig A retargeted (sandbox copy)")
	_dump("res://assets/models/anim/ual.gltf", "animation library retargeted")
	_dump("res://assets/models/characters/Swat.glb", "rig A UNTOUCHED (reference)")
	quit()
