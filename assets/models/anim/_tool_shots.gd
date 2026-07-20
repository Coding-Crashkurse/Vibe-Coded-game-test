extends SceneTree
## THROWAWAY experiment tool (retarget spike): puts the retargeted rig A sandbox
## copy next to the retargeted animation library, copies the library clips onto
## the character skeleton (track node paths remapped, bone subnames kept) and
## screenshots idle / crouch / reload so the retarget quality can be JUDGED.
## Nothing here touches the shipped characters.

const OUT := "C:/Users/User/AppData/Local/Temp/claude/c--Users-User-Desktop-ja2-remasted/975d617d-579f-4755-b62a-f4617a4062b5/scratchpad/retarget_shots"


func _find(n: Node, t: String) -> Node:
	if n.get_class() == t:
		return n
	for c in n.get_children():
		var r := _find(c, t)
		if r != null:
			return r
	return null


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var root := Node3D.new()
	get_root().add_child(root)

	# --- light + camera --------------------------------------------------
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -35, 0)
	sun.light_energy = 1.4
	root.add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.18, 0.16, 0.14)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.6, 0.65)
	e.ambient_light_energy = 0.8
	env.environment = e
	root.add_child(env)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.1, 3.1)
	cam.rotation_degrees = Vector3(-6, 0, 0)
	root.add_child(cam)

	# --- character (retargeted sandbox copy) ------------------------------
	var chr_scene: PackedScene = load("res://assets/models/anim/rt_swat.glb")
	var chr := chr_scene.instantiate()
	root.add_child(chr)
	var skel := _find(chr, "Skeleton3D") as Skeleton3D
	var ap := _find(chr, "AnimationPlayer") as AnimationPlayer
	print("character: skeleton=%s bones=%d anim=%s" % [skel != null, skel.get_bone_count(), ap != null])

	# --- library ----------------------------------------------------------
	var lib_scene: PackedScene = load("res://assets/models/anim/ual.gltf")
	var lib := lib_scene.instantiate()
	var lap := _find(lib, "AnimationPlayer") as AnimationPlayer

	# target node path of the character skeleton, relative to the AnimationPlayer root
	var ap_root := ap.get_node(ap.root_node)
	var skel_path := String(ap_root.get_path_to(skel))
	print("target skeleton path = '%s'" % skel_path)

	var added := 0
	for src_name in lap.get_animation_list():
		var a: Animation = lap.get_animation(src_name).duplicate(true)
		for ti in a.get_track_count():
			var np := a.track_get_path(ti)
			var bone := np.get_concatenated_subnames()
			if bone == "":
				continue
			# keep the bone, retarget the node path onto the character skeleton
			a.track_set_path(ti, NodePath(skel_path + ":" + String(bone)))
		var libname := String(src_name).get_slice("/", 1) if String(src_name).contains("/") else String(src_name)
		var target_lib: AnimationLibrary = ap.get_animation_library("ual")
		if target_lib == null:
			target_lib = AnimationLibrary.new()
			ap.add_animation_library("ual", target_lib)
		target_lib.add_animation(StringName(libname), a)
		added += 1
	print("copied %d library clips onto the character" % added)
	lib.free()

	# sanity: how many tracks actually resolve to a real bone?
	for probe in ["ual/Crouch_Idle_Loop", "ual/Pistol_Reload"]:
		if not ap.has_animation(probe):
			print("MISSING %s" % probe)
			continue
		var a: Animation = ap.get_animation(probe)
		var hit := 0
		var miss := 0
		var missing_names: Array[String] = []
		for ti in a.get_track_count():
			var b := String(a.track_get_path(ti).get_concatenated_subnames())
			if b == "":
				continue
			if skel.find_bone(b) >= 0:
				hit += 1
			else:
				miss += 1
				if not missing_names.has(b):
					missing_names.append(b)
		print("%s: tracks resolved=%d unresolved=%d  %s" % [probe, hit, miss, str(missing_names)])

	# --- shoot the poses ---------------------------------------------------
	var shots := [
		["character own idle", "CharacterArmature|Idle", "01_own_idle.png"],
		["character own aim", "CharacterArmature|Idle_Gun_Pointing", "02_own_aim.png"],
		["library Idle_Loop", "ual/Idle_Loop", "03_lib_idle.png"],
		["library Crouch_Idle_Loop", "ual/Crouch_Idle_Loop", "04_lib_crouch.png"],
		["library Pistol_Reload", "ual/Pistol_Reload", "05_lib_reload.png"],
		["library A_TPose", "ual/A_TPose", "06_lib_tpose.png"],
	]
	for s in shots:
		var label: String = s[0]
		var clip: String = s[1]
		var file: String = s[2]
		if not ap.has_animation(clip):
			print("SKIP (no clip): %s" % clip)
			continue
		ap.play(clip)
		ap.seek(0.4, true)
		for i in 4:
			await process_frame
		await process_frame
		var img := get_root().get_texture().get_image()
		img.save_png(OUT + "/" + file)
		print("SHOT %s -> %s" % [label, file])
	print("DONE")
	quit()
