extends SceneTree
## THROWAWAY experiment tool (retarget spike). Generates BoneMap .tres files for
## rig A (CharacterArmature) and the Quaternius Universal Animation Library so
## Godot's importer can retarget them onto SkeletonProfileHumanoid.
## Delete together with the spike if the experiment is abandoned.

const RIG_A := {
	"Root": "Root",
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
	"LeftThumbProximal": "Thumb1.L", "LeftThumbDistal": "Thumb2.L",
	"LeftIndexProximal": "Index1.L", "LeftIndexIntermediate": "Index2.L", "LeftIndexDistal": "Index3.L",
	"LeftMiddleProximal": "Middle1.L", "LeftMiddleIntermediate": "Middle2.L", "LeftMiddleDistal": "Middle3.L",
	"LeftRingProximal": "Ring1.L", "LeftRingIntermediate": "Ring2.L", "LeftRingDistal": "Ring3.L",
	"LeftLittleProximal": "Pinky1.L", "LeftLittleIntermediate": "Pinky2.L", "LeftLittleDistal": "Pinky3.L",
	"RightThumbProximal": "Thumb1.R", "RightThumbDistal": "Thumb2.R",
	"RightIndexProximal": "Index1.R", "RightIndexIntermediate": "Index2.R", "RightIndexDistal": "Index3.R",
	"RightMiddleProximal": "Middle1.R", "RightMiddleIntermediate": "Middle2.R", "RightMiddleDistal": "Middle3.R",
	"RightRingProximal": "Ring1.R", "RightRingIntermediate": "Ring2.R", "RightRingDistal": "Ring3.R",
	"RightLittleProximal": "Pinky1.R", "RightLittleIntermediate": "Pinky2.R", "RightLittleDistal": "Pinky3.R",
}

const UAL := {
	"Root": "root",
	"Hips": "DEF-hips", "Spine": "DEF-spine.001", "Chest": "DEF-spine.002", "UpperChest": "DEF-spine.003",
	"Neck": "DEF-neck", "Head": "DEF-head",
	"LeftShoulder": "DEF-shoulder.L", "LeftUpperArm": "DEF-upper_arm.L",
	"LeftLowerArm": "DEF-forearm.L", "LeftHand": "DEF-hand.L",
	"RightShoulder": "DEF-shoulder.R", "RightUpperArm": "DEF-upper_arm.R",
	"RightLowerArm": "DEF-forearm.R", "RightHand": "DEF-hand.R",
	"LeftUpperLeg": "DEF-thigh.L", "LeftLowerLeg": "DEF-shin.L",
	"LeftFoot": "DEF-foot.L", "LeftToes": "DEF-toe.L",
	"RightUpperLeg": "DEF-thigh.R", "RightLowerLeg": "DEF-shin.R",
	"RightFoot": "DEF-foot.R", "RightToes": "DEF-toe.R",
	"LeftThumbProximal": "DEF-thumb.01.L", "LeftThumbDistal": "DEF-thumb.02.L",
	"LeftIndexProximal": "DEF-f_index.01.L", "LeftIndexIntermediate": "DEF-f_index.02.L", "LeftIndexDistal": "DEF-f_index.03.L",
	"LeftMiddleProximal": "DEF-f_middle.01.L", "LeftMiddleIntermediate": "DEF-f_middle.02.L", "LeftMiddleDistal": "DEF-f_middle.03.L",
	"LeftRingProximal": "DEF-f_ring.01.L", "LeftRingIntermediate": "DEF-f_ring.02.L", "LeftRingDistal": "DEF-f_ring.03.L",
	"LeftLittleProximal": "DEF-f_pinky.01.L", "LeftLittleIntermediate": "DEF-f_pinky.02.L", "LeftLittleDistal": "DEF-f_pinky.03.L",
	"RightThumbProximal": "DEF-thumb.01.R", "RightThumbDistal": "DEF-thumb.02.R",
	"RightIndexProximal": "DEF-f_index.01.R", "RightIndexIntermediate": "DEF-f_index.02.R", "RightIndexDistal": "DEF-f_index.03.R",
	"RightMiddleProximal": "DEF-f_middle.01.R", "RightMiddleIntermediate": "DEF-f_middle.02.R", "RightMiddleDistal": "DEF-f_middle.03.R",
	"RightRingProximal": "DEF-f_ring.01.R", "RightRingIntermediate": "DEF-f_ring.02.R", "RightRingDistal": "DEF-f_ring.03.R",
	"RightLittleProximal": "DEF-f_pinky.01.R", "RightLittleIntermediate": "DEF-f_pinky.02.R", "RightLittleDistal": "DEF-f_pinky.03.R",
}


func _make(tbl: Dictionary, path: String) -> void:
	var prof := SkeletonProfileHumanoid.new()
	var bm := BoneMap.new()
	bm.profile = prof
	var mapped := 0
	var unknown: Array[String] = []
	for slot in tbl.keys():
		var idx := prof.find_bone(StringName(slot))
		if idx < 0:
			unknown.append(String(slot))
			continue
		bm.set_skeleton_bone_name(StringName(slot), StringName(tbl[slot]))
		mapped += 1
	var err := ResourceSaver.save(bm, path)
	print("BONEMAP %s: mapped=%d/%d unknown_slots=%s err=%d"
		% [path, mapped, tbl.size(), str(unknown), err])
	# report profile slots left empty
	var empty: Array[String] = []
	for i in prof.bone_size:
		var nm := prof.get_bone_name(i)
		if String(bm.get_skeleton_bone_name(nm)) == "":
			empty.append(String(nm))
	print("   unmapped profile slots (%d): %s" % [empty.size(), ", ".join(empty)])


func _init() -> void:
	_make(RIG_A, "res://assets/models/anim/bonemap_riga.tres")
	_make(UAL, "res://assets/models/anim/bonemap_ual.tres")
	quit()
