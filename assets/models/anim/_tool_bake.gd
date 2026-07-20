extends SceneTree
## THROWAWAY experiment tool (retarget spike), STEP 2.
##
## Hypothesis under test: the shipped characters can stay COMPLETELY UNTOUCHED
## (bone names incl. "Wrist.R" preserved) if the library clips are baked offline
## into rig A's own rest pose and bone names.
##
## The blocker found in step 1 is that the two rests are different POSE SHAPES
## (rig A arms-down, library T-pose), so "rotation relative to rest" is not a
## shared reference. This tool tries to MANUFACTURE the shared reference: the
## library's rest IS a canonical T-pose, so for every mapped bone the shortest-arc
## rotation that turns rig A's rest child-direction onto the library's rest
## child-direction reconstructs rig A's T-pose. With that, the transfer is
##     G_target = G_source * R_source_rest^-1 * Q * R_target_rest
## and the track value is the local rotation under rig A's own hierarchy.
##
## Validation clip is the library's A_TPose: if rig A does NOT end up in a clean
## T-pose, the reconstruction is wrong and the experiment is over.

const OUT := "C:/Users/User/AppData/Local/Temp/claude/c--Users-User-Desktop-ja2-remasted/975d617d-579f-4755-b62a-f4617a4062b5/scratchpad/retarget_shots"

# profile bone name (as the retargeted library now calls them) -> rig A bone name
const MAP := {
	"Hips": "Hips", "Spine": "Abdomen", "Chest": "Torso", "UpperChest": "Chest",
	"Neck": "Neck", "Head": "Head",
	"LeftShoulder": "Shoulder.L", "LeftUpperArm": "UpperArm.L",
	"LeftLowerArm": "LowerArm.L", "LeftHand": "Wrist.L",
	"RightShoulder": "Shoulder.R", "RightUpperArm": "UpperArm.R",
	"RightLowerArm": "LowerArm.R", "RightHand": "Wrist.R",
	"LeftUpperLeg": "UpperLeg.L", "LeftLowerLeg": "LowerLeg.L",
	"LeftFoot": "Foot.L", "LeftToes": "PT.L",
	"RightUpperLeg": "UpperLeg.R", "RightLowerLeg": "LowerLeg.R",
	"RightFoot": "Foot.R", "RightToes": "PT.R",
}
# primary child used to derive the bone's direction vector
const CHILD := {
	"Hips": "Spine", "Spine": "Chest", "Chest": "UpperChest", "UpperChest": "Neck",
	"Neck": "Head",
	"LeftShoulder": "LeftUpperArm", "LeftUpperArm": "LeftLowerArm", "LeftLowerArm": "LeftHand",
	"RightShoulder": "RightUpperArm", "RightUpperArm": "RightLowerArm", "RightLowerArm": "RightHand",
	"LeftUpperLeg": "LeftLowerLeg", "LeftLowerLeg": "LeftFoot", "LeftFoot": "LeftToes",
	"RightUpperLeg": "RightLowerLeg", "RightLowerLeg": "RightFoot", "RightFoot": "RightToes",
}


func _find(n: Node, t: String) -> Node:
	if n.get_class() == t:
		return n
	for c in n.get_children():
		var r := _find(c, t)
		if r != null:
			return r
	return null


## Direction in WORLD space. The two rigs sit in differently oriented armature
## nodes (Blender Z-up vs Y-up), so comparing raw skeleton-space rests mixes a
## global ~90 deg frame error into every bone.
func _gdir(sk: Skeleton3D, a: String, b: String) -> Vector3:
	var ia := sk.find_bone(a)
	var ib := sk.find_bone(b)
	if ia < 0 or ib < 0:
		return Vector3.ZERO
	var d := sk.get_bone_global_rest(ib).origin - sk.get_bone_global_rest(ia).origin
	d = sk.global_transform.basis * d
	if d.length() < 0.0001:
		return Vector3.ZERO
	return d.normalized()


## World-space rotation of the skeleton node (scale stripped).
func _wrot(sk: Skeleton3D) -> Quaternion:
	return sk.global_transform.basis.orthonormalized().get_rotation_quaternion()


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var root := Node3D.new()
	get_root().add_child(root)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -35, 0)
	sun.light_energy = 1.4
	root.add_child(sun)
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.18, 0.16, 0.14)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.65, 0.65, 0.7)
	e.ambient_light_energy = 0.9
	we.environment = e
	root.add_child(we)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.0, 2.6)
	root.add_child(cam)

	# UNTOUCHED shipped character
	var chr: Node = (load("res://assets/models/characters/Swat.glb") as PackedScene).instantiate()
	root.add_child(chr)
	var tsk := _find(chr, "Skeleton3D") as Skeleton3D
	var ap := _find(chr, "AnimationPlayer") as AnimationPlayer
	print("target bones=%d  Wrist.R=%d (must stay >=0)" % [tsk.get_bone_count(), tsk.find_bone("Wrist.R")])

	# retargeted library (profile bone names, T-pose rest)
	var lib: Node = (load("res://assets/models/anim/ual.gltf") as PackedScene).instantiate()
	root.add_child(lib)          # must be in-tree BEFORE any global_transform read
	var ssk := _find(lib, "Skeleton3D") as Skeleton3D
	var lap := _find(lib, "AnimationPlayer") as AnimationPlayer
	await process_frame
	var swr := _wrot(ssk)
	var twr := _wrot(tsk)
	print("source skel world rot=%s  target=%s" % [str(swr), str(twr)])

	# ---- reconstruct rig A's T-pose: Q aligns rigA rest dir -> library rest dir
	var Q := {}
	for prof in MAP.keys():
		var rigb: String = MAP[prof]
		if not CHILD.has(prof):
			Q[prof] = Quaternion.IDENTITY
			continue
		var cprof: String = CHILD[prof]
		var crig: String = MAP[cprof]
		var ds := _gdir(ssk, prof, cprof)
		var dt := _gdir(tsk, rigb, crig)
		if ds == Vector3.ZERO or dt == Vector3.ZERO:
			Q[prof] = Quaternion.IDENTITY
			continue
		var dot := clampf(dt.dot(ds), -1.0, 1.0)
		var axis := dt.cross(ds)
		if axis.length() < 0.000001:
			Q[prof] = Quaternion.IDENTITY if dot > 0.0 else Quaternion(Vector3.UP, PI)
		else:
			Q[prof] = Quaternion(axis.normalized(), acos(dot))
		print("  Q %-14s -> %-12s angle=%6.1f deg" % [prof, rigb, rad_to_deg(acos(dot))])

	# ---- bake one validation clip -------------------------------------------
	var src_name := ""
	for n in lap.get_animation_list():
		if String(n).contains("A_TPose"):
			src_name = String(n)
	print("validation source clip = '%s'" % src_name)
	var src: Animation = lap.get_animation(src_name)

	var baked := Animation.new()
	baked.length = src.length
	# sample the source at one instant, convert, write a 1-key track per bone
	var t := 0.1
	# source global rotations at time t
	var sglob := {}
	var tglob := {}
	var order := ["Hips", "Spine", "Chest", "UpperChest", "Neck", "Head",
		"LeftShoulder", "LeftUpperArm", "LeftLowerArm", "LeftHand",
		"RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand",
		"LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "LeftToes",
		"RightUpperLeg", "RightLowerLeg", "RightFoot", "RightToes"]
	# drive the library player so the source skeleton holds the pose
	get_root().add_child(lib)
	lap.play(src_name)
	lap.seek(t, true)
	await process_frame
	await process_frame

	for prof in order:
		var si := ssk.find_bone(prof)
		if si < 0:
			continue
		var g := ssk.get_bone_global_pose(si).basis.get_rotation_quaternion()
		sglob[prof] = g

	for prof in order:
		if not MAP.has(prof):
			continue
		var rigb: String = MAP[prof]
		var ti := tsk.find_bone(rigb)
		var si := ssk.find_bone(prof)
		if ti < 0 or si < 0:
			continue
		# everything lifted into WORLD space so the two armature orientations cancel
		var Rs: Quaternion = (swr * ssk.get_bone_global_rest(si).basis.orthonormalized().get_rotation_quaternion()).normalized()
		var Rt: Quaternion = (twr * tsk.get_bone_global_rest(ti).basis.orthonormalized().get_rotation_quaternion()).normalized()
		var Gs: Quaternion = (swr * (sglob[prof] as Quaternion)).normalized()
		var q: Quaternion = Q[prof]
		# world: G_target = Q * G_source * Rs^-1 * Rt   (Q reconstructs rig A's T-pose)
		var gt_world: Quaternion = (q * Gs * Rs.inverse() * Rt).normalized()
		# back into target skeleton space
		tglob[prof] = (twr.inverse() * gt_world).normalized()

	# convert global -> local under rig A hierarchy and write tracks
	var written := 0
	var skel_path := String(ap.get_node(ap.root_node).get_path_to(tsk))
	for prof in order:
		if not tglob.has(prof):
			continue
		var rigb: String = MAP[prof]
		var ti := tsk.find_bone(rigb)
		var par := tsk.get_bone_parent(ti)
		var pq := Quaternion.IDENTITY
		# nearest mapped ancestor that we computed; else use its rest
		if par >= 0:
			var pname := tsk.get_bone_name(par)
			var pprof := ""
			for k in MAP.keys():
				if MAP[k] == pname:
					pprof = k
			if pprof != "" and tglob.has(pprof):
				pq = tglob[pprof]
			else:
				pq = tsk.get_bone_global_rest(par).basis.get_rotation_quaternion()
		var gq: Quaternion = tglob[prof]
		var local: Quaternion = (pq.inverse() * gq).normalized()
		var tr := baked.add_track(Animation.TYPE_ROTATION_3D)
		baked.track_set_path(tr, NodePath(skel_path + ":" + rigb))
		baked.rotation_track_insert_key(tr, 0.0, local)
		written += 1
	print("baked %d rotation tracks" % written)

	var al := AnimationLibrary.new()
	al.add_animation(&"probe_tpose", baked)
	ap.add_animation_library("bake", al)

	for s in [["rest (no clip)", "", "10_bake_rest.png"],
			["baked T-pose probe", "bake/probe_tpose", "11_bake_tpose.png"]]:
		if String(s[1]) != "":
			ap.play(String(s[1]))
			ap.seek(0.0, true)
		for i in 4:
			await process_frame
		var img := get_root().get_texture().get_image()
		img.save_png(OUT + "/" + String(s[2]))
		print("SHOT %s" % s[2])
	print("DONE")
	quit()
